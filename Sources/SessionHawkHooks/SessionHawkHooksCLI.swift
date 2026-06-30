import Foundation
import SessionHawkCore

@main
struct SessionHawkHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60

    static func main() {
        do {
            // Allow wrappers to delegate one child process away from Session Hawk without changing global hook installation.
            // 允许外部控制器只让当前子进程跳过 Session Hawk hook，不影响全局安装状态。
            if HookSkipConfiguration.shouldSkipHooks(environment: ProcessInfo.processInfo.environment) {
                return
            }

            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                return
            }

            let decoder = JSONDecoder()
            let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())

            let payload = try decoder
                .decode(ClaudeHookPayload.self, from: input)
                .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

            let timeout = payload.hookEventName == .permissionRequest
                ? interactiveClaudeHookTimeout
                : 45

            guard let response = try? client.send(.processClaudeHook(payload), timeout: timeout) else {
                logStderr("bridge unavailable for claude hook (\(payload.hookEventName.rawValue))")
                return
            }

            if let output = try ClaudeHookOutputEncoder.standardOutput(for: response) {
                FileHandle.standardOutput.write(output)
            }
        } catch {
            // Hooks should fail open so the CLI continues working even if the bridge is unavailable.
            logStderr("hook failed: \(error)")
        }
    }

    private static func logStderr(_ message: String) {
        guard let data = "[SessionHawkHooks] \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
