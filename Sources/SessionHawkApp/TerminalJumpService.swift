import AppKit
import Foundation
import SessionHawkCore

struct TerminalJumpService {
    typealias ApplicationResolver = @Sendable (String) -> URL?
    typealias AppRunningChecker = @Sendable (String) -> Bool
    typealias OpenAction = @Sendable ([String]) throws -> Void
    typealias AppleScriptRunner = @Sendable (String) throws -> String
    typealias ProcessRunner = @Sendable (String, [String]) -> Bool

    private struct TerminalAppDescriptor {
        let displayName: String
        let bundleIdentifier: String
        let aliases: [String]
        let alternateBundleIdentifiers: [String]
        let preferredBundleIdentifiersByAlias: [String: String]

        init(
            displayName: String,
            bundleIdentifier: String,
            aliases: [String],
            alternateBundleIdentifiers: [String] = [],
            preferredBundleIdentifiersByAlias: [String: String] = [:]
        ) {
            self.displayName = displayName
            self.bundleIdentifier = bundleIdentifier
            self.aliases = aliases
            self.alternateBundleIdentifiers = alternateBundleIdentifiers
            self.preferredBundleIdentifiersByAlias = preferredBundleIdentifiersByAlias
        }

        var allBundleIdentifiers: [String] {
            [bundleIdentifier] + alternateBundleIdentifiers
        }
    }

    private static let knownApps: [TerminalAppDescriptor] = [
        TerminalAppDescriptor(
            displayName: "iTerm",
            bundleIdentifier: "com.googlecode.iterm2",
            aliases: ["iterm", "iterm2", "iterm.app"]
        ),
        TerminalAppDescriptor(
            displayName: "cmux",
            bundleIdentifier: "com.cmuxterm.app",
            aliases: ["cmux"]
        ),
        TerminalAppDescriptor(
            displayName: "Ghostty",
            bundleIdentifier: "com.mitchellh.ghostty",
            aliases: ["ghostty"]
        ),
        TerminalAppDescriptor(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            aliases: ["terminal", "apple_terminal"]
        ),
        TerminalAppDescriptor(
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            aliases: ["cursor"]
        ),
        TerminalAppDescriptor(
            displayName: "VS Code",
            bundleIdentifier: "com.microsoft.VSCode",
            aliases: ["vscode", "code", "visual studio code"]
        ),
        TerminalAppDescriptor(
            displayName: "VS Code Insiders",
            bundleIdentifier: "com.microsoft.VSCodeInsiders",
            aliases: ["vscode-insiders", "code-insiders"]
        ),
    ]

    /// Bundle identifiers of VS Code family editors. Derived from
    /// `vscodeFamilyCLI` so the two maps cannot drift.
    private static let vscodeFamilyBundleIDs: Set<String> = Set(vscodeFamilyCLI.keys)

    /// Bundle identifiers of terminal emulators that commonly host Zellij,
    /// derived from `knownApps` so it stays in sync automatically.
    private static let zellijParentTerminals = knownApps.map(\.bundleIdentifier)

    private static let ghosttyFocusSettleDelay = 0.08
    private static let ghosttyWindowActivationDelay = 0.04
    private static let ghosttyFocusAttempts = 3

    private let applicationResolver: ApplicationResolver
    private let appRunningChecker: AppRunningChecker
    private let openAction: OpenAction
    private let appleScriptRunner: AppleScriptRunner
    private let processRunner: ProcessRunner

    init(
        applicationResolver: @escaping ApplicationResolver = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        appRunningChecker: @escaping AppRunningChecker = { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
        },
        openAction: @escaping OpenAction = Self.defaultOpenAction(arguments:),
        appleScriptRunner: @escaping AppleScriptRunner = Self.defaultAppleScriptRunner(script:),
        processRunner: @escaping ProcessRunner = Self.defaultProcessRunner(executable:arguments:)
    ) {
        self.applicationResolver = applicationResolver
        self.appRunningChecker = appRunningChecker
        self.openAction = openAction
        self.appleScriptRunner = appleScriptRunner
        self.processRunner = processRunner
    }

