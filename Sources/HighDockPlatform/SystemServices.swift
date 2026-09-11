import AppKit
import CoreGraphics
import HighDockCore

@MainActor
public struct DisplayReader {
    public static func read() -> DisplayLayout {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return DisplayLayout(displays: []) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return DisplayLayout(displays: []) }
        ids = Array(ids.prefix(Int(count))).filter { CGDisplayIsActive($0) != 0 || CGDisplayIsInMirrorSet($0) != 0 }
        func identity(_ id: CGDirectDisplayID) -> String {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
            return CFUUIDCreateString(nil, uuid) as String
        }
        let screens = NSScreen.screens
        return DisplayLayout(displays: ids.map { id in
            let screen = screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let bounds = CGDisplayBounds(id)
            let mirror = CGDisplayMirrorsDisplay(id)
            return Display(id: identity(id), name: screen?.localizedName ?? "Mirrored display",
                           x: bounds.minX, y: bounds.minY,
                           width: Double(screen?.frame.width ?? bounds.width), height: Double(screen?.frame.height ?? bounds.height),
                           primary: id == CGMainDisplayID(), mirrorOf: mirror == kCGNullDirectDisplay ? nil : identity(mirror))
        })
    }
}

struct Command {
    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw DockError.command(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}

enum DockError: LocalizedError {
    case command(String), verification
    var errorDescription: String? {
        switch self {
        case .command(let message): "Could not update the Dock. \(message)"
        case .verification: "The Dock did not confirm the change. Try again."
        }
    }
}

public protocol DockControlling: Sendable {
    func read() async throws -> DockSettings
    func apply(_ settings: DockSettings) async throws
}

public actor DockController: DockControlling {
    let command: @Sendable (String, [String]) throws -> Data
    let runningDock: @MainActor @Sendable () -> Int32?
    let selectMainDisplay: @MainActor @Sendable (String) throws -> Void

    public init() {
        command = Command.run
        selectMainDisplay = MainDisplayController.select
        runningDock = {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                .first { $0.isFinishedLaunching }?.processIdentifier
        }
    }
    init(command: @escaping @Sendable (String, [String]) throws -> Data, runningDock: @escaping @MainActor @Sendable () -> Int32?,
         selectMainDisplay: @escaping @MainActor @Sendable (String) throws -> Void = MainDisplayController.select) {
        self.command = command; self.runningDock = runningDock
        self.selectMainDisplay = selectMainDisplay
    }
    private var busy = false
    public func read() throws -> DockSettings {
        let data = try command("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
        let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        return DockSettings(edge: DockEdge(rawValue: values["orientation"] as? String ?? "bottom") ?? .bottom,
                            autoHide: (values["autohide"] as? NSNumber)?.boolValue ?? false)
    }
    public func apply(_ settings: DockSettings) async throws {
        while busy { try await Task.sleep(for: .milliseconds(50)) }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        if let id = settings.mainDisplayID { try await selectMainDisplay(id) }
        let current = try read()
        guard current.edge != settings.edge || current.autoHide != settings.autoHide else { return }
        if current.edge != settings.edge {
            _ = try command("/usr/bin/defaults", ["write", "com.apple.dock", "orientation", "-string", settings.edge.rawValue])
        }
        if current.autoHide != settings.autoHide {
            _ = try command("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", settings.autoHide ? "true" : "false"])
        }
        let oldPID = await runningDock()
        _ = try command("/usr/bin/killall", ["-u", NSUserName(), "Dock"])
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(100))
            let newPID = await runningDock()
            let restarted = newPID != nil && newPID != oldPID
            if restarted {
                let actual = try read()
                if actual.edge == settings.edge && actual.autoHide == settings.autoHide { return }
            }
        }
        throw DockError.verification
    }
}
