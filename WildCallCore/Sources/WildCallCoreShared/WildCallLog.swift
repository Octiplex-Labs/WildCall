import Foundation
import os

/// Unified logging for the app and the extension. Messages go to os_log
/// (Console.app, sysdiagnose) and, in Debug builds, to stdout so that
/// `devicectl device process launch --console` shows them.
public enum WildCallLog {
    private static let logger = Logger(subsystem: "com.octiplex.wildcall", category: "store")

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("[WildCall] \(message)")
        #endif
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        #if DEBUG
        print("[WildCall] ERROR \(message)")
        #endif
    }
}
