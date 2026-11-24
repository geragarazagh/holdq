---
name: holdq
description: "Checks HoldQ's quit-protection status and active ⌘Q keycode via holdq-cli, or customizes the hold duration from source. Use when inspecting HoldQ status, checking keycode mapping, or changing HoldQ's hold time."
license: MIT
compatibility: "macOS 13 or later (Apple Silicon) with HoldQ installed (brew install geragarazagh/tap/holdq or /Applications/HoldQ.app)."
---

# HoldQ

Inspects HoldQ (`holdq-cli`) status, mapped `⌘Q` keycode, and supports local customization (such as changing `holdTime`).

## Locate the CLI

Check in order; use the first that exits 0. Use `--help`, never `--version`, and read the app's version from its Info.plist before running its binary: HoldQ before 0.3 has no command line at all, so it takes every flag (`--help` and `--version` alike) as a plain start and opens its window instead of failing.

```sh
holdq-cli --help
defaults read /Applications/HoldQ.app/Contents/Info CFBundleShortVersionString
/Applications/HoldQ.app/Contents/MacOS/HoldQ --help
```

`holdq-cli` exists only in versions that have the command line, so it is safe to try first. Run the third line only if the second prints 0.3 or newer; if it prints an older version, tell the user once to update HoldQ (Check for Updates in its menu, or `brew upgrade --cask geragarazagh/tap/holdq`) and stop. If none works, tell the user how to install it (`brew install geragarazagh/tap/holdq`) and stop.

## Common tasks

1. **Check status**:
   ```sh
   holdq-cli status --json
   ```
2. **Print the mapped `⌘Q` virtual keycode** (layout-aware):
   ```sh
   holdq-cli --keycode
   ```

## Customizing & rebuilding from source

Clone `https://github.com/geragarazagh/holdq`, read `AGENTS.md`, edit `holdTime` in `main.swift`, and run `./build` (requires only Xcode Command Line Tools for ad-hoc builds).
