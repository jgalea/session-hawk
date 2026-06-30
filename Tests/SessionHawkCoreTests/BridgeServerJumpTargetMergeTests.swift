import Foundation
import Testing
@testable import SessionHawkCore

/// Pins `BridgeServer.mergeJumpTargetPreservingExistingResolvedFields`
/// behavior on the one "resolved" field it guards — `terminalSessionID`.
/// It's determined at hook time by a potentially-flaky runtime probe
/// (the Ghostty AppleScript locator), so when a later hook fails to
/// re-resolve it the merged jumpTarget must carry forward the previous
/// value instead of clearing it.
struct BridgeServerJumpTargetMergeTests {
    @Test
    func preservesTerminalSessionIDWhenIncomingIsNil() {
        // Documents the pre-existing Ghostty-session-ID preservation
        // behavior, now also routed through the shared helper. Only
        // SessionStart hooks actually query Ghostty's focused-terminal
        // locator; later hooks leave the field nil deliberately, and
        // we must not overwrite the captured ID with that nil.
        let existing = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: "ghostty-session-42"
        )
        let incoming = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: nil
        )

        let merged = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: incoming,
            existing: existing
        )

        #expect(merged.terminalSessionID == "ghostty-session-42")
    }

    @Test
    func overwritesTerminalSessionIDWhenIncomingHasValue() {
        // When the incoming hook successfully re-resolves the session
        // id, it MUST win — the user may have switched tabs since the
        // last hook. Only nil-valued incoming fields are preserved.
        let existing = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: "ghostty-session-42"
        )
        let incoming = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: "ghostty-session-99"
        )

        let merged = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: incoming,
            existing: existing
        )

        #expect(merged.terminalSessionID == "ghostty-session-99")
    }

    @Test
    func doesNotInventValuesWhenBothSidesAreNil() {
        // Preservation only activates when there is an existing value
        // to carry forward. When both sides are nil, the merged field
        // stays nil — the helper must not fabricate state.
        let existing = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: nil
        )
        let incoming = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: nil
        )

        let merged = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: incoming,
            existing: existing
        )

        #expect(merged.terminalSessionID == nil)
    }

    @Test
    func treatsMissingExistingJumpTargetAsNoPreservation() {
        // Edge case: the session has no jumpTarget yet at all (maybe
        // it was just created). The merge helper should pass through
        // the incoming jumpTarget unchanged — there is nothing to
        // preserve.
        let incoming = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            terminalSessionID: "ghostty-session-7"
        )

        let merged = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: incoming,
            existing: nil
        )

        #expect(merged.terminalSessionID == "ghostty-session-7")
    }
}
