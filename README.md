# HighDock

HighDock remembers the Dock's edge, auto-hide setting, and an optional main display for each monitor layout. Resize the Dock normally. HighDock never writes its size, magnification, or pinned apps.

## Run

Requires macOS 26 or later, Xcode with Swift 6.2 or later, and Python 3.11 or later.

```sh
./scripts/build.sh
open build/HighDock.app
```

Open `Package.swift` in Xcode to work on the app. The build script creates an ad-hoc signed, unsandboxed app bundle. Use that bundle to test the menu bar and Launch at Login. Keep it in a stable location if you enable login launch. No developer account is needed for local use.

On first launch the setup window opens. Later launches stay in the menu bar. Choose Open HighDock to configure the connected layout. Save and Apply creates a setup and changes its edge and hiding setting. Saved setups can be renamed, edited while disconnected, or deleted.

Choose **Main display** to have HighDock make that monitor the Mac’s main display when the setup applies. Numbers in the picker match the preview. **Keep current main display** preserves the current choice. This changes the main display for the desktop as well as influencing Dock placement; macOS still decides which edges can host the Dock.

Unknown layouts stay untouched. Changes made directly in macOS last until the next setup activation. Pause suspends automatic changes; explicit Save and Apply still works. Quit and deletion leave the Dock as it is.

## Distribution

Personal releases use Developer ID signing, Apple notarization, and Sparkle updates. Install the first release manually on each Mac, then use **Check for Updates** in the menu bar. Development builds keep updates disabled.

[Personal release guide](docs/PersonalReleases.md) covers signing setup, universal packaging, draft releases, and the GitHub Pages feed. The release tooling follows the same process as the personal NetNewsWire build.

## How it works

- `HighDockCore` owns layout identity, setup records, versioned storage, and switching policy.
- `HighDockPlatform` reads displays and applies Dock preferences. It optionally changes the main display through a CoreGraphics configuration transaction, preserving relative display positions and mirroring. It writes only `orientation` and `autohide` through `defaults`, restarts the current user's Dock once when needed, then checks a newly launched Dock process and reads back the settings. A no-op never restarts the Dock.
- `HighDock` owns the SwiftUI window, menu bar, login registration, one-second event debounce, and application queue.

Layouts use persistent CoreGraphics display UUIDs, normalized origins, logical dimensions, primary display, and mirror membership. Setups with a chosen main display match both their saved layout and the layout after that choice applies. Overlapping setup matches are rejected. Enumeration order and names do not affect matching. Scaling that changes logical dimensions creates a new layout. Missing or duplicate identities do not match. UUID stability ultimately depends on macOS and the display or adapter. A new identity is treated as an unsaved layout.

Setup data lives at `~/Library/Application Support/HighDock/setups.json`. Writes are atomic. Unsupported or corrupt files are kept unchanged and block saving until repaired. Pause and first-launch flags use the app's user defaults.

Dock preference keys are an undocumented macOS integration. Readback and process restart verify application mechanics; they cannot prove where macOS visually placed the Dock. HighDock can choose the main display but cannot independently pin the Dock to a screen. Main-display changes apply for the login session and are restored by HighDock when the saved setup next activates. It requests no Accessibility or Screen Recording permission.

## Check

```sh
./scripts/test.sh
.build/debug/HighDockProbe
```

The probe prints the current display layout and Dock settings. The optional live check temporarily changes edge and auto-hide, verifies a Dock restart, restores the original values, and compares other preferences:

```sh
.build/debug/HighDockProbe --exercise-dock
```

Run it in a normal desktop terminal with other Dock automation paused. It saves a before snapshot in `build/dock-before.plist`. On a normal failure it attempts restoration before reporting the error. It cannot recover from forced process termination. The comparison excludes Dock-maintained activity counters. It never imports the full preference snapshot.

Automated tests cover layout matching, file errors, no-op Dock updates, write failures, verification failures, saving and editing setups, pause/resume, wake/manual overrides, deletion, and rapid connection events.

Validation on macOS 27 confirmed live Dock changes and restoration with unrelated preferences intact. The native window and accessibility tree were inspected on a built-in Retina display. Saving, pause/resume, persistence across launch, and reopening from Finder were checked in the built app. The behavior and update-settings tests pass. An opt-in render test exercises light, dark, and increased-contrast window appearances; offscreen captures do not fully reproduce native sidebar vibrancy. Physical multi-monitor reconnects, mirroring, lid closure, login launch after reboot, and macOS 26 still need hardware testing.

To regenerate offscreen appearance checks in a desktop session:

```sh
HIGHDOCK_RENDER_PREVIEWS=1 ./scripts/test.sh --filter renderAppearanceChecks
```

For final hardware acceptance, save distinct laptop and external-display setups, resize the Dock manually, then connect/disconnect, rearrange, mirror, sleep/wake, and close/open the lid. Confirm each settled layout applies once, unknown layouts stay untouched, and manual resizing survives every switch. Check VoiceOver, keyboard navigation, increased contrast, reduced motion, and both appearances.

The app icon is drawn by `scripts/Icon.swift`. To regenerate:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift scripts/Icon.swift build/HighDock.iconset
python3 scripts/pack-icon.py
```
