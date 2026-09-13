import Foundation
import Testing
import HighDockCore
import HighDockPlatform
@testable import HighDock

private actor MemoryDock: DockControlling {
    var settings = DockSettings()
    var applications: [DockSettings] = []
    func read() -> DockSettings { settings }
    func apply(_ settings: DockSettings) { self.settings = settings; applications.append(settings) }
    func changeManually(_ settings: DockSettings) { self.settings = settings }
}

@MainActor
@Test func animationToggleRestoresCustomTimingAcrossSaveAndReload() async throws {
    let f = Fixture(); defer { f.clean() }
    await f.dock.changeManually(DockSettings(autoHide: true, animation: DockAnimation(timeModifier: 0.25)))
    let model = try f.model()
    try await f.settle(model)
    model.draftAnimationEnabled = false
    model.save()
    try await f.settle(model)
    await model.loadDraft()
    #expect(model.draftSettings.animation == DockAnimation(enabled: false, timeModifier: 0.25))
    model.draftAnimationEnabled = true
    model.save()
    try await f.settle(model)
    #expect(try f.store.load().first?.settings.animation == DockAnimation(timeModifier: 0.25))
}

@MainActor
@Test func olderSetupInheritsTimingWithoutManagingItUntilEdited() async throws {
    let f = Fixture(); defer { f.clean() }
    await f.dock.changeManually(DockSettings(animation: DockAnimation(enabled: false)))
    let setup = Setup(name: "Desk", layout: f.desk, settings: DockSettings(autoHide: true))
    let model = try f.model(setups: [setup])
    try await f.settle(model)
    model.selectedID = setup.id
    await model.loadDraft()
    #expect(!model.draftAnimationEnabled)
    model.save()
    #expect(try f.store.load().first?.settings.animation == nil)
    model.draftAnimationEnabled = true
    model.save()
    #expect(try f.store.load().first?.settings.animation == DockAnimation())
    #expect(await f.dock.applications.isEmpty)
}

