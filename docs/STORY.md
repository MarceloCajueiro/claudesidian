# The Story of ClaudeSidian

How a personal itch became an open-source macOS app — built entirely through a conversation with Claude Code.

## The Problem

macOS has a fundamental gap when it comes to CLI tools: GUI apps launched from Finder, Spotlight, or the Dock don't inherit your shell environment. No `~/.zshrc`, no custom PATH, no nvm, no Homebrew binaries. If you want to launch a CLI tool like [Claude Code](https://docs.anthropic.com/en/docs/claude-code) from the Dock and have it *just work*, you're out of luck.

The author wanted a simple thing: click an icon, get Claude Code running inside an [Obsidian](https://obsidian.md/) vault, with full shell environment. No Terminal.app juggling. No remembering `cd ~/obsidian-meta && claude --dangerously-skip-permissions` every time.

## Act 1: The Quick Hack (v0 — AppleScript wrapper)

The first attempt was pragmatic: a `.app` bundle containing a bash script that invoked AppleScript to tell Terminal.app to open a new window with the right command.

```
Claudesidian.app/
  Contents/
    MacOS/claudesidian  ← bash script
    Info.plist
    Resources/AppIcon.icns
```

The launcher script was simple:

```bash
#!/bin/bash
osascript <<'APPLESCRIPT'
tell application "Terminal"
    activate
    set newTab to do script "cd ~/obsidian-meta && source ~/.zshrc; exec claude --dangerously-skip-permissions"
end tell
APPLESCRIPT
```

An SVG icon was generated programmatically — a diamond/crystal shape blending Obsidian's dark purple with Claude's coral gradient. No Sketch, no Figma, no design tools. The icon was created through a pipeline of macOS built-in commands:

1. `qlmanage -t -s 1024 -o . icon.svg` — Quick Look renders the SVG to PNG
2. `sips -z 16 16 ... -z 512 512 ... -z 1024 1024` — resize to all required dimensions (16px through 1024px, including @2x variants)
3. `mkdir icon.iconset && mv *.png icon.iconset/` — assemble the iconset folder with Apple's naming convention (`icon_16x16.png`, `icon_16x16@2x.png`, etc.)
4. `iconutil -c icns icon.iconset` — convert to the final `.icns` file

This entire toolchain exists on every Mac — no Xcode required.

**It worked.** But there was a problem.

## Act 2: "How do I get my own icon in Cmd+Tab?"

Since the wrapper just told Terminal.app to run a command, **Terminal's icon** appeared in Cmd+Tab and the Dock — not ClaudeSidian's. The app had no real identity. It was a shortcut, not an application.

The question was clear: *how do you make a macOS app that has its own Dock icon, its own Cmd+Tab entry, AND runs an interactive terminal session?*

Research surfaced three viable approaches:
1. **Electron + xterm.js** — full terminal emulation via web tech (~100MB+)
2. **Minimal Swift + raw PTY** — build a terminal from scratch using `posix_spawn` and `openpty()`
3. **SwiftTerm** — a mature Swift library with `LocalProcessTerminalView`, a ready-made terminal emulator view backed by a pseudo-terminal

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (by Miguel de Icaza) was the clear winner: native, ~1.4MB binary, full xterm-256color support, and it could be built with Swift Package Manager — no Xcode project required.

## Act 3: The Native App (v1)

The entire app was rewritten as a single Swift file using AppKit + SwiftTerm:

- `NSApplication` with `.regular` activation policy → own Dock icon and Cmd+Tab entry
- `NSWindow` with transparent titlebar and dark theme
- `LocalProcessTerminalView` providing full terminal emulation via PTY
- Custom environment builder to inject PATH, SSH_AUTH_SOCK, and other variables that macOS GUI apps don't inherit
- Login shell invocation (`shell -l -c "exec command"`) to source the user's profile

The app launched the user's shell, which sourced `~/.zshrc`, then exec'd into Claude Code. The terminal was fully interactive. Closing the window or quitting the app sent SIGTERM to the child process.

This version worked exactly as intended — but everything was hardcoded: the command (`claude --dangerously-skip-permissions`), the working directory (`~/obsidian-meta`), the binary path.

## Act 4: Polish

Small but important refinements followed — the kind of things you only discover by using the app for real:

- **Cmd+W didn't close the window** — A classic AppKit gotcha. SwiftTerm's terminal view consumed the key event before AppKit's responder chain could route it to the window's `performClose:` action. The fix: wire up the menu item's key equivalent explicitly.
- **Fixed title bar** — The terminal title kept changing as Claude Code updated it (shell escape sequences). The title was locked to "ClaudeSidian" by overriding the terminal delegate.
- **Padding** — The terminal content was flush against the window edges. A container view with Auto Layout constraints added 12px padding on all sides.
- **Shift+Enter** — Claude Code uses Shift+Enter for multiline input. SwiftTerm doesn't send anything useful for this combo by default. A custom `ClaudeSidianTerminalView` subclass was created to intercept `keyCode 36` (Enter) with the Shift modifier and send a literal `\n` to the PTY — matching what iTerm2, WezTerm, and Kitty do natively. This required reading Claude Code's own source to confirm which escape sequences it accepts.
- **Dead key composition** — SwiftTerm's `optionAsMetaKey` was enabled by default, which hijacked the Option key for terminal meta sequences. This broke macOS dead key composition — typing Option+E followed by "a" should produce "á", but instead sent `^[e`. Disabling this flag restored proper accent input for Portuguese and other languages.
- **Proper naming** — The "S" in "ClaudeSidian" was capitalized everywhere: window title, menu bar, bundle display name, and `CFBundleDisplayName` in Info.plist (the field macOS uses for Spotlight search).

## Act 5: Open Source

The decision to open source the project triggered a significant refactoring:

**Nothing should be hardcoded.** The app needed to work for anyone, not just the author.

A configuration system was introduced:

- **`~/.config/claudesidian/config.json`** — simple JSON file with `command` and `workingDirectory` fields
- **First-run setup wizard** — a native NSWindow with text fields for command and working directory, a Browse button with NSOpenPanel for folder selection, input validation, and a "Save & Launch" button
- **Settings menu** — accessible via ClaudeSidian > Settings (Cmd+,), pre-filled with current values
- **Process cleanup** — `applicationShouldTerminate` and `windowWillClose` both call `terminate()` on the child process, with a SIGKILL fallback after 2 seconds

The codebase was split into three files:
- `main.swift` — AppDelegate, window setup, terminal setup, menu bar
- `Config.swift` — `AppConfig` struct with load/save, shell detection, command parsing
- `SetupWindow.swift` — First-run and settings UI

The icon was cleaned up — the "CLAUDESIDIAN" text at the bottom of the SVG was removed, leaving only the diamond symbol.

A build script, README, CHANGELOG, LICENSE (MIT), and GitHub Actions CI were added. The project was pushed to GitHub as a public repository.

## Act 6: Distribution

Open sourcing is not just about pushing code — someone has to be able to *use* it.

The first goal was simple: `git tag v1.0.0 && git push origin v1.0.0` should produce a downloadable `.app` without any manual steps.

A GitHub Actions workflow was created:
- Triggered by pushing a semver tag (`v*`)
- Stamps the version from the tag into `Info.plist` using `/usr/libexec/PlistBuddy`
- Builds a **Universal Binary** (`--arch arm64 --arch x86_64`) — runs natively on both Apple Silicon and Intel Macs, no Rosetta needed
- Assembles the `.app` bundle, zips it with `ditto` (preserves macOS metadata), and publishes a GitHub Release with auto-generated notes
- Tags containing a hyphen (e.g. `v1.0.0-beta.1`) are automatically marked as prereleases

**The first release failed.** The CI runner (`macos-14`) shipped Xcode 15.4 with Swift 5.9, but SwiftTerm's `Package.swift` used trailing commas — a syntax feature that requires Swift 6. The fix was switching to `macos-15` (Xcode 16, Swift 6). A classic case of "works on my machine" — locally the author had Swift 6.2.1, but CI hadn't caught up.

The app is unsigned (no Apple Developer account), so macOS Gatekeeper blocks it on first launch. Users right-click → Open to bypass this. Signing and notarization are future enhancements.

## The Conversation

This entire project — from "I want an app that opens Claude Code in my Obsidian vault" to a published open-source macOS app with automated releases — was built through iterative conversations with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) across multiple sessions in a single day.

