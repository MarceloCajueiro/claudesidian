# ClaudeSidian

A lightweight native macOS terminal launcher built with Swift and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Run any CLI tool in a dedicated app window with its own Dock icon, Cmd+Tab integration, and proper process management.

Originally built to run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) against an [Obsidian](https://obsidian.md/) vault — but it works with any command.

## Features

- Native macOS app (~1.4MB) with custom icon and Dock presence
- First-run setup wizard — no config files to edit manually
- Configurable command and working directory
- Proper process cleanup on quit (SIGTERM + SIGKILL fallback)
- Dark theme with Claude-inspired coral accents
- Font size controls (Cmd+/Cmd-/Cmd+0)
- Full terminal emulation via SwiftTerm

## Installation

### Download

Grab the latest `.zip` from [GitHub Releases](https://github.com/MarceloCajueiro/claudesidian/releases/latest), unzip, and move `Claudesidian.app` to your Applications folder.

> **Note:** The app is unsigned. On first launch, macOS Gatekeeper will block it. Right-click the app and choose **Open**, then click **Open** again in the dialog. You only need to do this once.

### Build from source

Requires Swift 5.9+ (included with Xcode 15+).

```bash
git clone https://github.com/MarceloCajueiro/claudesidian.git
cd claudesidian
bash build.sh
```

This builds a release binary and installs `Claudesidian.app` to `~/Applications/`.

### Run

```bash
open ~/Applications/Claudesidian.app
```

On first launch, you'll be prompted to configure:
- **Command to run** — e.g. `claude --dangerously-skip-permissions`
- **Working directory** — e.g. `~/my-project`

## Configuration

Settings are stored at `~/.config/claudesidian/config.json`:

```json
{
  "command": "claude --dangerously-skip-permissions",
  "workingDirectory": "~/obsidian-meta"
}
```

You can edit this file directly or use **ClaudeSidian > Settings** (Cmd+,) from the menu bar.

## Why?

macOS GUI apps launched from Finder/Spotlight don't inherit your shell environment. Tools like Claude Code need proper PATH, SSH keys, and shell config. ClaudeSidian solves this by launching your command through a login shell (`-l -c`), so everything just works.

It also gives your CLI tool a proper app identity — Dock icon, Cmd+Tab switching, and clean process lifecycle.

## License

MIT