@MainActor
private final class Fixture {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let dock = MemoryDock()
    let laptop = DisplayLayout(displays: [Display(id: "laptop", x: 0, y: 0, width: 1440, height: 900, primary: true)])
    let desk = DisplayLayout(displays: [Display(id: "external", x: 0, y: 0, width: 2560, height: 1440, primary: true)])
    var current: DisplayLayout
    var store: SetupStore { SetupStore(url: folder.appending(path: "setups.json")) }
    init() {
        current = DisplayLayout(displays: [Display(id: "laptop", x: 0, y: 0, width: 1440, height: 900, primary: true)])
    }
    func model(setups: [Setup] = []) throws -> AppModel {
        try store.save(setups)
        let defaults = UserDefaults(suiteName: "HighDockTests.\(UUID().uuidString)")!
        return AppModel(store: store, dock: dock, displayReader: { [self] in current }, settleDuration: .milliseconds(30), preferences: defaults, observeSystem: false)
    }
    func settle(_ model: AppModel) async throws {
        for _ in 0..<100 {
            if !model.settling && !model.applying { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Model did not settle")
    }
    func clean() { try? FileManager.default.removeItem(at: folder) }
}

@MainActor
@Test func unfamiliarLayoutDoesNotCreateOrApplySetup() async throws {
    let f = Fixture(); defer { f.clean() }
    let model = try f.model()
    try await f.settle(model)
    #expect(model.setups.isEmpty)
    #expect(model.activeSetup == nil)
    #expect(await f.dock.applications.isEmpty)
}

@MainActor
@Test func currentSavePersistsAndApplies() async throws {
    let f = Fixture(); defer { f.clean() }
    let model = try f.model()
    try await f.settle(model)
    model.draftName = "Laptop"
    model.draftSettings = DockSettings(edge: .right, autoHide: true)
    model.save()
    try await f.settle(model)
    #expect(try f.store.load().first?.name == "Laptop")
    #expect(await f.dock.applications == [DockSettings(edge: .right, autoHide: true)])
}

@MainActor
@Test func editingDisconnectedSetupDoesNotTouchDock() async throws {
    let f = Fixture(); defer { f.clean() }
    let setup = Setup(name: "Desk", layout: f.desk, settings: DockSettings(edge: .left))
    let model = try f.model(setups: [setup])
    try await f.settle(model)
    model.selectedID = setup.id
    await model.loadDraft()
    model.draftName = "Studio"
    model.draftSettings.autoHide = true
    model.save()
    #expect(try f.store.load().first?.name == "Studio")
    #expect(try f.store.load().first?.settings.autoHide == true)
    #expect(await f.dock.applications.isEmpty)
}

@MainActor
@Test func wakePreservesManualOverrideAndReturnRestoresSavedSettings() async throws {
    let f = Fixture(); defer { f.clean() }
    let saved = DockSettings(edge: .left)
    let model = try f.model(setups: [Setup(name: "Laptop", layout: f.laptop, settings: saved)])
    try await f.settle(model)
    await f.dock.changeManually(DockSettings(edge: .right))
    model.scheduleRefresh()
    try await f.settle(model)
    #expect(await f.dock.read().edge == .right)
    f.current = f.desk; model.scheduleRefresh(); try await f.settle(model)
    f.current = f.laptop; model.scheduleRefresh(); try await f.settle(model)
    #expect(await f.dock.read() == saved)
    #expect(await f.dock.applications.count == 2)
}

@MainActor
@Test func rapidConnectionEventsApplyOnlyTheSettledLayout() async throws {
    let f = Fixture(); defer { f.clean() }
    let model = try f.model(setups: [Setup(name: "Laptop", layout: f.laptop, settings: DockSettings(edge: .left)), Setup(name: "Desk", layout: f.desk, settings: DockSettings(edge: .right))])
    for index in 0..<10 {
        f.current = index.isMultiple(of: 2) ? f.laptop : f.desk
        model.scheduleRefresh()
        try await Task.sleep(for: .milliseconds(2))
    }
    try await f.settle(model)
    #expect(await f.dock.applications == [DockSettings(edge: .right)])
}

@MainActor
@Test func pauseThenResumeReappliesCurrentSetup() async throws {
    let f = Fixture(); defer { f.clean() }
    let model = try f.model(setups: [Setup(name: "Desk", layout: f.desk, settings: DockSettings(edge: .right))])
    try await f.settle(model)
    model.togglePause()
    f.current = f.desk; model.scheduleRefresh(); try await f.settle(model)
    #expect(await f.dock.applications.isEmpty)
    model.togglePause()
    model.scheduleRefresh()
    try await f.settle(model)
    #expect(await f.dock.applications == [DockSettings(edge: .right)])
}

@MainActor
@Test func deletingActiveSetupLeavesDockUntouched() async throws {
    let f = Fixture(); defer { f.clean() }
    let model = try f.model(setups: [Setup(name: "Laptop", layout: f.laptop, settings: DockSettings(edge: .left))])
    try await f.settle(model)
    model.deleteSelected()
    model.scheduleRefresh(force: true)
    try await f.settle(model)
    #expect(model.setups.isEmpty)
    #expect(try f.store.load().isEmpty)
    #expect(await f.dock.applications.count == 1)
}

@MainActor
@Test func mainDisplayChangeKeepsSetupConnectedWithoutReapplying() async throws {
    let f = Fixture(); defer { f.clean() }
    let original = DisplayLayout(displays: [
        Display(id: "laptop", x: 0, y: 0, width: 1440, height: 900, primary: true),
        Display(id: "left", x: -1920, y: -1440, width: 2560, height: 1440),
        Display(id: "right", x: 640, y: -1440, width: 2560, height: 1440)
    ])
    f.current = original
    let model = try f.model()
    try await f.settle(model)
    model.draftSettings = DockSettings(edge: .left, mainDisplayID: "left")
    model.save()
    try await f.settle(model)
    let savedID = try #require(model.selectedID)
    f.current = try #require(original.makingPrimary("left"))
    model.scheduleRefresh()
    try await f.settle(model)
    #expect(model.activeSetup?.id == savedID)
    #expect(model.editingCurrent)
    #expect(await f.dock.applications.count == 1)
    model.draftName = "Work"
    model.save()
    try await f.settle(model)
    #expect(try f.store.load().first?.layout == original)
    model.draftSettings.mainDisplayID = "right"
    model.save()
    try await f.settle(model)
    #expect(await f.dock.applications.last?.mainDisplayID == "right")
    f.current = try #require(original.makingPrimary("right"))
    model.scheduleRefresh()
    try await f.settle(model)
    #expect(model.activeSetup?.id == savedID)
    model.draftSettings.mainDisplayID = nil
    model.save()
    try await f.settle(model)
    #expect(model.activeSetup?.id == savedID)
    #expect(try f.store.load().first?.layout == f.current)
}
