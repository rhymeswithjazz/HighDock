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

@Test func oldDockSettingsLeaveMainDisplayUnchanged() throws {
    let settings = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"edge":"left","autoHide":false}"#.utf8))
    #expect(settings.mainDisplayID == nil)
    #expect(settings.animation == nil)
}

@Test func animationSettingsRoundTripIncludingDisabledCustomTiming() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = SetupStore(url: url)
    for animation in [DockAnimation(), DockAnimation(enabled: false), DockAnimation(enabled: false, timeModifier: 0.25)] {
        var setup = laptopSetup
        setup.settings.animation = animation
        try store.save([setup])
        #expect(try store.load() == [setup])
    }
}

@Test func invalidAnimationCannotOverwriteSavedSetups() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = SetupStore(url: url)
    try store.save([laptopSetup])
    let original = try Data(contentsOf: url)
    var setup = laptopSetup
    setup.settings.animation = DockAnimation(timeModifier: -1)
    #expect(throws: SetupStore.StoreError.self) { try store.save([setup]) }
    #expect(try Data(contentsOf: url) == original)
}

@Test func mainDisplayChangePreservesThreeMonitorArrangement() throws {
    let layout = DisplayLayout(displays: [
        Display(id: "laptop", x: 0, y: 0, width: 1440, height: 900, primary: true),
        Display(id: "left", x: -1920, y: -1440, width: 2560, height: 1440),
        Display(id: "right", x: 640, y: -1440, width: 2560, height: 1440)
    ])
    let changed = try #require(layout.makingPrimary("left"))
    #expect(changed.displays[1].x == 0 && changed.displays[1].y == 0)
    #expect(changed.displays[0].x == 1920 && changed.displays[0].y == 1440)
    #expect(changed.displays.filter(\.primary).map(\.id) == ["left"])
    let setup = Setup(name: "Desk", layout: layout, settings: DockSettings(edge: .left, mainDisplayID: "left"))
    #expect(setup.matches(layout))
    #expect(setup.matches(changed))
    var policy = SwitchingPolicy()
    #expect(policy.activate(layout, setups: [setup]) == setup.settings)
    #expect(policy.activate(changed, setups: [setup]) == nil)
    #expect(policy.activate(changed, setups: [setup], force: true) == setup.settings)
    #expect(layout.makingPrimary("missing") == nil)
}

@Test func mirroredDisplayCannotBecomeMain() {
    let layout = DisplayLayout(displays: [display(), display("mirror", primary: false, mirrorOf: "laptop")])
    #expect(layout.makingPrimary("mirror") == nil)
    #expect(layout.makingPrimary("laptop")?.displays[1].mirrorOf == "laptop")
}

@Test func conflictingMainDisplaySetupsCannotOverwriteSavedFile() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = SetupStore(url: url)
    let selected = Setup(name: "Desk", layout: desk, settings: DockSettings(mainDisplayID: "external"))
    try store.save([selected])
    #expect(try store.load() == [selected])
    let other = Setup(name: "Other", layout: try #require(desk.makingPrimary("external")), settings: DockSettings())
    #expect(throws: SetupStore.StoreError.self) { try store.save([selected, other]) }
    #expect(try store.load() == [selected])
}

private let office = DisplayLayout(displays: [
    Display(id: "left", x: 0, y: 0, width: 3008, height: 1692, primary: true),
    Display(id: "laptop", x: 2188, y: 1692, width: 1512, height: 982),
    Display(id: "right", x: 3008, y: 0, width: 3008, height: 1692)
])

@Test func reconnectRecognizesOfficeWithADifferentMainDisplay() throws {
    for mainDisplayID: String? in [nil, "left"] {
        let setup = Setup(name: "Work Office", layout: office, settings: DockSettings(edge: .left, mainDisplayID: mainDisplayID))
        let reconnected = try #require(office.makingPrimary("laptop"))
        #expect(Setup.matching(reconnected, among: [setup]) == setup)
        var policy = SwitchingPolicy()
        #expect(policy.activate(reconnected, setups: [setup]) == setup.settings)
        #expect(policy.activate(office, setups: [setup]) == nil)
        #expect(policy.activate(laptop, setups: [setup]) == nil)
        #expect(policy.activate(reconnected, setups: [setup]) == setup.settings)
    }
}

@Test func reconnectMatchingPreservesExactChoicesAndRejectsAmbiguity() throws {
    let left = Setup(name: "Left", layout: office, settings: DockSettings(edge: .left))
    let right = Setup(name: "Right", layout: try #require(office.makingPrimary("right")), settings: DockSettings(edge: .right))
    for setups in [[left, right], [right, left]] {
        #expect(Setup.matching(office, among: setups) == left)
        #expect(Setup.matching(right.layout, among: setups) == right)
        #expect(Setup.matching(try #require(office.makingPrimary("laptop")), among: setups) == nil)
    }
}

@Test func reconnectMatchingStillRequiresTheSameDisplaysAndArrangement() throws {
    let setup = Setup(name: "Work Office", layout: office, settings: DockSettings(edge: .left))
    let reconnected = try #require(office.makingPrimary("laptop"))
    var moved = reconnected; moved.displays[1].x += 1
    var resized = reconnected; resized.displays[0].width += 1
    var replaced = reconnected; replaced.displays[0].id = "different"
    var mirrored = reconnected; mirrored.displays[2].mirrorOf = "left"
    var missing = reconnected; missing.displays.removeLast()
    var duplicate = reconnected; duplicate.displays[2].id = "left"
    for layout in [moved, resized, replaced, mirrored, missing, duplicate, DisplayLayout(displays: [])] {
        #expect(Setup.matching(layout, among: [setup]) == nil)
    }
}
