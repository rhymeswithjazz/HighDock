import Foundation

public enum DockEdge: String, Codable, CaseIterable, Sendable {
    case left, bottom, right
}

public struct DockSettings: Codable, Equatable, Sendable {
    public var edge: DockEdge
    public var autoHide: Bool
    public init(edge: DockEdge = .bottom, autoHide: Bool = false) {
        self.edge = edge
        self.autoHide = autoHide
    }
}

public struct Display: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var primary: Bool
    public var mirrorOf: String?
    public init(id: String, name: String = "Display", x: Double, y: Double, width: Double, height: Double, primary: Bool = false, mirrorOf: String? = nil) {
        self.id = id; self.name = name; self.x = x; self.y = y
        self.width = width; self.height = height; self.primary = primary; self.mirrorOf = mirrorOf
    }
}

public struct DisplayLayout: Codable, Equatable, Sendable {
    public var displays: [Display]
    public init(displays: [Display]) { self.displays = displays }
    public var signature: String? {
        guard !displays.isEmpty,
              displays.allSatisfy({ !$0.id.isEmpty && $0.width > 0 && $0.height > 0 && [$0.x, $0.y, $0.width, $0.height].allSatisfy(\.isFinite) }),
              Set(displays.map(\.id)).count == displays.count else { return nil }
        let minX = displays.map(\.x).min()!, minY = displays.map(\.y).min()!
        let rows = displays.sorted { $0.id < $1.id }.map {
            [$0.id, String($0.x - minX), String($0.y - minY), String($0.width), String($0.height), String($0.primary), $0.mirrorOf ?? ""]
        }
        return String(data: try! JSONEncoder().encode(rows), encoding: .utf8)
    }
}

public struct Setup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var layout: DisplayLayout
    public var settings: DockSettings
    public init(id: UUID = UUID(), name: String, layout: DisplayLayout, settings: DockSettings) {
        self.id = id; self.name = name; self.layout = layout; self.settings = settings
    }
}

public struct SetupFile: Codable, Equatable, Sendable {
    public var version = 1
    public var setups: [Setup]
    public init(setups: [Setup] = []) { self.setups = setups }
}

public struct SetupStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [Setup] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try JSONDecoder().decode(SetupFile.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw StoreError.unsupportedVersion }
        guard Set(file.setups.map(\.id)).count == file.setups.count,
              file.setups.allSatisfy({ $0.layout.signature != nil }),
              Set(file.setups.compactMap { $0.layout.signature }).count == file.setups.count else { throw StoreError.invalidData }
        return file.setups
    }
    public func save(_ setups: [Setup]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(SetupFile(setups: setups)).write(to: url, options: .atomic)
    }
    public enum StoreError: LocalizedError {
        case unsupportedVersion, invalidData
        public var errorDescription: String? { "Saved setups could not be read. The existing file has been kept unchanged." }
    }
}

public struct SwitchingPolicy: Sendable {
    public private(set) var lastSignature: String?
    public var paused = false
    public init() {}
    public mutating func activate(_ layout: DisplayLayout, setups: [Setup], force: Bool = false) -> DockSettings? {
        let signature = layout.signature
        let changed = signature != lastSignature
        lastSignature = signature
        guard !paused, let signature, changed || force else { return nil }
        return setups.first { $0.layout.signature == signature }?.settings
    }
}
