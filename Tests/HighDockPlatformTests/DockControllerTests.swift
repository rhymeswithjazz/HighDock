import Foundation
import Synchronization
import Testing
import HighDockCore
@testable import HighDockPlatform

private final class FakeDock: Sendable {
    struct State {
        var settings = DockSettings()
        var writes: [[String]] = []
        var restarts = 0
        var failWrite = false
        var ignoreWrite = false
    }
    let state = Mutex(State())
    func run(_ path: String, _ arguments: [String]) throws -> Data {
        try state.withLock { value in
            if arguments.first == "export" {
                return try PropertyListSerialization.data(fromPropertyList: ["orientation": value.settings.edge.rawValue, "autohide": value.settings.autoHide, "tilesize": 53], format: .xml, options: 0)
            }
            if path.hasSuffix("killall") { value.restarts += 1; return Data() }
            if value.failWrite { throw DockError.command("Test write failure") }
            value.writes.append(arguments)
            if !value.ignoreWrite {
                if arguments[2] == "orientation" { value.settings.edge = DockEdge(rawValue: arguments[4])! }
                if arguments[2] == "autohide" { value.settings.autoHide = arguments[4] == "true" }
            }
            return Data()
        }
    }
    var controller: DockController {
        DockController(command: { [self] in try run($0, $1) }, runningDock: { [self] in Int32(100 + state.withLock { $0.restarts }) })
    }
}

@Test func matchingSettingsDoNotWriteOrRestart() async throws {
    let fake = FakeDock()
    try await fake.controller.apply(DockSettings())
    #expect(fake.state.withLock { $0.writes.isEmpty && $0.restarts == 0 })
}
@Test func onlyChangedDockKeysAreWrittenWithOneRestart() async throws {
    let fake = FakeDock()
    try await fake.controller.apply(DockSettings(edge: .left, autoHide: true))
    let writes = fake.state.withLock { $0.writes }
    #expect(writes.map { $0[2] } == ["orientation", "autohide"])
    #expect(fake.state.withLock { $0.restarts } == 1)
}
@Test func edgeOnlyChangePreservesHiding() async throws {
    let fake = FakeDock()
    try await fake.controller.apply(DockSettings(edge: .right))
    #expect(fake.state.withLock { $0.writes.map { $0[2] } } == ["orientation"])
}
@Test func failedWritesAreReportedWithoutRestart() async {
    let fake = FakeDock()
    fake.state.withLock { $0.failWrite = true }
    await #expect(throws: DockError.self) { try await fake.controller.apply(DockSettings(edge: .left)) }
    #expect(fake.state.withLock { $0.restarts } == 0)
}
@Test func ignoredWritesCannotReportSuccess() async {
    let fake = FakeDock()
    fake.state.withLock { $0.ignoreWrite = true }
    await #expect(throws: DockError.self) { try await fake.controller.apply(DockSettings(edge: .left)) }
}
