---
name: holdq
description: "Checks HoldQ's quit-protection status and active ⌘Q keycode via holdq-cli, or customizes the hold duration from source. Use when inspecting HoldQ status, checking keycode mapping, or changing HoldQ's hold time."
license: MIT
compatibility: "macOS 13 or later (Apple Silicon) with HoldQ installed (brew install geragarazagh/tap/holdq or /Applications/HoldQ.app)."
---

# HoldQ

Inspects HoldQ (`holdq-cli`) status, mapped `⌘Q` keycode, and supports local customization (such as changing `holdTime`).

## Locate the CLI

Check in order; use the first that exits 0:

```sh
holdq-cli --version
/Applications/HoldQ.app/Contents/MacOS/HoldQ --version
```

If neither exists, tell the user how to install it (`brew install geragarazagh/tap/holdq`) and stop.

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
