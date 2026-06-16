# Contributing to Anvil

Thanks for your interest in improving Anvil! This is a SwiftUI macOS app, so the bar to get going is just a recent Xcode.

## Getting set up

1. Fork and clone the repo.
2. Open `anvil.xcodeproj` in **Xcode 26.3+** on **macOS 26+**.
3. Select the `anvil` scheme and build with **⌘B** / run with **⌘R**.

There are no third-party dependencies and no package manager step — open and build.

## Project layout

Keep the **engine** (`anvil/Engine/`) free of SwiftUI. It's the testable orchestration layer: detection, discovery, command construction, process streaming. UI lives in the top-level files. See the architecture section in the [README](README.md) for the full map.

## Guidelines

- **Match the surrounding style.** Comments in this codebase are in Portuguese (pt-BR); follow the local convention of the file you're editing.
- **Engine changes should be testable.** Command construction is pure — verify it by inspection in the test target rather than spawning real processes.
- **Respect the design language.** The UI is a cyanotype blueprint (see `Theme.swift`). Prefer the existing `BP` palette and native components over ad-hoc styling — and go easy on borders.
- **Keep the sandbox off but the runtime hardened.** Don't add entitlements unless a feature truly needs one.

## Submitting a change

1. Create a branch off `main`.
2. Make your change; confirm `xcodebuild … build` succeeds with no new warnings.
3. Open a PR describing **what** changed and **why**. Screenshots/GIFs are very welcome for UI work.

## Reporting bugs & ideas

Use the issue templates under [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/). Include your macOS and Xcode versions, and the toolchain (iOS/Android/Bun/Docker) involved.