The interaction pattern was:

1. **User states intent** → "I want a macOS app that launches Claude Code in ~/obsidian-meta"
2. **Claude builds first version** → AppleScript wrapper with custom icon
3. **User tests and gives feedback** → "The icon doesn't show in Cmd+Tab"
4. **Claude researches and rebuilds** → SwiftTerm-based native app
5. **User refines** → "Fix the title bar", "Add padding", "Shift+Enter doesn't work"
6. **Claude investigates and iterates** → reads Claude Code source, creates terminal subclass
7. **User discovers language bug** → "Accents don't work, I can't type ã or é"
8. **Claude traces the root cause** → `optionAsMetaKey` in SwiftTerm, fixes it
9. **User decides to open source** → "Remove hardcoded values, create GitHub repo"
10. **Claude refactors and ships** → Config system, setup wizard, README, CI
11. **CI breaks** → Swift version mismatch on GitHub Actions runner
12. **Claude fixes and re-releases** → switch to `macos-15`, retag

No code was written in Xcode. No manual file editing. The entire project — every Swift file, every shell script, the SVG icon, the Info.plist, the build system, the GitHub Actions workflow — was generated through the conversation.

The project went through three architectural phases and six acts across multiple Claude Code sessions:

| Phase | Approach | Identity in Cmd+Tab |
|-------|----------|-------------------|
| v0 | Bash + AppleScript → Terminal.app | Terminal |
| v1 | Swift + SwiftTerm (hardcoded) | ClaudeSidian |
| v2 | Swift + SwiftTerm (configurable + CI) | ClaudeSidian |

Context was maintained across sessions through Claude Code's memory system and the codebase itself — each session could pick up where the last left off by reading the code and git history.

## Architecture

```
ClaudeSidian.app
  └── Claudesidian (1.4MB native binary)
        ├── AppKit NSApplication (.regular policy)
        ├── NSWindow (dark theme, transparent titlebar)
        └── SwiftTerm LocalProcessTerminalView
              └── PTY → user's login shell → exec command
```

Config: `~/.config/claudesidian/config.json`

Dependencies: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT)

## What It Demonstrates

- **macOS app development without Xcode** — Swift Package Manager + manual .app bundle assembly
- **macOS icon creation without design tools** — SVG → `qlmanage` → `sips` → `iconutil` → `.icns`
- **Solving the macOS GUI↔Shell environment gap** — login shell invocation + custom PATH building
- **Iterative AI-assisted development** — from prototype to shipped open-source project in a single day, across multiple sessions
- **Shipping is messy** — the first CI build failed, accents didn't work, Cmd+W didn't close the window. Each bug was a lesson in how macOS actually works under the hood.
- **Minimal viable architecture** — three Swift files, one dependency, 1.4MB universal binary