    func jump(to target: JumpTarget) throws -> String {
        // tmux sessions: switch pane first, then use the terminal-specific
        // jump to focus the correct window/tab (not just activate the app).
        if let tmuxTarget = target.tmuxTarget, !tmuxTarget.isEmpty {
            let paneSelected = jumpToTmuxPane(target)

            let descriptor = resolveTerminalApp(preferredName: target.terminalApp)

            // Use the full terminal-specific jump (AppleScript for Ghostty/iTerm/Terminal)
            // to focus the correct window/tab.
            if let descriptor {
                switch descriptor.bundleIdentifier {
                case "com.mitchellh.ghostty":
                    if try jumpToGhosttyTerminal(target) {
                        return "Focused the matching tmux pane in Ghostty."
                    }
                case "com.googlecode.iterm2":
                    if try jumpToITermSession(target) {
                        return "Focused the matching tmux pane in iTerm."
                    }
                case "com.apple.Terminal":
                    if try jumpToTerminalTab(target) {
                        return "Focused the matching tmux pane in Terminal."
                    }
                default:
                    break
                }

                // Fallback: at least activate the app
                try openAction(["-b", descriptor.bundleIdentifier])
                return paneSelected
                    ? "Focused the matching tmux pane and activated \(descriptor.displayName)."
                    : "Activated \(descriptor.displayName). tmux pane targeting failed."
            }

            if paneSelected {
                return "Focused the matching tmux pane."
            }
        }

        let normalizedPreferredName = normalizeTerminalAppName(target.terminalApp)
        let descriptor = resolveTerminalApp(preferredName: target.terminalApp)
        let hasWorkingDirectory = target.workingDirectory.map { FileManager.default.fileExists(atPath: $0) } ?? false
        let hasPreciseLocator = [target.terminalSessionID, target.terminalTTY].contains {
            guard let value = $0?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.isEmpty
        }
        let preferredBundleIdentifier: String?
        if let descriptor {
            preferredBundleIdentifier = preferredBundleIdentifierForAlias(
                for: descriptor,
                normalizedPreferredName: normalizedPreferredName
            )
        } else {
            preferredBundleIdentifier = nil
        }

        let resolvedBundleIdentifier: String?
        if let descriptor {
            resolvedBundleIdentifier = resolveBundleIdentifier(
                for: descriptor,
                preferredBundleIdentifier: preferredBundleIdentifier
            )
        } else {
            resolvedBundleIdentifier = nil
        }
        let appIsRunning = resolvedBundleIdentifier.map(appRunningChecker) ?? false

        // Zellij is a terminal multiplexer, not a macOS .app. Handle it
        // before the descriptor-based dispatch since it won't have one.
        if target.terminalApp.lowercased() == "zellij" {
            if jumpToZellijPane(target) {
                return "Focused the matching Zellij pane."
            }
            // Fallback: activate whichever parent terminal is running.
            if let parentBundleID = Self.zellijParentTerminals.first(where: { appRunningChecker($0) }) {
                try openAction(["-b", parentBundleID])
                return "Activated parent terminal. Zellij pane targeting could not find the pane."
            }
            throw TerminalJumpError.unsupportedTerminal("Zellij (no parent terminal found)")
        }

        if let descriptor {
            switch resolvedBundleIdentifier ?? descriptor.bundleIdentifier {
            case "com.googlecode.iterm2":
                if try jumpToITermSession(target) {
                    return "Focused the matching iTerm session."
                }
            case "com.cmuxterm.app":
                if jumpToCmuxTerminal(target) {
                    return "Focused the matching cmux terminal."
                }
            case "com.mitchellh.ghostty":
                if try jumpToGhosttyTerminal(target) {
                    return "Focused the matching Ghostty terminal."
                }
            case "com.apple.Terminal":
                if try jumpToTerminalTab(target) {
                    return "Focused the matching Terminal tab."
                }
            case let id where Self.vscodeFamilyBundleIDs.contains(id):
                if let workingDirectory = target.workingDirectory {
                    let opened = jumpToVSCodeFamilyWorkspace(workingDirectory, bundleIdentifier: id)
                    if opened {
                        return "Focused the matching \(descriptor.displayName) workspace."
                    }
                }
                if appIsRunning {
                    try openAction(["-b", id])
                    return "Activated \(descriptor.displayName)."
                }
            default:
                break
            }
        }

        if let descriptor, hasPreciseLocator, appIsRunning {
            try openAction(["-b", resolvedBundleIdentifier ?? descriptor.bundleIdentifier])
            return "Activated \(descriptor.displayName). Exact pane targeting could not find the live terminal."
        }

        if let descriptor, hasWorkingDirectory, let workingDirectory = target.workingDirectory {
            try openAction(["-b", resolvedBundleIdentifier ?? descriptor.bundleIdentifier, workingDirectory])
            return "Opened \(target.workspaceName) in \(descriptor.displayName). Exact pane targeting is still best-effort."
        }

        if let descriptor {
            try openAction(["-b", resolvedBundleIdentifier ?? descriptor.bundleIdentifier])
            return "Activated \(descriptor.displayName). Exact pane targeting is still best-effort."
        }

        if hasWorkingDirectory, let workingDirectory = target.workingDirectory {
            try openAction([workingDirectory])
            return "Opened \(target.workspaceName) in Finder because no supported terminal app could be resolved."
        }

        throw TerminalJumpError.unsupportedTerminal(target.terminalApp)
    }

