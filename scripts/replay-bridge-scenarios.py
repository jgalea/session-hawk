#!/usr/bin/env python3
"""
Replay bridge events into a running Session Hawk dev app.

This is a manual UI verification helper.  It sends realistic bridge commands
over the same Unix socket used by hook clients.  Permission/question events keep
their socket open by default, matching real blocking hook processes while
the UI waits for user input.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path
from typing import Any


SCENARIOS = ("approval", "question", "completion", "all")
DEFAULT_FIRE_AND_FORGET_PAUSE = 0.15
DEFAULT_HOLD_TIMEOUT = 0.0


def default_socket_path() -> str:
    path = os.environ.get("SESSION_HAWK_SOCKET_PATH") or os.environ.get("VIBE_ISLAND_SOCKET_PATH")
    if path:
        return path
    return str(Path.home() / "Library/Application Support/SessionHawk/bridge.sock")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def base_payload(session_id: str, cwd: str, terminal_title: str) -> dict[str, Any]:
    return {
        "cwd": cwd,
        "session_id": session_id,
        "transcript_path": f"/tmp/session-hawk-{session_id}.jsonl",
        "model": "claude-sonnet-5",
        "permission_mode": "default",
        "terminal_app": "cmux",
        "terminal_session_id": f"replay-{session_id}",
        "terminal_title": terminal_title,
    }


def claude_payload(
    hook_event_name: str,
    session_id: str,
    cwd: str,
    *,
    terminal_title: str = "session-hawk demo",
    **fields: Any,
) -> dict[str, Any]:
    """Build a ClaudeHookPayload dict (snake_case keys per ClaudeHooks.swift CodingKeys)."""
    payload = {
        **base_payload(session_id, cwd, terminal_title),
        "hook_event_name": hook_event_name,
    }
    for key, value in fields.items():
        if value is not None:
            payload[key] = value
    return payload


def claude_question_tool_input() -> dict[str, Any]:
    """Mirrors the real AskUserQuestion tool_input shape (camelCase, per ClaudeHookPayload.questionPrompt).

    The app appends an "Other" freeform option itself, so it isn't included here.
    """
    return {
        "questions": [
            {
                "question": "Which notification treatment should this session use?",
                "header": "Notification",
                "options": [
                    {"label": "Inline choices", "description": "Answer directly in the island"},
                    {"label": "Jump back", "description": "Return to the terminal before answering"},
                ],
                "multiSelect": False,
            }
        ]
    }


def command_envelope(command: dict[str, Any]) -> dict[str, Any]:
    return {"type": "command", "command": command}


def process_claude_hook(payload: dict[str, Any]) -> dict[str, Any]:
    return command_envelope({"type": "processClaudeHook", "claudeHook": payload})


def scenario_commands(scenario: str, cwd: str) -> list[tuple[str, dict[str, Any], bool, bool]]:
    if scenario == "approval":
        session_id = "session-hawk-replay-approval"
        return [
            (
                "claude session start",
                process_claude_hook(
                    claude_payload("SessionStart", session_id, cwd, source="startup")
                ),
                True,
                False,
            ),
            (
                "claude prompt",
                process_claude_hook(
                    claude_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd,
                        prompt="Replay the approval notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "claude permission request",
                process_claude_hook(
                    claude_payload(
                        "PermissionRequest",
                        session_id,
                        cwd,
                        tool_name="Bash",
                        tool_use_id=f"tool-{session_id}",
                        tool_input={"command": "swift test --filter AppModelSessionListTests"},
                    )
                ),
                False,
                True,
            ),
        ]

    if scenario == "question":
        # Claude Code has no separate "question" hook event. The real mechanism is a
        # PermissionRequest whose tool_name is AskUserQuestion — BridgeServer.handleClaudeHook
        # detects payload.questionPrompt (parsed from tool_input) and emits .questionAsked
        # instead of .permissionRequested, holding the socket the same way. This is the
        # actual first-class shape the app expects, not an approximation.
        session_id = "session-hawk-replay-question"
        return [
            (
                "claude session start",
                process_claude_hook(
                    claude_payload("SessionStart", session_id, cwd, source="startup")
                ),
                True,
                False,
            ),
            (
                "claude prompt",
                process_claude_hook(
                    claude_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd,
                        prompt="Replay the question notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "claude question (AskUserQuestion permission request)",
                process_claude_hook(
                    claude_payload(
                        "PermissionRequest",
                        session_id,
                        cwd,
                        tool_name="AskUserQuestion",
                        tool_use_id=f"tool-{session_id}",
                        tool_input=claude_question_tool_input(),
                    )
                ),
                False,
                True,
            ),
        ]

    if scenario == "completion":
        session_id = "session-hawk-replay-completion"
        return [
            (
                "claude session start",
                process_claude_hook(
                    claude_payload("SessionStart", session_id, cwd, source="startup")
                ),
                True,
                False,
            ),
            (
                "claude prompt",
                process_claude_hook(
                    claude_payload(
                        "UserPromptSubmit",
                        session_id,
                        cwd,
                        prompt="Replay the completion notification card.",
                    )
                ),
                True,
                False,
            ),
            (
                "claude stop",
                process_claude_hook(
                    claude_payload(
                        "Stop",
                        session_id,
                        cwd,
                        last_assistant_message=(
                            "Bridge replay finished. Use this card to verify completed-session "
                            "notification layout and reply affordances."
                        ),
                    )
                ),
                True,
                False,
            ),
        ]

    raise ValueError(f"unsupported scenario: {scenario}")


def recv_response(sock: socket.socket, timeout: float | None) -> dict[str, Any] | None:
    sock.settimeout(timeout)
    buffer = b""
    try:
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                return None
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if not line:
                    continue
                message = json.loads(line)
                if message.get("type") == "response":
                    return message.get("response")
    except (TimeoutError, socket.timeout):
        return None


def connect_bridge(socket_path: str) -> socket.socket:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(socket_path)
    except FileNotFoundError:
        sock.close()
        raise RuntimeError(
            f"Bridge socket not found at {socket_path}. Start the dev app first."
        )
    except ConnectionRefusedError:
        sock.close()
        raise RuntimeError(
            f"Bridge socket refused connection at {socket_path}. Restart the dev app and try again."
        )
    return sock


def encode_envelope(envelope: dict[str, Any]) -> str:
    return json.dumps(envelope, separators=(",", ":"))


def send_envelope(
    socket_path: str,
    envelope: dict[str, Any],
    *,
    wait_response: bool,
    timeout: float,
    dry_run: bool,
) -> dict[str, Any] | None:
    line = encode_envelope(envelope)
    if dry_run:
        print(line)
        return {"type": "dryRun"}

    with connect_bridge(socket_path) as sock:
        sock.sendall(line.encode("utf-8") + b"\n")
        if wait_response:
            return recv_response(sock, timeout)

        time.sleep(DEFAULT_FIRE_AND_FORGET_PAUSE)
        return None


def hold_interaction(
    socket_path: str,
    envelope: dict[str, Any],
    *,
    timeout: float | None,
    dry_run: bool,
    label: str,
) -> dict[str, Any] | None:
    line = encode_envelope(envelope)
    if dry_run:
        print(line)
        return {"type": "dryRun"}

    with connect_bridge(socket_path) as sock:
        sock.sendall(line.encode("utf-8") + b"\n")
        print(f"  sent {label}; keeping hook connected until UI resolution")
        print("  answer the card in Session Hawk, or press Ctrl-C to cancel")
        return recv_response(sock, timeout)


def replay_one(
    scenario: str,
    *,
    socket_path: str,
    cwd: str,
    timeout: float,
    hold_timeout: float | None,
    hold_interactions: bool,
    dry_run: bool,
) -> None:
    print(f"Replaying {scenario} bridge scenario")
    for label, envelope, wait_response, can_hold in scenario_commands(scenario, cwd):
        if can_hold and hold_interactions:
            response = hold_interaction(
                socket_path,
                envelope,
                timeout=hold_timeout,
                dry_run=dry_run,
                label=label,
            )
            if dry_run:
                print(f"  sent {label}")
            elif response is None:
                print(f"  {label} ended without a bridge response")
            else:
                print(f"  resolved {label}")
            continue
        else:
            response = send_envelope(
                socket_path,
                envelope,
                wait_response=wait_response,
                timeout=timeout,
                dry_run=dry_run,
            )
        if wait_response and response is None and not dry_run:
            raise RuntimeError(f"{label} did not return a bridge response")
        print(f"  sent {label}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Replay Session Hawk bridge scenarios into the running dev app."
    )
    parser.add_argument(
        "scenario",
        choices=SCENARIOS,
        help="Scenario to replay. Use individual scenarios for manual visual inspection.",
    )
    parser.add_argument(
        "--socket",
        default=default_socket_path(),
        help="Bridge socket path. Defaults to SESSION_HAWK_SOCKET_PATH or the stable SessionHawk app-support socket.",
    )
    parser.add_argument(
        "--cwd",
        default=str(repo_root()),
        help="Working directory to place in replay payloads.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5,
        help="Response timeout for non-blocking bridge commands.",
    )
    parser.add_argument(
        "--hold-timeout",
        type=float,
        default=DEFAULT_HOLD_TIMEOUT,
        help="Seconds to keep approval/question replay hooks connected while waiting for UI resolution. 0 waits indefinitely.",
    )
    parser.add_argument(
        "--no-hold",
        action="store_true",
        help="Do not keep approval/question hooks connected. Mostly useful for inspecting raw bridge cleanup behavior.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=1.4,
        help="Delay between scenarios when using `all`.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print JSON envelopes without connecting to the bridge.",
    )
    args = parser.parse_args()

    scenarios = ("approval", "question", "completion") if args.scenario == "all" else (args.scenario,)
    hold_interactions = not args.no_hold and args.scenario != "all"
    hold_timeout = None if args.hold_timeout <= 0 else args.hold_timeout

    if args.scenario == "all" and not args.no_hold and not args.dry_run:
        print("`all` replays without holding approval/question sockets; use an individual scenario for UI inspection.")

    try:
        for index, scenario in enumerate(scenarios):
            if index:
                time.sleep(args.delay)
            replay_one(
                scenario,
                socket_path=args.socket,
                cwd=args.cwd,
                timeout=args.timeout,
                hold_timeout=hold_timeout,
                hold_interactions=hold_interactions,
                dry_run=args.dry_run,
            )
    except KeyboardInterrupt:
        print("\nReplay cancelled.")
        return 130
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.dry_run:
        print("Dry run complete.")
    else:
        print("Replay complete. Inspect the Session Hawk overlay.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
