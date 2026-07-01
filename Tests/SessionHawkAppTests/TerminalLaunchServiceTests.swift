import XCTest
@testable import SessionHawkApp

final class TerminalLaunchServiceTests: XCTestCase {
    private final class RecordedInvocationBox: @unchecked Sendable {
        var executable: String?
        var arguments: [String]?
    }

    private let workingDirectory = "/tmp/session hawk test/project"
    private let sessionID = "0f47ac10-58cc-4372-a567-0e02b2c3d479"

    private func makeService() -> TerminalLaunchService {
        TerminalLaunchService(binaryResolver: { name in
            switch name {
            case "cmux": "/fake/bin/cmux"
            case "wezterm": "/fake/bin/wezterm"
            default: nil
            }
        })
    }

    func testCmuxLaunchCommand() {
        let command = makeService().launchCommand(for: .cmux, workingDirectory: workingDirectory, sessionID: sessionID)

        XCTAssertEqual(command.executablePath, "/fake/bin/cmux")
        XCTAssertEqual(command.arguments, [
            "new-workspace",
            "--focus", "true",
            "--cwd", "/tmp/session hawk test/project",
            "--command", "claude --resume 0f47ac10-58cc-4372-a567-0e02b2c3d479",
        ])
    }

    func testWezTermLaunchCommand() {
        let command = makeService().launchCommand(for: .wezterm, workingDirectory: workingDirectory, sessionID: sessionID)

        XCTAssertEqual(command.executablePath, "/fake/bin/wezterm")
        XCTAssertEqual(command.arguments, [
            "start",
            "--cwd", "/tmp/session hawk test/project",
            "--",
            "claude", "--resume", "0f47ac10-58cc-4372-a567-0e02b2c3d479",
        ])
    }

    func testGhosttyLaunchCommand() {
        let command = makeService().launchCommand(for: .ghostty, workingDirectory: workingDirectory, sessionID: sessionID)

        XCTAssertEqual(command.executablePath, "/usr/bin/open")
        XCTAssertEqual(command.arguments, [
            "-na", "Ghostty",
            "--args",
            "--working-directory=/tmp/session hawk test/project",
            "-e", "claude", "--resume", "0f47ac10-58cc-4372-a567-0e02b2c3d479",
        ])
    }

    func testTerminalLaunchCommand() {
        let command = makeService().launchCommand(for: .terminal, workingDirectory: workingDirectory, sessionID: sessionID)

        XCTAssertEqual(command.executablePath, "/usr/bin/osascript")
        XCTAssertEqual(command.arguments, [
            "-e", "tell application \"Terminal\" to do script \"cd '/tmp/session hawk test/project' && claude --resume 0f47ac10-58cc-4372-a567-0e02b2c3d479\"",
            "-e", "tell application \"Terminal\" to activate",
        ])
    }

    func testITermLaunchCommand() {
        let command = makeService().launchCommand(for: .iterm2, workingDirectory: workingDirectory, sessionID: sessionID)

        XCTAssertEqual(command.executablePath, "/usr/bin/osascript")
        XCTAssertEqual(command.arguments, [
            "-e",
            """
            tell application "iTerm"
                create window with default profile
                tell current session of current window
                    write text "cd '/tmp/session hawk test/project' && claude --resume 0f47ac10-58cc-4372-a567-0e02b2c3d479"
                end tell
            end tell
            """,
        ])
    }

    func testLaunchReturnsSuccessMessageWhenProcessRunnerSucceeds() throws {
        let recorded = RecordedInvocationBox()
        let service = TerminalLaunchService(
            binaryResolver: { _ in "/fake/bin/cmux" },
            processRunner: { executable, arguments in
                recorded.executable = executable
                recorded.arguments = arguments
                return true
            }
        )

        let result = try service.launch(terminal: .cmux, workingDirectory: workingDirectory, sessionID: sessionID)

        XCTAssertEqual(result, "Resumed session in cmux.")
        XCTAssertEqual(recorded.executable, "/fake/bin/cmux")
        XCTAssertEqual(recorded.arguments?.first, "new-workspace")
    }

    func testLaunchThrowsWhenProcessRunnerFails() {
        let service = TerminalLaunchService(
            binaryResolver: { _ in "/fake/bin/cmux" },
            processRunner: { _, _ in false }
        )

        XCTAssertThrowsError(try service.launch(terminal: .cmux, workingDirectory: workingDirectory, sessionID: sessionID)) { error in
            XCTAssertEqual(error.localizedDescription, "Failed to launch cmux.")
        }
    }
}
