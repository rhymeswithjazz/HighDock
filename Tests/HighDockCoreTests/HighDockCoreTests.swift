import Foundation
import Testing
@testable import HighDockCore

private func display(_ id: String = "laptop", x: Double = 0, y: Double = 0, width: Double = 1440, primary: Bool = true, mirrorOf: String? = nil) -> Display {
    Display(id: id, x: x, y: y, width: width, height: 900, primary: primary, mirrorOf: mirrorOf)
}
private let laptop = DisplayLayout(displays: [display()])
private let desk = DisplayLayout(displays: [display(), display("external", x: 1440, primary: false)])
private let laptopSetup = Setup(name: "Laptop", layout: laptop, settings: DockSettings(edge: .bottom, autoHide: true))
private let deskSetup = Setup(name: "Desk", layout: desk, settings: DockSettings(edge: .left, autoHide: false))

@Test func layoutIgnoresEnumerationAndDesktopOrigin() {
    let translated = DisplayLayout(displays: [display("external", x: 1540, y: -200, primary: false), display(x: 100, y: -200)])
    #expect(desk.signature == translated.signature)
}
@Test func layoutIgnoresDisplayNames() {
    var renamed = desk
    renamed.displays[0].name = "New friendly name"
    #expect(renamed.signature == desk.signature)
}
@Test func layoutDistinguishesArrangementPrimaryMirroringAndDimensions() {
    var moved = desk; moved.displays[1].y = 100
    var primary = desk; primary.displays[0].primary = false; primary.displays[1].primary = true
    var mirrored = desk; mirrored.displays[1].mirrorOf = "laptop"
    var resized = desk; resized.displays[1].width = 1600
    for changed in [moved, primary, mirrored, resized, laptop] {
        #expect(changed.signature != desk.signature)
    }
}
@Test func ambiguousIdentityDoesNotMatch() {
    #expect(DisplayLayout(displays: []).signature == nil)
    #expect(DisplayLayout(displays: [display("")]).signature == nil)
    #expect(DisplayLayout(displays: [display(), display(x: 1440)]).signature == nil)
}
@Test func appliesOnlyOnEntryAndExplicitResume() {
    var policy = SwitchingPolicy()
    let setups = [laptopSetup, deskSetup]
    #expect(policy.activate(laptop, setups: setups) == laptopSetup.settings)
    #expect(policy.activate(laptop, setups: setups) == nil)
    #expect(policy.activate(desk, setups: setups) == deskSetup.settings)
    #expect(policy.activate(laptop, setups: setups) == laptopSetup.settings)
    #expect(policy.activate(laptop, setups: setups, force: true) == laptopSetup.settings)
}
@Test func manualOverridesSurviveWakeAndRepeatedDisplayEvents() {
    var policy = SwitchingPolicy()
    _ = policy.activate(desk, setups: [deskSetup])
    for _ in 0..<20 { #expect(policy.activate(desk, setups: [deskSetup]) == nil) }
}
@Test func unknownLayoutsAndDeletedSetupsStayUntouched() {
    var policy = SwitchingPolicy()
    #expect(policy.activate(desk, setups: [laptopSetup]) == nil)
    #expect(policy.activate(laptop, setups: [laptopSetup]) != nil)
    #expect(policy.activate(laptop, setups: [], force: true) == nil)
}
@Test func pauseTracksLayoutWithoutApplying() {
    var policy = SwitchingPolicy()
    policy.paused = true
    #expect(policy.activate(laptop, setups: [laptopSetup]) == nil)
    #expect(policy.activate(desk, setups: [deskSetup]) == nil)
    policy.paused = false
    #expect(policy.activate(desk, setups: [deskSetup], force: true) == deskSetup.settings)
}
@Test func returningFromAmbiguousLayoutReactivatesKnownLayout() {
    var policy = SwitchingPolicy()
    _ = policy.activate(laptop, setups: [laptopSetup])
    #expect(policy.activate(DisplayLayout(displays: []), setups: [laptopSetup]) == nil)
    #expect(policy.activate(laptop, setups: [laptopSetup]) == laptopSetup.settings)
}
@Test func storeRoundTripsAndSupportsDeletion() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SetupStore(url: folder.appending(path: "setups.json"))
    #expect(try store.load().isEmpty)
    try store.save([laptopSetup, deskSetup])
    #expect(try store.load() == [laptopSetup, deskSetup])
    try store.save([deskSetup])
    #expect(try store.load() == [deskSetup])
}
@Test func storeRejectsFutureVersionsWithoutOverwriting() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let original = Data(#"{"version":2,"setups":[]}"#.utf8)
    try original.write(to: url)
    #expect(throws: SetupStore.StoreError.self) { try SetupStore(url: url).load() }
    #expect(try Data(contentsOf: url) == original)
}
@Test func storeRejectsCorruption() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("broken".utf8).write(to: url)
    #expect(throws: (any Error).self) { try SetupStore(url: url).load() }
}
