import Foundation
import Testing
@testable import SessionHawkApp
import SessionHawkCore

struct AgentSessionPresentationTests {
    @Test
    func attachedCompletedSessionStaysActiveWhileRecent() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_199),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "claude ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .active)
    }

    @Test
    func attachedCompletedSessionCollapsesWhenOld() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_201),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "claude ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Initial prompt",
                lastUserPrompt: "Follow-up prompt",
                lastAssistantMessage: "Last assistant message"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .inactive)
        #expect(session.spotlightShowsDetailLines(at: referenceDate) == false)
    }

    @Test
    func detachedCompletedSessionCanStillCollapseToInactive() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_801)
        )

        #expect(session.islandPresence(at: referenceDate) == .inactive)
        #expect(session.spotlightShowsDetailLines(at: referenceDate) == false)
    }

    @Test
    func detachedCompletedSessionStaysActiveWithinTwentyMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_199),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Follow-up prompt",
                lastAssistantMessage: "Last assistant message"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .active)
        #expect(session.spotlightShowsDetailLines(at: referenceDate))
    }

    @Test
    func completionReplyRecipientCoversEveryAgentTool() {
        let expectedNames: [(AgentTool, String)] = [
            (.claudeCode, "Claude"),
        ]
        #expect(expectedNames.map { $0.0.rawValue }.sorted() == AgentTool.allCases.map(\.rawValue).sorted())

        for (tool, expectedName) in expectedNames {
            let session = AgentSession(
                id: "\(tool.rawValue)-session",
                title: "\(expectedName) · worktree",
                tool: tool,
                phase: .completed,
                summary: "Ready",
                updatedAt: .now
            )

            #expect(session.completionReplyRecipientName == expectedName)
        }
    }

    @Test
    func completedSessionBecomesV8StaleAfterFiveMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-301)
        )

        #expect(session.isStaleCompletedForIsland(at: referenceDate))
        #expect(session.islandPresence(at: referenceDate) == .active)
    }

    @Test
    func completedSessionDoesNotBecomeV8StaleWhenThresholdIsNever() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-86_400)
        )

        #expect(!session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: IslandCompletedStaleThreshold.never.seconds
        ))
    }

    @Test
    func nonCompletedSessionsDoNotBecomeV8Stale() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: referenceDate.addingTimeInterval(-3_600)
        )

        #expect(!session.isStaleCompletedForIsland(at: referenceDate))
    }

    @Test
    func liveHeadlineUsesLatestPromptForAttachedSession() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "claude ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Start by fixing the island hover behavior.",
                lastUserPrompt: "Now make the overlay height fit the content.",
                lastAssistantMessage: "Updating the layout logic."
            )
        )

        // Headline is workspace-only; the prompt is still available on the
        // "You:" line for the notification/permission surface.
        #expect(session.spotlightHeadlineText == "worktree")
        #expect(session.spotlightPromptLineText == "You: Now make the overlay height fit the content.")
    }

    @Test
    func detachedSessionHeadlineShowsInitialPrompt() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Done",
            updatedAt: Date.now.addingTimeInterval(-30),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Start by fixing the island hover behavior.",
                lastUserPrompt: "Now make the overlay height fit the content.",
                lastAssistantMessage: "Updating the layout logic."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree")
        #expect(session.spotlightPromptLineText == "You: Now make the overlay height fit the content.")
    }

    @Test
    func completedSessionShowsDifferentHeadlineAndPrompt() {
        let now = Date.now
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "claude ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Commit the README change.",
                lastUserPrompt: "Also confirm the worktree status.",
                lastAssistantMessage: "Committed and verified."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree")
        #expect(session.spotlightPromptLineText == "You: Also confirm the worktree status.")
        #expect(session.notificationHeaderPromptLineText == nil)
    }

    @Test
    func headlineNeverIncludesPromptContent() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "claude ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "You are running a secret command.",
                lastUserPrompt: "Do the thing.",
                lastAssistantMessage: "On it."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree")
        #expect(!session.spotlightHeadlineText.contains("·"))
        #expect(!session.spotlightHeadlineText.contains("secret"))
    }

    @Test
    func runningClaudeSessionWithoutToolShowsThinkingBesidePrompt() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Thinking.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Align the Claude statuses."
            )
        )

        #expect(session.spotlightPromptLineText == "You: Align the Claude statuses.")
        #expect(session.spotlightActivityLineText == "Thinking")
        #expect(session.displayCurrentToolName == nil)
    }

    @Test
    func runningClaudeSessionKeepsWriteStdinAsInput() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running input.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Continue the command.",
                currentTool: "write_stdin",
                currentToolInputPreview: "y"
            )
        )

        #expect(session.spotlightActivityLineText == "Input y")
        #expect(session.spotlightStatusLabel == "Live · Input")
        #expect(session.displayCurrentToolName == "Input")
    }

    @Test
    func runningClaudeSessionDisplaysWebSearchAction() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · worktree",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running web search.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Check the Claude repo.",
                currentTool: "web_search",
                currentToolInputPreview: "Claude rollout ResponseItem"
            )
        )

        #expect(session.spotlightActivityLineText == "Search Claude rollout ResponseItem")
        #expect(session.spotlightStatusLabel == "Live · Search")
        #expect(session.spotlightSecondaryText == "Running Search")
        #expect(session.displayCurrentToolName == "Search")
    }
}
