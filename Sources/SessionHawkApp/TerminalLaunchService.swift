import Foundation

/// The terminal Session Hawk launches when it needs to open one on the
/// user's behalf (currently: resuming a recovered Claude session).
enum PreferredTerminal: String, CaseIterable, Sendable {
    case cmux
    case iterm2
    case terminal
    case ghostty
    case wezterm

    static let `default`: PreferredTerminal = .cmux

    var displayName: String {
        switch self {
        case .cmux: "cmux"
        case .iterm2: "iTerm"
        case .terminal: "Terminal"
        case .ghostty: "Ghostty"
        case .wezterm: "WezTerm"
        }
    }
}

/// Launches a preferred terminal at a given working directory, resuming a
/// Claude Code session with `claude --resume <sessionID>`.
struct TerminalLaunchService {
    typealias BinaryResolver = @Sendable (String) -> String?
    typealias ProcessRunner = @Sendable (String, [String]) -> Bool

    struct LaunchCommand: Equatable {
        let executablePath: String
        let arguments: [String]
    }

    private let binaryResolver: BinaryResolver
    private let processRunner: ProcessRunner

    init(
        binaryResolver: @escaping BinaryResolver = Self.defaultBinaryResolver(name:),
        processRunner: @escaping ProcessRunner = Self.defaultProcessRunner(executable:arguments:)
    ) {
        self.binaryResolver = binaryResolver
        self.processRunner = processRunner
    }

    /// Maps a terminal, working directory, and session id to the exact
    /// executable and arguments that will launch it. Kept side-effect free
    /// (beyond delegating to the injected `binaryResolver`) so it can be
    /// tested without touching the filesystem or spawning processes.
    func launchCommand(for terminal: PreferredTerminal, workingDirectory: String, sessionID: String) -> LaunchCommand {
        let resumeCommand = "claude --resume \(sessionID)"

        switch terminal {
        case .cmux:
            let executable = binaryResolver("cmux") ?? "cmux"
            return LaunchCommand(
                executablePath: executable,
                arguments: ["new-workspace", "--focus", "true", "--cwd", workingDirectory, "--command", resumeCommand]
            )

        case .wezterm:
            let executable = binaryResolver("wezterm") ?? "wezterm"
            return LaunchCommand(
                executablePath: executable,
                arguments: ["start", "--cwd", workingDirectory, "--", "claude", "--resume", sessionID]
            )

        case .ghostty:
            return LaunchCommand(
                executablePath: "/usr/bin/open",
                arguments: ["-na", "Ghostty", "--args", "--working-directory=\(workingDirectory)", "-e", "claude", "--resume", sessionID]
            )

        case .terminal:
            let shellCommand = "cd \(Self.shellQuoted(workingDirectory)) && \(resumeCommand)"
            return LaunchCommand(
                executablePath: "/usr/bin/osascript",
                arguments: [
                    "-e", "tell application \"Terminal\" to do script \"\(Self.escapeAppleScript(shellCommand))\"",
                    "-e", "tell application \"Terminal\" to activate",
                ]
            )

        case .iterm2:
            let shellCommand = "cd \(Self.shellQuoted(workingDirectory)) && \(resumeCommand)"
            let script = """
            tell application "iTerm"
                create window with default profile
                tell current session of current window
                    write text "\(Self.escapeAppleScript(shellCommand))"
                end tell
            end tell
            """
            return LaunchCommand(executablePath: "/usr/bin/osascript", arguments: ["-e", script])
        }
    }

    /// Resolves and runs the launch command, returning a user-facing status
    /// string on success or throwing on failure.
    func launch(terminal: PreferredTerminal, workingDirectory: String, sessionID: String) throws -> String {
        let command = launchCommand(for: terminal, workingDirectory: workingDirectory, sessionID: sessionID)

        guard processRunner(command.executablePath, command.arguments) else {
            throw TerminalLaunchError.launchFailed(terminal)
        }

        return "Resumed session in \(terminal.displayName)."
    }

    /// Single-quotes a path for safe embedding in a shell command, escaping
    /// any embedded single quotes.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func defaultBinaryResolver(name: String) -> String? {
        if let known = Self.knownBinaryCandidates(for: name).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return known
        }
        return Self.resolveViaWhich(name)
    }

    private static func knownBinaryCandidates(for name: String) -> [String] {
        switch name {
        case "cmux":
            return ["/Applications/cmux.app/Contents/Resources/bin/cmux"]
        case "wezterm":
            return ["/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm"]
        default:
            return []
        }
    }

    private static func resolveViaWhich(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private static func defaultProcessRunner(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum TerminalLaunchError: Error, LocalizedError {
    case launchFailed(PreferredTerminal)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(terminal):
            "Failed to launch \(terminal.displayName)."
        }
    }
}
