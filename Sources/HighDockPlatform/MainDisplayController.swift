import AppKit
import CoreGraphics
import Foundation
import HighDockCore

@MainActor
enum MainDisplayController {
    static func select(_ id: String) throws {
        let layout = DisplayReader.read()
        guard let planned = layout.makingPrimary(id) else { throw Failure.unavailable }
        guard layout.displays.first(where: { $0.id == id })?.primary != true else { return }
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count))
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count))
        var displayIDs: [String: CGDirectDisplayID] = [:]
        for displayID in ids.prefix(Int(count)) {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { continue }
            displayIDs[CFUUIDCreateString(nil, uuid) as String] = displayID
        }
        let origins = try planned.displays.filter { $0.mirrorOf == nil }.map { display in
            guard let displayID = displayIDs[display.id],
                  let x = Int32(exactly: display.x), let y = Int32(exactly: display.y) else { throw Failure.unavailable }
            return (displayID, x, y)
        }
        var configuration: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&configuration))
        var committed = false
        defer { if !committed { CGCancelDisplayConfiguration(configuration) } }
        for (displayID, x, y) in origins {
            try check(CGConfigureDisplayOrigin(configuration, displayID, x, y))
        }
        let result = CGCompleteDisplayConfiguration(configuration, .forSession)
        committed = true
        try check(result)
        guard DisplayReader.read().signature == planned.signature else { throw Failure.verification }
    }

    private static func check(_ error: CGError) throws {
        guard error == .success else { throw Failure.configuration(error.rawValue) }
    }

    enum Failure: LocalizedError {
        case unavailable, configuration(Int32), verification
        var errorDescription: String? {
            switch self {
            case .unavailable: "The selected main display is unavailable. Reconnect it or choose another display."
            case .configuration(let code): "macOS could not change the main display (error \(code))."
            case .verification: "macOS did not confirm the requested main display and arrangement. Check Displays in System Settings."
            }
        }
    }
}
