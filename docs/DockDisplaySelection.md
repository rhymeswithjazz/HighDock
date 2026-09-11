# Choose the main display

HighDock now saves an optional main display with each setup. This is the agreed approach for placing the Dock on the upper-left monitor in a three-monitor desk arrangement. It also changes the Mac's main display; Dock placement remains subject to macOS edge rules.

The Main display picker uses persistent display UUIDs and numbered names that match the preview. Existing setups default to Keep current main display. The preview shows the requested main display and Dock edge.

The platform uses a CoreGraphics transaction to translate display origins so the chosen display is at zero, preserving relative positions. Mirrored follower displays are excluded from origin writes because those writes would break mirroring. The app checks the resulting layout before applying Dock preferences. Missing targets and failed configuration return errors. No Accessibility permission is needed.

A setup matches both its original layout and its chosen main-display layout. The app suppresses reapplication caused by its own display change. Conflicting saved setups are rejected before writing. Clearing the choice on a connected setup keeps the current main display and saves that current layout.

Automated checks cover old settings, persistence, layout translation, mirrored and missing targets, conflicting setups, Dock no-ops and failures, and setup recognition after changing the main display. Physical verification is still needed: select the upper-left monitor and Left, then test actual Dock placement, auto-hide, reconnect, sleep/wake, and relaunch. Confirm relative monitor positions and mirroring stay intact. Changing the main display is not a guarantee of arbitrary Dock placement on shared edges.
