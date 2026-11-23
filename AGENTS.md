# AGENTS.md — HoldQ

Zero-permission macOS quit protection (`⌘Q` quits only when held 1.0 s) in plain Swift + AppKit + Carbon `RegisterEventHotKey`. No Xcode project; `./build` compiles directly with `swiftc`.

## Architecture

- `main.swift` — `holdTime` (1.0 s), layout-aware `quitKeyCode()`, Carbon `RegisterEventHotKey`, 120 Hz HUD ring (`HUD`), `NSRunningApplication.terminate()`.
- `cli.swift` — `holdq-cli` (`status`, `--keycode`, `--version`, `--help`).
- `window.swift` — fixed 340 × 260 pt settings panel, Open at Login helper.
- `updates.swift` — Sparkle 2.10.1 updater.

## Build

- `./build` — builds ad-hoc signed `HoldQ.app` (`-target arm64-apple-macos13.0`). Works with Xcode Command Line Tools alone (`iconutil` fallback). Full Xcode is used for `Assets.car` (required when `SIGN_ID` is set).

## Invariants

- **Zero permissions**: uses Carbon `RegisterEventHotKey`, never a `CGEventTap` — needs no Accessibility or Input Monitoring.
- **Customizing locally**: change `holdTime` in `main.swift` (e.g. `0.7` or `1.5`), run `./build`, replace `/Applications/HoldQ.app`.
