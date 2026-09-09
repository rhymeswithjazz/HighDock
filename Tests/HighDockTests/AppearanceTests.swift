import AppKit
import SwiftUI
import Foundation
import Testing
import HighDockCore
import HighDockPlatform
@testable import HighDock

private actor PreviewDock: DockControlling {
    func read() -> DockSettings { DockSettings() }
    func apply(_ settings: DockSettings) {}
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["HIGHDOCK_RENDER_PREVIEWS"] == "1"))
func renderAppearanceChecks() async throws {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "build/previews")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    let layout = DisplayLayout(displays: [
        Display(id: "external", name: "Studio Display", x: 0, y: 0, width: 2560, height: 1440, primary: true),
        Display(id: "laptop", name: "MacBook Pro", x: -1512, y: 458, width: 1512, height: 982)
    ])
    let store = SetupStore(url: temp.appending(path: "setups.json"))
    try store.save([Setup(name: "Studio", layout: layout, settings: DockSettings(edge: .left, autoHide: true))])
    let model = AppModel(store: store, dock: PreviewDock(), displayReader: { layout }, settleDuration: .milliseconds(1), preferences: UserDefaults(suiteName: "HighDockPreview")!, observeSystem: false)
    try await Task.sleep(for: .milliseconds(100))
    for variant in ["light", "dark", "contrast"] {
        let root = MainView(model: model)
            .environment(\.colorScheme, variant == "dark" ? .dark : .light)
            .frame(width: 860, height: 620)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : (variant == "contrast" ? .accessibilityHighContrastAqua : .aqua))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appending(path: "\(variant).png"))
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        window.contentView = nil
    }
}
