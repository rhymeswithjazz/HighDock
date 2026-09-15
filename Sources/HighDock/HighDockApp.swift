import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let softwareUpdater = SoftwareUpdater()
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        softwareUpdater.start()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") { showWindow() }
        UserDefaults.standard.set(true, forKey: "hasLaunched")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func showWindow() {
        model.scheduleRefresh()
        if windowController == nil {
            let host = NSHostingController(rootView: MainView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "HighDock"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 860, height: 700))
            window.contentMinSize = NSSize(width: 740, height: 680)
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("HighDockMain")
            window.center()
            windowController = NSWindowController(window: window)
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct HighDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("HighDock", systemImage: "dock.rectangle") {
            AppMenu(model: delegate.model, softwareUpdater: delegate.softwareUpdater, showWindow: delegate.showWindow)
        }
    }
}

struct AppMenu: View {
    @Bindable var model: AppModel
    @ObservedObject var softwareUpdater: SoftwareUpdater
    let showWindow: () -> Void
    var body: some View {
        Text(model.activeSetup?.name ?? "Unsaved setup")
        if model.applying { Text("Applying Dock settings…") }
        if model.error != nil { Text("HighDock needs attention") }
        Divider()
        Button("Open HighDock", action: showWindow).keyboardShortcut("o")
        Button(model.paused ? "Resume Automatic Switching" : "Pause Automatic Switching") { model.togglePause() }
        Divider()
        if softwareUpdater.isEnabled {
            Button("Check for Updates…") { softwareUpdater.checkForUpdates() }
                .disabled(!softwareUpdater.canCheckForUpdates)
            Toggle("Check for Updates Automatically", isOn: Binding(
                get: { softwareUpdater.automaticallyChecksForUpdates },
                set: { softwareUpdater.setAutomaticallyChecks($0) }))
            Toggle("Include Test Builds", isOn: $softwareUpdater.includeTestBuilds)
        } else {
            Text("Updates disabled in development builds")
        }
        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
        Divider()
        Button("Quit HighDock") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
