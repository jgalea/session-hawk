# Roadmap

Session Hawk is a lean, Claude-Code-only fork of [Open Island](https://github.com/Octane0411/open-vibe-island). It's maintained as a personal, detached public repo rather than a community project — contributions are welcome, but the focus stays narrow: get the Claude Code experience right rather than spreading across multiple agents.

Think of Session Hawk as having done the basics: a macOS island shell + Claude Code communication layer + fundamental features like notifications and terminal jump-back. Everything else can be defined by you.

> **How to contribute**: describe your idea clearly in an issue, then submit a PR. See [CONTRIBUTING.md](../CONTRIBUTING.md) for details.

## Focus Areas

| # | Area | Description | Status |
|---|------|-------------|--------|
| 1 | **Claude Code Experience** | Session Hawk is Claude Code only. We focus on getting that experience right rather than spreading across multiple agents. | Active |
| 2 | **IDE / Plugin Jump-back** | Support jumping back to IDE or in-IDE terminal windows, or apps with integrated code agent plugins (Cursor, VSCode, GoLand, Obsidian, etc.). | Planned |
| 3 | **More Terminals** | Add support for terminal apps not yet on the supported list. If your terminal isn't supported, you're the best person to add it. | Open |
| 4 | **SSH Jump-back** | We currently support detecting and notifying code agent sessions over SSH. Jump-back is harder and needs more work. | Open |
| 5 | **Interaction & Polish** | Better UX, UI, animations, sound design, and overall feel. [Vibe Island](https://vibeisland.app/) sets a high bar here. | Open |
| 6 | **Product Ideas: Voice, Notification Reply & More** | Voice input/output, notification-based reply, and any other ideas. | Conditionally Open |
| 7 | **Architecture & Code Quality** | Think the current code is poorly structured? We agree it can always be better. Architectural opinions, refactoring proposals, or rewriting modules from scratch are all welcome. | Open |

**Status legend**: `Active` = core team focus · `In Progress` = work started · `Planned` = accepted, not started · `Open` = community-driven, all contributions welcome · `Conditionally Open` = open an issue or start a discussion first