    private func jumpToITermSession(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set matched to false
                        if "\(escapeAppleScript(target.terminalSessionID))" is not "" and (id of aSession as text) is "\(escapeAppleScript(target.terminalSessionID))" then
                            set matched to true
                        end if
                        if not matched and "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aSession as text) is "\(escapeAppleScript(target.terminalTTY))" then
                            set matched to true
                        end if
                        if matched then
                            select aWindow
                            tell aWindow to select aTab
                            select aSession
                            return "matched"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """

        return try runAppleScript(script) == "matched"
    }

    // MARK: - VS Code family (VS Code, Insiders, Cursor)

    /// Maps bundle identifiers to the CLI command used to open a workspace.
    /// Single source of truth — `vscodeFamilyBundleIDs` is derived from these
    /// keys, so adding a fork here automatically routes its activation case.
    private static let vscodeFamilyCLI: [String: String] = [
        "com.microsoft.VSCode": "code",
        "com.microsoft.VSCodeInsiders": "code-insiders",
        "com.todesktop.230313mzl4w4u92": "cursor",
    ]

    private func jumpToVSCodeFamilyWorkspace(_ workspacePath: String, bundleIdentifier: String) -> Bool {
        guard let cli = Self.vscodeFamilyCLI[bundleIdentifier] else {
            return false
        }
        return processRunner(cli, ["-r", workspacePath])
    }

    private func jumpToCmuxTerminal(_ target: JumpTarget) -> Bool {
        // Focus the exact cmux surface via the official CLI. It resolves the
        // socket and handles auth for us, and returns non-zero if the focus
        // fails. The old hand-rolled JSON-RPC guessed the protocol, ignored
        // auth, and reported success even when nothing happened — so cmux
        // came forward on whatever surface was last active, not the session's.
        guard let surfaceID = target.terminalSessionID,
              !surfaceID.isEmpty else {
            // No surface ID — let the caller fall back to generic activation.
            return false
        }

        guard processRunner(Self.resolveCmuxBinary(), ["focus-panel", "--panel", surfaceID]) else {
            return false
        }

        // The surface is now selected inside cmux; bring its window forward.
        try? openAction(["-b", "com.cmuxterm.app"])
        return true
    }

    private static func resolveCmuxBinary() -> String {
        let bundled = "/Applications/cmux.app/Contents/Resources/bin/cmux"
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : "cmux"
    }

    // MARK: - Tmux CLI-based jump

    private func jumpToTmuxPane(_ target: JumpTarget) -> Bool {
        guard let tmuxTarget = target.tmuxTarget, !tmuxTarget.isEmpty else {
            return false
        }

        guard let tmuxPath = resolveTmuxPath() else {
            return false
        }

        // tmuxTarget is "session:window.pane" (e.g. "oss-contributions:3.0")
        // When running from a macOS GUI app (outside tmux), there is no
        // "current client" — $TMUX is not set. We must explicitly find the
        // client TTY and pass it via -c to switch-client.

        func socketArgs() -> [String] {
            if let socketPath = target.tmuxSocketPath, !socketPath.isEmpty {
                return ["-S", socketPath]
            }
            return []
        }

        // Extract "session:window" and "session" from "session:window.pane"
        let sessionWindow: String
        if let dotIndex = tmuxTarget.lastIndex(of: ".") {
            sessionWindow = String(tmuxTarget[tmuxTarget.startIndex..<dotIndex])
        } else {
            sessionWindow = tmuxTarget
        }

        let sessionName: String
        if let colonIndex = tmuxTarget.firstIndex(of: ":") {
            sessionName = String(tmuxTarget[tmuxTarget.startIndex..<colonIndex])
        } else {
            sessionName = tmuxTarget
        }

        // Find the client TTY so we can explicitly target it with switch-client.
        let clientTTY = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                                       args: ["list-clients", "-F", "#{client_tty}"])?
            .components(separatedBy: "\n").first { !$0.isEmpty }

        // Step 1: switch-client — point the client at the target session.
        if let clientTTY = clientTTY {
            _ = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                               args: ["switch-client", "-c", clientTTY, "-t", sessionName])
        }

        // Step 2: select-window — switch to the correct window.
        _ = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                           args: ["select-window", "-t", sessionWindow])

        // Step 3: select-pane — focus the exact pane.
        let spResult = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs(),
                                      args: ["select-pane", "-t", tmuxTarget])

        return spResult != nil
    }

    /// Run a tmux command and return its stdout (nil on failure).
    /// Uses the same direct-exec pattern as ActiveAgentProcessDiscovery.commandOutput.
    private func runTmuxCommand(tmuxPath: String, socketArgs: [String], args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = socketArgs + args

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return nil
        }
    }

    private func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback to 'which'
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["tmux"]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = FileHandle.nullDevice
        guard (try? whichTask.run()) != nil else { return nil }
        whichTask.waitUntilExit()
        guard whichTask.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    // MARK: - Zellij CLI-based jump

    /// Parses the encoded `terminalSessionID` (format: `paneId:sessionName`)
    /// and uses `zellij action` to switch to the tab containing that pane.
    private func jumpToZellijPane(_ target: JumpTarget) -> Bool {
        guard let encoded = target.terminalSessionID, !encoded.isEmpty else {
            return false
        }

        let parts = encoded.split(separator: ":", maxSplits: 1)
        let paneIDString = String(parts[0])
        let sessionName = parts.count > 1 ? String(parts[1]) : nil

        guard let paneID = Int(paneIDString) else {
            return false
        }

        guard let zellijPath = resolveZellijPath() else {
            return false
        }

        // Query all panes to find which tab contains our target pane.
        guard let tabPosition = zellijTabPosition(
            zellijPath: zellijPath,
            sessionName: sessionName,
            paneID: paneID
        ) else {
            return false
        }

        // Switch to the tab (1-indexed).
        let goToTab = Process()
        goToTab.executableURL = URL(fileURLWithPath: zellijPath)
        if let sessionName, !sessionName.isEmpty {
            goToTab.arguments = ["--session", sessionName, "action", "go-to-tab", "\(tabPosition + 1)"]
        } else {
            goToTab.arguments = ["action", "go-to-tab", "\(tabPosition + 1)"]
        }
        goToTab.standardOutput = FileHandle.nullDevice
        goToTab.standardError = FileHandle.nullDevice
        guard (try? goToTab.run()) != nil else { return false }
        goToTab.waitUntilExit()

        // Activate the parent terminal app window.
        if let parentBundleID = Self.zellijParentTerminals.first(where: { appRunningChecker($0) }) {
            try? openAction(["-b", parentBundleID])
        }

        return goToTab.terminationStatus == 0
    }

    private func resolveZellijPath() -> String? {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/zellij",
            "/usr/local/bin/zellij",
            "/opt/homebrew/bin/zellij",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback: which.
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["zellij"]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        whichTask.standardError = FileHandle.nullDevice
        guard (try? whichTask.run()) != nil else { return nil }
        whichTask.waitUntilExit()
        guard whichTask.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private struct ZellijPaneInfo: Decodable {
        let id: Int
        let tabPosition: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case tabPosition = "tab_position"
        }
    }

    /// Queries Zellij for pane info and returns the tab position of the given pane.
    private func zellijTabPosition(
        zellijPath: String,
        sessionName: String?,
        paneID: Int
    ) -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: zellijPath)
        var args: [String] = []
        if let sessionName, !sessionName.isEmpty {
            args += ["--session", sessionName]
        }
        args += ["action", "list-panes", "--json", "--tab"]
        task.arguments = args

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let panes = try? JSONDecoder().decode([ZellijPaneInfo].self, from: data) else {
            return nil
        }

        return panes.first(where: { $0.id == paneID })?.tabPosition
    }

    private func jumpToGhosttyTerminal(_ target: JumpTarget) throws -> Bool {
        try runAppleScript(ghosttyJumpScript(for: target)) == "matched"
    }

    func ghosttyJumpScript(for target: JumpTarget) -> String {
        let terminalSessionID = escapeAppleScript(target.terminalSessionID)
        let workingDirectory = escapeAppleScript(target.workingDirectory)
        let paneTitle = escapeAppleScript(target.paneTitle)

        return """
        tell application "Ghostty"
            if not (it is running) then return ""
            activate

            set targetWindow to missing value
            set targetTab to missing value
            set targetTerminal to missing value

            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aTerminal in terminals of aTab
                        if "\(terminalSessionID)" is not "" and (id of aTerminal as text) is "\(terminalSessionID)" then
                            set targetWindow to aWindow
                            set targetTab to aTab
                            set targetTerminal to aTerminal
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat

                if targetTerminal is not missing value then
                    exit repeat
                end if
            end repeat

            if targetTerminal is missing value and "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat

                        if targetTerminal is not missing value then
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat
            end if

            if targetTerminal is missing value and "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat

                        if targetTerminal is not missing value then
                            exit repeat
                        end if
                    end repeat

                    if targetTerminal is not missing value then
                        exit repeat
                    end if
                end repeat
            end if

            if targetTerminal is missing value then return ""

            if "\(terminalSessionID)" is "" then
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                if targetTab is not missing value then
                    select tab targetTab
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                focus targetTerminal
                delay \(Self.ghosttyFocusSettleDelay)
                return "matched"
            end if

            repeat \(Self.ghosttyFocusAttempts) times
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                if targetTab is not missing value then
                    select tab targetTab
                    delay \(Self.ghosttyWindowActivationDelay)
                end if

                focus targetTerminal
                -- Ghostty updates the focused split asynchronously after focus returns.
                delay \(Self.ghosttyFocusSettleDelay)

                try
                    if (id of focused terminal of selected tab of front window as text) is "\(terminalSessionID)" then
                        return "matched"
                    end if
                end try
            end repeat
        end tell
        return ""
        """
    }

    private func jumpToTerminalTab(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "Terminal"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aTab as text) is "\(escapeAppleScript(target.terminalTTY))" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                    if "\(escapeAppleScript(target.paneTitle))" is not "" and (custom title of aTab as text) contains "\(escapeAppleScript(target.paneTitle))" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """

        return try runAppleScript(script) == "matched"
    }

