# Hook System

SessionHawk receives hook events from Claude Code via the `SessionHawkHooks` CLI. The CLI forwards payloads to the app over a Unix socket and, when necessary, writes a directive back to stdout so Claude Code can act on it (e.g. block a tool call).

## Architecture

```
Claude Code
  │  stdin: JSON payload
  ▼
SessionHawkHooks CLI
  │  Unix socket
  ▼
BridgeServer → AppModel → UI
  │  BridgeResponse
  ▼
SessionHawkHooks CLI
  │  stdout: JSON directive (only when a response is needed)
  ▼
Claude Code
```

**Fail-open principle**: if the bridge is unavailable the hook process exits silently without writing to stdout, so Claude Code continues running unaffected.

## Skip Hooks For Delegated Control

Set `SESSION_HAWK_SKIP_HOOKS=1` on a child agent process when another local controller intentionally owns permission handling for that run. The hook CLI exits immediately without reading or forwarding the payload, so Claude Code continues without Session Hawk UI intervention.

`VIBE_ISLAND_SKIP=1` is also recognized as a legacy compatibility alias.

This is meant for per-process launches. Do not set it globally unless you want Session Hawk hooks disabled for every Claude Code process started from that environment.

**Entry point**: [`Sources/SessionHawkHooks/SessionHawkHooksCLI.swift`](../Sources/SessionHawkHooks/SessionHawkHooksCLI.swift)

---

## Claude Code Hooks

**Payload type**: `ClaudeHookPayload`  
**Source**: [`Sources/SessionHawkCore/ClaudeHooks.swift`](../Sources/SessionHawkCore/ClaudeHooks.swift)

### Events

| `hook_event_name` | When it fires | Directive response |
|---|---|---|
| `SessionStart` | Session starts (`startup` / `resume` / `clear` / `compact`) | None |
| `SessionEnd` | Session ends | None |
| `UserPromptSubmit` | User submits a prompt | None |
| `PreToolUse` | Before a tool call | **Yes** — allow / deny / modify input |
| `PostToolUse` | After a successful tool call | None |
| `PostToolUseFailure` | After a failed tool call | None |
| `PermissionRequest` | Agent requests user approval | **Yes** — allow or deny (24 h timeout) |
| `PermissionDenied` | A permission was denied | None |
| `Notification` | Agent emits a notification | None |
| `Stop` | Turn ends normally | None |
| `StopFailure` | Turn ends with an error | None |
| `SubagentStart` | A sub-agent starts | None |
| `SubagentStop` | A sub-agent stops | None |
| `PreCompact` | Before context compaction | None |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `permission_mode` | `permissionMode` | Permission mode |
| `model` | `model` | Model name |
| `agent_id` | `agentID` | Sub-agent ID (SubagentStart/Stop) |
| `agent_type` | `agentType` | Sub-agent type |
| `source` | `source` | Start source (`startup` / `resume` / `clear` / `compact`) |
| `tool_name` | `toolName` | Tool name |
| `tool_input` | `toolInput` | Tool input parameters (JSON) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `permission_suggestions` | `permissionSuggestions` | Suggested permission changes (PermissionRequest) |
| `prompt` | `prompt` | User prompt text |
| `message` | `message` | Notification message body |
| `title` | `title` | Notification title |
| `notification_type` | `notificationType` | Notification type |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `error` | `error` | Error message (Failure events) |
| `error_details` | `errorDetails` | Extended error details |
| `is_interrupt` | `isInterrupt` | Whether the event is an interrupt |
| `agent_transcript_path` | `agentTranscriptPath` | Sub-agent transcript path |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### PreToolUse directive response

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny" | "ask",
    "permissionDecisionReason": "reason shown to the agent",
    "updatedInput": { ... },
    "additionalContext": "extra context injected into the turn"
  }
}
```

| Field | Description |
|---|---|
| `permissionDecision` | `allow` — proceed; `deny` — block; `ask` — let the agent ask the user |
| `permissionDecisionReason` | Human-readable reason forwarded to the agent |
| `updatedInput` | Replace the tool's input parameters (optional) |
| `additionalContext` | Inject additional context into the turn (optional) |

### PermissionRequest directive response

The `PermissionRequest` event has a **24-hour timeout** to allow the user to review and approve in the UI.

Allow:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": { ... },
      "updatedPermissions": [ ... ]
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request",
      "interrupt": false
    }
  }
}
```

Setting `interrupt: true` terminates the current agent turn immediately.

---

## Timeout Policy

| Event | Timeout |
|---|---|
| `PermissionRequest` | **24 hours** (awaits human approval) |
| All other events | **45 seconds** |

---

## Terminal Auto-detection

The hook process infers the terminal type from environment variables at runtime:

| Environment variable | Inferred terminal |
|---|---|
| `ITERM_SESSION_ID` or `LC_TERMINAL=iTerm2` | `iTerm` |
| `CMUX_WORKSPACE_ID` or `CMUX_SOCKET_PATH` | `cmux` |
| `GHOSTTY_RESOURCES_DIR` | `Ghostty` |
| `WARP_IS_LOCAL_SHELL_SESSION` | `Warp` |
| `TERM_PROGRAM=Apple_Terminal` | `Terminal` |
| `TERM_PROGRAM=WezTerm` | `WezTerm` |

For iTerm, Terminal, and Ghostty the process additionally runs an AppleScript query to obtain the session ID, TTY, and window title — used to power the "jump back to terminal" feature. The `cmux` terminal uses `CMUX_SURFACE_ID` instead of AppleScript.

---

## Related source files

| File | Responsibility |
|---|---|
| [`Sources/SessionHawkHooks/SessionHawkHooksCLI.swift`](../Sources/SessionHawkHooks/SessionHawkHooksCLI.swift) | Hook CLI entry point |
| [`Sources/SessionHawkCore/ClaudeHooks.swift`](../Sources/SessionHawkCore/ClaudeHooks.swift) | Claude Code payload model, directive types, output encoder |
| [`Sources/SessionHawkCore/BridgeServer.swift`](../Sources/SessionHawkCore/BridgeServer.swift) | Unix socket server — handles incoming hook payloads |
| [`Sources/SessionHawkCore/BridgeTransport.swift`](../Sources/SessionHawkCore/BridgeTransport.swift) | Protocol codec and envelope types |
