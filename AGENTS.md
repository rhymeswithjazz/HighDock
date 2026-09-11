# Repository Guidelines

## Project structure

HighDock is a Swift Package Manager macOS menu bar app that saves Dock settings per display layout.

- `Sources/HighDockCore/` owns layout identity, setup storage, and switching policy.
- `Sources/HighDockPlatform/` reads displays and applies Dock and main-display changes.
- `Sources/HighDock/` contains SwiftUI views, app state, login registration, and Sparkle updates.
- `Sources/HighDockProbe/` provides desktop diagnostics.
- `Tests/` mirrors the app, core, and platform targets. `scripts/tests/` covers Python release tools.
- `Resources/` contains the app icon and plist. `scripts/` handles packaging and releases; `docs/` holds release and display-selection notes.

## Build and development

Use macOS 26+, Xcode with Swift 6.2+, and Python 3.11+. Open `Package.swift` in Xcode.

- `./scripts/build.sh` creates the ad-hoc signed `build/HighDock.app`.
- `open build/HighDock.app` launches the bundle for menu bar and login testing.
- `./scripts/build.sh --universal` builds arm64 and x86_64, as CI does.
- `./scripts/test.sh` runs Swift tests; append `--filter <name>` to narrow the run.
- `python3 -m unittest discover -s scripts/tests` tests release tooling.
- `.build/debug/HighDockProbe` prints display and Dock state after building the test targets.

## Coding style

Use four-space indentation, `UpperCamelCase` Swift types, and `lowerCamelCase` members. Match nearby code; no formatter or linter is configured. Keep system effects in the platform target and policy in core. Preserve `@MainActor` isolation for app state. Add comments only for counterintuitive or unusually complex logic.

## Testing

Swift tests use Swift Testing with `@Test` and `#expect`. Name functions after behavior, such as `unknownLayoutsAndDeletedSetupsStayUntouched`. Python tests use `unittest` and `test_` names. No numeric coverage threshold is configured. Cover changed behavior, failure paths, and no-op updates. For UI changes, check the built app and include appearance screenshots. Follow README hardware checks for display changes.

## Commits and pull requests

Use short, imperative commit subjects matching history, such as `Fix architecture verification in CI`. Keep the user as commit author; never mention an AI assistant in commit messages. PRs should explain the behavior change, link relevant issues, and report automated and manual checks. Ensure CI passes.

## System safeguards

Preserve Dock size, magnification, and pinned apps. Keep corrupt or unsupported setup files unchanged. The probe's `--exercise-dock` option temporarily changes live settings. Follow `docs/PersonalReleases.md` for signing and notarization.
