import Foundation
import Testing
@testable import SessionHawkCore

struct CmuxWorkspaceNameTests {
    private func json(_ string: String) -> Data {
        Data(string.utf8)
    }

    private let sample = """
    {
      "workspaces": [
        {
          "current_directory": "/Users/jean/code/lantana",
          "custom_title": "Lantana",
          "has_custom_title": true,
          "id": "11111111-1111-1111-1111-111111111111",
          "ref": "workspace:1"
        },
        {
          "current_directory": "/Users/jean/code/plain",
          "custom_title": null,
          "has_custom_title": false,
          "id": "22222222-2222-2222-2222-222222222222",
          "ref": "workspace:2"
        }
      ]
    }
    """

    @Test
    func returnsCustomTitleWhenCwdMatchesAndTitleIsSet() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/Users/jean/code/lantana",
            workspaceID: nil
        )
        #expect(title == "Lantana")
    }

    @Test
    func matchesRegardlessOfTrailingSlashInCwd() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/Users/jean/code/lantana/",
            workspaceID: nil
        )
        #expect(title == "Lantana")
    }

    @Test
    func returnsNilWhenWorkspaceHasNoCustomTitle() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/Users/jean/code/plain",
            workspaceID: nil
        )
        #expect(title == nil)
    }

    @Test
    func returnsNilWhenNoWorkspaceMatchesCwd() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/Users/jean/code/unknown",
            workspaceID: nil
        )
        #expect(title == nil)
    }

    @Test
    func prefersWorkspaceIDMatchOverCwd() {
        // Same cwd as the untitled workspace, but the UUID points at the
        // titled one — the UUID match wins.
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/Users/jean/code/plain",
            workspaceID: "11111111-1111-1111-1111-111111111111"
        )
        #expect(title == "Lantana")
    }

    @Test
    func fallsBackToCwdWhenWorkspaceIDDoesNotMatch() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/Users/jean/code/lantana",
            workspaceID: "does-not-exist"
        )
        #expect(title == "Lantana")
    }

    @Test
    func returnsNilOnMalformedJSON() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json("{ not json"),
            cwd: "/Users/jean/code/lantana",
            workspaceID: nil
        )
        #expect(title == nil)
    }

    @Test
    func workspaceNamePrefersResolvedNameOverCwdBasename() {
        var payload = ClaudeHookPayload(
            cwd: "/Users/jean/code/lantana",
            hookEventName: .sessionStart,
            sessionID: "abc"
        )
        #expect(payload.workspaceName == "lantana")

        payload.resolvedWorkspaceName = "Lantana"
        #expect(payload.workspaceName == "Lantana")
    }

    @Test
    func workspaceNameFallsBackWhenResolvedNameIsBlank() {
        var payload = ClaudeHookPayload(
            cwd: "/Users/jean/code/lantana",
            hookEventName: .sessionStart,
            sessionID: "abc",
            resolvedWorkspaceName: "   "
        )
        #expect(payload.workspaceName == "lantana")
    }

    @Test
    func resolvedWorkspaceNameSurvivesCodableRoundTrip() throws {
        let payload = ClaudeHookPayload(
            cwd: "/Users/jean/code/lantana",
            hookEventName: .sessionStart,
            sessionID: "abc",
            terminalApp: "cmux",
            resolvedWorkspaceName: "Lantana"
        )

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ClaudeHookPayload.self, from: encoded)

        #expect(decoded.resolvedWorkspaceName == "Lantana")
        #expect(decoded.workspaceName == "Lantana")
        #expect(decoded.defaultJumpTarget.workspaceName == "Lantana")
    }
}
