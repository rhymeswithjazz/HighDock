import AppKit
import Observation
import ServiceManagement
import HighDockCore
import HighDockPlatform

@MainActor @Observable
final class AppModel {
    var setups: [Setup] = []
    var layout = DisplayLayout(displays: [])
    var selectedID: UUID?
    var draftName = ""
    var draftSettings = DockSettings()
    var paused: Bool
    var applying = false
    var error: String?
    var status = ""
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    var storageAvailable = true
    private let store: SetupStore
    private let dock: any DockControlling
    private let displayReader: @MainActor () -> DisplayLayout
    private let settleDuration: Duration
    private let preferences: UserDefaults
    private var policy = SwitchingPolicy()
    private var debounce: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var pendingSettings: (settings: DockSettings, signature: String, generation: Int)?
    private var forceRefresh = false
    var settling = true
    private var failedLoginChange: Bool?
    private var failedSave = false
    private var failedDeletion: UUID?
    private var refreshGeneration = 0

    var activeSetup: Setup? {
        guard let signature = layout.signature else { return nil }
        return setups.first { $0.layout.signature == signature }
    }
    var selectedSetup: Setup? { setups.first { $0.id == selectedID } }
    var displayedLayout: DisplayLayout { selectedSetup?.layout ?? layout }
    var editingCurrent: Bool { selectedID == nil || selectedSetup?.layout.signature == layout.signature }
    var canSave: Bool {
        storageAvailable && !applying && !settling && displayedLayout.signature != nil && !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(store: SetupStore = SetupStore(url: URL.applicationSupportDirectory.appending(path: "HighDock/setups.json")),
         dock: any DockControlling = DockController(),
         displayReader: @escaping @MainActor () -> DisplayLayout = DisplayReader.read,
         settleDuration: Duration = .seconds(1),
         preferences: UserDefaults = .standard,
         observeSystem: Bool = true) {
        self.store = store; self.dock = dock; self.displayReader = displayReader
        self.settleDuration = settleDuration; self.preferences = preferences
        paused = preferences.bool(forKey: "paused")
        do { setups = try store.load() }
        catch { storageAvailable = false; self.error = error.localizedDescription }
        policy.paused = paused
        if observeSystem {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        }
        scheduleRefresh(force: true)
    }

    func scheduleRefresh(force: Bool = false) {
        debounce?.cancel()
        settling = true
        forceRefresh = forceRefresh || force
        refreshGeneration += 1
        let generation = refreshGeneration
        let delay = settleDuration
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            let shouldForce = self.forceRefresh
            let previous = self.layout.signature
            self.layout = self.displayReader()
            if previous != self.layout.signature || shouldForce {
                self.selectedID = self.activeSetup?.id
                await self.loadDraft()
            }
            guard !Task.isCancelled, generation == self.refreshGeneration else { return }
            self.forceRefresh = false
            self.settling = false
            self.pendingSettings = nil
            if let settings = self.policy.activate(self.layout, setups: self.setups, force: shouldForce) {
                self.requestApply(settings)
            }
        }
    }

    func select(_ id: UUID?) {
        selectedID = id
        Task { await loadDraft() }
    }
    func loadDraft() async {
        if let setup = selectedSetup {
            draftName = setup.name; draftSettings = setup.settings
        } else {
            draftName = layout.displays.count == 1 ? (layout.displays.first?.name ?? "My Mac") : "My desk"
            let signature = layout.signature
            do {
                let settings = try await dock.read()
                guard selectedID == nil, signature == layout.signature else { return }
                draftSettings = settings
            } catch { self.error = error.localizedDescription }
        }
        status = ""
    }
    func save() {
        guard canSave else { return }
        let setup = Setup(id: selectedID ?? UUID(), name: draftName.trimmingCharacters(in: .whitespacesAndNewlines), layout: displayedLayout, settings: draftSettings)
        var updated = setups
        if let index = updated.firstIndex(where: { $0.id == setup.id }) { updated[index] = setup }
        else if let index = updated.firstIndex(where: { $0.layout.signature == setup.layout.signature }) {
            updated[index].name = setup.name; updated[index].settings = setup.settings
        } else { updated.append(setup) }
        do {
            try store.save(updated)
            failedSave = false
            setups = updated
            selectedID = updated.first { $0.layout.signature == setup.layout.signature }?.id
            error = nil
            if editingCurrent { requestApply(setup.settings) }
            else { status = "Saved for the next time you connect." }
        } catch { failedSave = true; self.error = error.localizedDescription }
    }
    func deleteSelected() {
        guard let id = selectedID, !applying else { return }
        delete(id)
    }
    private func delete(_ id: UUID) {
        do {
            let updated = setups.filter { $0.id != id }
            try store.save(updated); setups = updated
            failedDeletion = nil; error = nil
            select(activeSetup?.id)
        } catch { failedDeletion = id; self.error = error.localizedDescription }
    }
    func togglePause() {
        paused.toggle()
        preferences.set(paused, forKey: "paused")
        policy.paused = paused
        if paused { pendingSettings = nil }
        else { scheduleRefresh(force: true) }
    }
    func retry() {
        if let enabled = failedLoginChange { setLaunchAtLogin(enabled) }
        else if failedSave { save() }
        else if let id = failedDeletion { delete(id) }
        else if !storageAvailable {
            do { setups = try store.load(); storageAvailable = true; error = nil; scheduleRefresh(force: true) }
            catch { self.error = error.localizedDescription }
        } else if let setup = activeSetup { requestApply(setup.settings) }
        else { error = nil; scheduleRefresh() }
    }
    func requestApply(_ settings: DockSettings) {
        guard let signature = layout.signature else { return }
        pendingSettings = (settings, signature, refreshGeneration)
        guard !applying else { return }
        applying = true
        Task {
            while let next = pendingSettings {
                pendingSettings = nil
                guard next.signature == layout.signature, next.generation == refreshGeneration, !settling else { continue }
                do {
                    try await dock.apply(next.settings)
                    error = nil
                    status = "Dock settings applied."
                } catch {
                    self.error = error.localizedDescription
                    status = ""
                }
            }
            applying = false
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil; failedLoginChange = nil
        } catch { failedLoginChange = enabled; self.error = error.localizedDescription }
        refreshLoginStatus()
    }
    func refreshLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
