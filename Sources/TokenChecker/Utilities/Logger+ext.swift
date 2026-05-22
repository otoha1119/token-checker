import Foundation
import OSLog

extension Logger {
    static let subsystem = "com.token-checker.app"
    static let app = Logger(subsystem: subsystem, category: "App")
    static let claude = Logger(subsystem: subsystem, category: "Claude")
    static let codex = Logger(subsystem: subsystem, category: "Codex")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
