# ClaudeSidian

Native macOS terminal app built with Swift + SwiftTerm, designed for running Claude Code.

## Build & Install

Always use the build script to build AND install in one step:

```bash
bash build.sh
```

This builds a release binary and installs `Claudesidian.app` to `~/Applications/`.

**Never use `swift build` alone** — always run `bash build.sh` so the app bundle gets updated.

## Architecture

- `Sources/main.swift` — App delegate, terminal window controller, drag & drop, Cmd+Click file detection
- `Sources/Config.swift` — AppConfig model and persistence
- `Sources/SetupWindow.swift` — First-run setup and settings UI
- `Resources/Info.plist` — App bundle metadata
- `Package.swift` — SPM dependencies (SwiftTerm, swift-argument-parser)

## Key Features

- Multi-window support (Cmd+N) — each window runs its own shell process
- Drag & drop files from Finder into terminal
- Cmd+Click to open file paths
- Shift+Enter for multiline input (Claude Code)
- OSC 8 hyperlink support
