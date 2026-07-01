import Foundation

/// Temporary file-based debug log. os_log from the ad-hoc-signed dev build is
/// not reliably visible via `log show`, so route diagnostics to a file that
/// can be tailed directly. Remove before shipping.
public enum SHDebugLog {
    public static let path = "/tmp/sessionhawk-debug.log"

    public static func log(_ message: String) {
        let line = "[\(Date().timeIntervalSince1970)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
