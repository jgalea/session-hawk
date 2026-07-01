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
          "current_directory": "/repos/lantana",
          "custom_title": "Lantana",
          "has_custom_title": true,
          "id": "11111111-1111-1111-1111-111111111111",
          "ref": "workspace:1"
        },
        {
          "current_directory": "/repos/plain",
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
            cwd: "/repos/lantana",
            workspaceID: nil
        )
        #expect(title == "Lantana")
    }

    @Test
    func matchesRegardlessOfTrailingSlashInCwd() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/repos/lantana/",
            workspaceID: nil
        )
        #expect(title == "Lantana")
    }

    @Test
    func returnsNilWhenWorkspaceHasNoCustomTitle() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/repos/plain",
            workspaceID: nil
        )
        #expect(title == nil)
    }

    @Test
    func returnsNilWhenNoWorkspaceMatchesCwd() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/repos/unknown",
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
            cwd: "/repos/plain",
            workspaceID: "11111111-1111-1111-1111-111111111111"
        )
        #expect(title == "Lantana")
    }

    @Test
    func fallsBackToCwdWhenWorkspaceIDDoesNotMatch() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(sample),
            cwd: "/repos/lantana",
            workspaceID: "does-not-exist"
        )
        #expect(title == "Lantana")
    }

    @Test
    func returnsNilWhenCwdIsAmbiguousWithoutWorkspaceID() {
        // Several cmux workspaces routinely share one directory with different
        // titles. Without a UUID to disambiguate, we must not guess.
        let ambiguous = """
        {
          "workspaces": [
            {
              "current_directory": "/repos/pa",
              "custom_title": "Session Hawk",
              "has_custom_title": true,
              "id": "aaaaaaaa-0000-0000-0000-000000000001",
              "ref": "workspace:9"
            },
            {
              "current_directory": "/repos/pa",
              "custom_title": "Portal Backup",
              "has_custom_title": true,
              "id": "bbbbbbbb-0000-0000-0000-000000000002",
              "ref": "workspace:4"
            }
          ]
        }
        """
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(ambiguous),
            cwd: "/repos/pa",
            workspaceID: nil
        )
        #expect(title == nil)
    }

    @Test
    func resolvesAmbiguousCwdWhenWorkspaceIDIsPresent() {
        let ambiguous = """
        {
          "workspaces": [
            {
              "current_directory": "/repos/pa",
              "custom_title": "Session Hawk",
              "has_custom_title": true,
              "id": "aaaaaaaa-0000-0000-0000-000000000001",
              "ref": "workspace:9"
            },
            {
              "current_directory": "/repos/pa",
              "custom_title": "Portal Backup",
              "has_custom_title": true,
              "id": "bbbbbbbb-0000-0000-0000-000000000002",
              "ref": "workspace:4"
            }
          ]
        }
        """
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json(ambiguous),
            cwd: "/repos/pa",
            workspaceID: "bbbbbbbb-0000-0000-0000-000000000002"
        )
        #expect(title == "Portal Backup")
    }

    @Test
    func returnsNilOnMalformedJSON() {
        let title = ClaudeHookPayload.cmuxCustomTitle(
            fromJSON: json("{ not json"),
            cwd: "/repos/lantana",
            workspaceID: nil
        )
        #expect(title == nil)
    }

    // MARK: - cwd -> workspace id resolution (click-time jump handle)

    @Test
    func workspaceIDReturnedForUniqueCwdMatch() {
        let id = ClaudeHookPayload.cmuxWorkspaceID(
            fromJSON: json(sample),
            cwd: "/repos/lantana"
        )
        #expect(id == "11111111-1111-1111-1111-111111111111")
    }

    @Test
    func workspaceIDMatchesRegardlessOfTrailingSlash() {
        let id = ClaudeHookPayload.cmuxWorkspaceID(
            fromJSON: json(sample),
            cwd: "/repos/lantana/"
        )
        #expect(id == "11111111-1111-1111-1111-111111111111")
    }

    @Test
    func workspaceIDNilForAmbiguousCwd() {
        // Several cmux workspaces share one directory, so the cwd alone cannot
        // pick one — return nil rather than jump to the wrong workspace.
        let ambiguous = """
        {
          "workspaces": [
            {
              "current_directory": "/repos/pa",
              "custom_title": "Session Hawk",
              "has_custom_title": true,
              "id": "aaaaaaaa-0000-0000-0000-000000000001",
              "ref": "workspace:9"
            },
            {
              "current_directory": "/repos/pa",
              "custom_title": "Portal Backup",
              "has_custom_title": true,
              "id": "bbbbbbbb-0000-0000-0000-000000000002",
              "ref": "workspace:4"
            }
          ]
        }
        """
        let id = ClaudeHookPayload.cmuxWorkspaceID(
            fromJSON: json(ambiguous),
            cwd: "/repos/pa"
        )
        #expect(id == nil)
    }

    @Test
    func workspaceIDNilWhenNoCwdMatches() {
        let id = ClaudeHookPayload.cmuxWorkspaceID(
            fromJSON: json(sample),
            cwd: "/repos/unknown"
        )
        #expect(id == nil)
    }

    @Test
    func workspaceIDNilOnMalformedJSON() {
        let id = ClaudeHookPayload.cmuxWorkspaceID(
            fromJSON: json("{ not json"),
            cwd: "/repos/lantana"
        )
        #expect(id == nil)
    }

    @Test
    func terminalWorkspaceIDSurvivesJumpTargetCodableRoundTrip() throws {
        let target = JumpTarget(
            terminalApp: "cmux",
            workspaceName: "Lantana",
            paneTitle: "pane",
            workingDirectory: "/repos/lantana",
            terminalWorkspaceID: "11111111-1111-1111-1111-111111111111"
        )

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(JumpTarget.self, from: encoded)

        #expect(decoded.terminalWorkspaceID == "11111111-1111-1111-1111-111111111111")
    }

    @Test
    func workspaceNamePrefersResolvedNameOverCwdBasename() {
        var payload = ClaudeHookPayload(
            cwd: "/repos/lantana",
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
            cwd: "/repos/lantana",
            hookEventName: .sessionStart,
            sessionID: "abc",
            resolvedWorkspaceName: "   "
        )
        #expect(payload.workspaceName == "lantana")
    }

    @Test
    func resolvedWorkspaceNameSurvivesCodableRoundTrip() throws {
        let payload = ClaudeHookPayload(
            cwd: "/repos/lantana",
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
