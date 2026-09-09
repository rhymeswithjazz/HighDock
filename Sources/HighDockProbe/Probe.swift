import Foundation
import AppKit
import HighDockCore
import HighDockPlatform

@main
struct Probe {
    static func snapshot() throws -> [String: Any] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", "com.apple.dock", "-"]
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProbeError.failed }
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }
    static func main() async throws {
        let dock = DockController()
        let current = try await dock.read()
        let layout = await MainActor.run { DisplayReader.read() }
        print("Displays: \(layout.displays.count), unambiguous: \(layout.signature != nil)")
        for display in layout.displays { print("  \(display.name): \(display.width) × \(display.height), primary: \(display.primary)") }
        print("Dock: \(current.edge.rawValue), auto-hide: \(current.autoHide)")
        guard CommandLine.arguments.contains("--exercise-dock") else { return }
        let before = try snapshot()
        let backupURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "build/dock-before.plist")
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: before, format: .xml, options: 0).write(to: backupURL)
        do {
            try await dock.apply(DockSettings(edge: current.edge == .left ? .right : .left, autoHide: !current.autoHide))
            print("Alternate settings applied and Dock restart verified.")
            try await dock.apply(current)
            print("Original settings restored and Dock restart verified.")
        } catch {
            try await dock.apply(current)
            throw error
        }
        var original = before, after = try snapshot()
        for key in ["orientation", "autohide", "mod-count", "last-analytics-stamp", "lastShowIndicatorTime"] {
            original.removeValue(forKey: key); after.removeValue(forKey: key)
        }
        let changed = Set(original.keys).union(after.keys).filter { key in
            !NSDictionary(dictionary: ["value": original[key] ?? NSNull()]).isEqual(to: ["value": after[key] ?? NSNull()])
        }
        guard changed.isEmpty else {
            print("Other Dock keys changed during the check: \(changed.sorted().joined(separator: ", "))")
            throw ProbeError.failed
        }
        print("PASS: size, magnification, pinned apps, and all other checked preferences are unchanged.")
    }
    enum ProbeError: Error { case failed }
}
