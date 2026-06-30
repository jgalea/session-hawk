<div align="center">

# Session Hawk

[![License](https://img.shields.io/badge/LICENSE-GPL--3.0-5C9E31?style=for-the-badge)](LICENSE)
[![Built by](https://img.shields.io/badge/BUILT%20BY-JEAN%20GALEA-8A2BE2?style=for-the-badge)](https://jeangalea.com)

**A lean, local-first macOS notch companion for Claude Code.**

</div>

Session Hawk is a notch and menu-bar widget for macOS that shows live Claude Code session status, brokers permission prompts, and gives you a one-click jump back to the terminal where the session is running.

The app installs a hook into `~/.claude/settings.json`. That hook forwards Claude Code lifecycle events to the app over a local Unix socket. Everything stays local: no network calls, no telemetry, and no hosted service.

Supported terminal contexts:

- cmux
- iTerm
- Terminal
- Ghostty
- VS Code and Cursor

## Install

Build from source on macOS 14 or later:

```sh
swift build -c release --product SessionHawkApp
zsh scripts/package-app.sh
```

For development:

```sh
zsh scripts/launch-dev-app.sh
```

Session Hawk is a lean Claude-only public fork of the open-source Open Island project.

## License

GPL-3.0. Session Hawk Copyright (C) 2026 Jean Galea.