    private func resolveTerminalApp(preferredName: String) -> TerminalAppDescriptor? {
        let normalized = normalizeTerminalAppName(preferredName)

        // "Unknown" is the hook-side sentinel meaning "we could not classify this
        // terminal". Returning nil here lets jump() fall through to the Finder
        // cwd fallback instead of silently activating the first installed
        // known terminal — the historical behavior that caused sessions in an
        // unrecognized terminal to open the wrong app's windows.
        if normalized == "unknown" {
            return nil
        }

        if let exact = Self.knownApps.first(where: { descriptor in
            descriptor.displayName.lowercased() == normalized || descriptor.aliases.contains(normalized)
        }) {
            return exact
        }

        return Self.knownApps.first(where: isInstalled(descriptor:))
    }

    private func normalizeTerminalAppName(_ preferredName: String) -> String {
        preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isInstalled(descriptor: TerminalAppDescriptor) -> Bool {
        descriptor.allBundleIdentifiers.contains { applicationResolver($0) != nil }
    }

    private func preferredBundleIdentifierForAlias(
        for descriptor: TerminalAppDescriptor,
        normalizedPreferredName: String
    ) -> String? {
        if let aliasSpecific = descriptor.preferredBundleIdentifiersByAlias[normalizedPreferredName] {
            return aliasSpecific
        }
        if descriptor.displayName.lowercased() == normalizedPreferredName {
            return descriptor.bundleIdentifier
        }
        return nil
    }

    private func resolveBundleIdentifier(
        for descriptor: TerminalAppDescriptor,
        preferredBundleIdentifier: String?
    ) -> String {
        if let preferredBundleIdentifier, appRunningChecker(preferredBundleIdentifier) {
            return preferredBundleIdentifier
        }
        if let preferredBundleIdentifier, applicationResolver(preferredBundleIdentifier) != nil {
            return preferredBundleIdentifier
        }
        if let running = descriptor.allBundleIdentifiers.first(where: appRunningChecker) {
            return running
        }
        if let installed = descriptor.allBundleIdentifiers.first(where: { applicationResolver($0) != nil }) {
            return installed
        }
        return preferredBundleIdentifier ?? descriptor.bundleIdentifier
    }

    private func runAppleScript(_ script: String) throws -> String {
        try appleScriptRunner(script)
    }

    private static func defaultOpenAction(arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = arguments

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw TerminalJumpError.openFailed(arguments)
        }
    }

    private static func defaultAppleScriptRunner(script: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard task.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TerminalJumpError.appleScriptFailed(stderr.isEmpty ? script : stderr)
        }

        return output
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

    private func escapeAppleScript(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum TerminalJumpError: Error, LocalizedError {
    case unsupportedTerminal(String)
    case openFailed([String])
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedTerminal(terminal):
            "Could not resolve a supported terminal app for \(terminal)."
        case let .openFailed(arguments):
            "Failed to launch terminal with arguments: \(arguments.joined(separator: " "))"
        case let .appleScriptFailed(message):
            "Terminal automation failed: \(message)"
        }
    }
}
