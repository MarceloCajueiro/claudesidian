# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2025-02-11

### Added

- Native macOS terminal launcher with SwiftTerm integration
- First-run setup wizard for command and working directory configuration
- Persistent configuration at `~/.config/claudesidian/config.json`
- Settings accessible via menu bar (Cmd+,)
- Dark theme with Claude-inspired coral accents
- Font size controls (Cmd+/Cmd-/Cmd+0)
- Cmd+W to close window
- Proper process cleanup on quit (SIGTERM + SIGKILL fallback)
- Custom app icon with Dock presence and Cmd+Tab integration
- Universal Binary support (ARM64 + Intel) via GitHub Actions
- Automated GitHub Releases distribution

[1.0.0]: https://github.com/MarceloCajueiro/claudesidian/releases/tag/v1.0.0
