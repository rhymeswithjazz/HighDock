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
                var preferences: [String: Any] = ["orientation": value.settings.edge.rawValue, "autohide": value.settings.autoHide, "tilesize": 53, "autohide-delay": 0.7]
                if let modifier = value.settings.animation?.effectiveTimeModifier {
                    preferences["autohide-time-modifier"] = modifier
                }
                return try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
            }
            if path.hasSuffix("killall") { value.restarts += 1; return Data() }
            if value.failWrite { throw DockError.command("Test write failure") }
            value.writes.append(arguments)
            if !value.ignoreWrite {
                if arguments[2] == "orientation" { value.settings.edge = DockEdge(rawValue: arguments[4])! }
                if arguments[2] == "autohide" { value.settings.autoHide = arguments[4] == "true" }
                if arguments[2] == "autohide-time-modifier" {
                    let modifier = arguments[0] == "delete" ? nil : Double(arguments[4])
                    value.settings.animation = DockAnimation(enabled: modifier != 0, timeModifier: modifier == 0 ? nil : modifier)
                }
            }
            return Data()
        }
    }
    var controller: DockController {
        DockController(command: { [self] in try run($0, $1) }, runningDock: { [self] in Int32(100 + state.withLock { $0.restarts }) })
    }
}

@Test func animationReadPreservesSystemDisabledAndCustomTiming() async throws {
    for animation in [DockAnimation(), DockAnimation(enabled: false), DockAnimation(timeModifier: 0.25)] {
        let fake = FakeDock()
        fake.state.withLock { $0.settings.animation = animation }
        #expect(try await fake.controller.read().animation == animation)
    }
}

@Test func disablingAnimationBatchesWithOtherChanges() async throws {
    let fake = FakeDock()
    try await fake.controller.apply(DockSettings(edge: .left, autoHide: true, animation: DockAnimation(enabled: false)))
    #expect(fake.state.withLock { $0.writes } == [
        ["write", "com.apple.dock", "orientation", "-string", "left"],
        ["write", "com.apple.dock", "autohide", "-bool", "true"],
        ["write", "com.apple.dock", "autohide-time-modifier", "-float", "0.0"]
    ])
    #expect(fake.state.withLock { $0.restarts } == 1)
}

@Test func enablingSystemAnimationDeletesOverride() async throws {
    let fake = FakeDock()
    fake.state.withLock { $0.settings.animation = DockAnimation(enabled: false) }
    try await fake.controller.apply(DockSettings(animation: DockAnimation()))
    #expect(fake.state.withLock { $0.writes } == [["delete", "com.apple.dock", "autohide-time-modifier"]])
    #expect(try await fake.controller.read().animation == DockAnimation())
}

@Test func enablingCustomAnimationRestoresSavedTiming() async throws {
    let fake = FakeDock()
    fake.state.withLock { $0.settings.animation = DockAnimation(enabled: false) }
    try await fake.controller.apply(DockSettings(animation: DockAnimation(timeModifier: 0.25)))
    #expect(fake.state.withLock { $0.writes } == [["write", "com.apple.dock", "autohide-time-modifier", "-float", "0.25"]])
}

@Test func unmanagedAndMatchingAnimationDoNotWriteOrRestart() async throws {
    for animation in [DockAnimation(), DockAnimation(enabled: false), DockAnimation(timeModifier: 0.25)] {
        let fake = FakeDock()
        fake.state.withLock { $0.settings.animation = animation }
        try await fake.controller.apply(DockSettings())
        try await fake.controller.apply(DockSettings(animation: animation))
        #expect(fake.state.withLock { $0.writes.isEmpty && $0.restarts == 0 })
    }
}

@Test func animationWriteFailureDoesNotRestartDock() async {
    let fake = FakeDock()
    fake.state.withLock { $0.failWrite = true }
    await #expect(throws: DockError.self) {
        try await fake.controller.apply(DockSettings(animation: DockAnimation(enabled: false)))
    }
    #expect(fake.state.withLock { $0.restarts } == 0)
}

@Test func ignoredAnimationWriteAndDeletionCannotReportSuccess() async {
    for enabled in [true, false] {
        let fake = FakeDock()
        fake.state.withLock {
            $0.settings.animation = DockAnimation(enabled: !enabled)
            $0.ignoreWrite = true
        }
        await #expect(throws: DockError.self) {
            try await fake.controller.apply(DockSettings(animation: DockAnimation(enabled: enabled)))
        }
    }
}

@Test func invalidAnimationDoesNotChangeDock() async {
    for modifier in [-1.0, 0.0, Double.infinity, Double.nan] {
        let fake = FakeDock()
        await #expect(throws: DockError.self) {
            try await fake.controller.apply(DockSettings(edge: .left, animation: DockAnimation(timeModifier: modifier)))
        }
        #expect(fake.state.withLock { $0.writes.isEmpty && $0.restarts == 0 })
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

@Test func mainDisplayAppliesEvenWhenDockPreferencesAlreadyMatch() async throws {
    let selected = Mutex<[String]>([])
    let fake = FakeDock()
    let controller = DockController(command: { try fake.run($0, $1) }, runningDock: { 100 },
        selectMainDisplay: { id in selected.withLock { $0.append(id) } })
    try await controller.apply(DockSettings(mainDisplayID: "external"))
    #expect(selected.withLock { $0 } == ["external"])
    #expect(fake.state.withLock { $0.writes.isEmpty && $0.restarts == 0 })
}

@Test func unavailableMainDisplayDoesNotChangeDockPreferences() async {
    let fake = FakeDock()
    let controller = DockController(command: { try fake.run($0, $1) }, runningDock: { 100 },
        selectMainDisplay: { _ in throw MainDisplayController.Failure.unavailable })
    await #expect(throws: MainDisplayController.Failure.self) {
        try await controller.apply(DockSettings(edge: .left, mainDisplayID: "missing"))
    }
    #expect(fake.state.withLock { $0.writes.isEmpty && $0.restarts == 0 })
}

@Test func mainDisplaySelectionDoesNotBreakDockReadback() async throws {
    let fake = FakeDock()
    let controller = DockController(command: { try fake.run($0, $1) },
        runningDock: { Int32(100 + fake.state.withLock { $0.restarts }) }, selectMainDisplay: { _ in })
    try await controller.apply(DockSettings(edge: .left, mainDisplayID: "external"))
    #expect(fake.state.withLock { $0.settings.edge == .left && $0.restarts == 1 })
}
