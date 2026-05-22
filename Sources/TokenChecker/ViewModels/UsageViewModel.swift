import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class UsageViewModel {
    private let claudeProvider: UsageProvider
    private let codexProvider: UsageProvider

    var snapshot: UsageSnapshot = .empty
    var isLoading: Bool = false
    var pollingInterval: PollingInterval {
        didSet { persistInterval() }
    }

    init(
        claudeProvider: UsageProvider = ClaudeUsageProvider(),
        codexProvider: UsageProvider = CodexUsageProvider()
    ) {
        self.claudeProvider = claudeProvider
        self.codexProvider = codexProvider
        self.pollingInterval = Self.loadPersistedInterval()
    }

    /// `task(id: pollingInterval)` から駆動するメインループ。
    func runPollingLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval.seconds * 1_000_000_000))
            } catch {
                return
            }
            await refresh()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let claude = fetchClaude()
        async let codex = fetchCodex()

        let (c, x) = await (claude, codex)
        snapshot = UsageSnapshot(claude: c, codex: x, fetchedAt: Date())
    }

    private func fetchClaude() async -> Result<ServiceUsage, DomainError> {
        do {
            return .success(try await claudeProvider.fetch())
        } catch let err as DomainError {
            Logger.claude.error("fetch failed: \(err.localizedDescription)")
            return .failure(err)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func fetchCodex() async -> Result<ServiceUsage, DomainError> {
        do {
            return .success(try await codexProvider.fetch())
        } catch let err as DomainError {
            Logger.codex.error("fetch failed: \(err.localizedDescription)")
            return .failure(err)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - ログインボタン

    /// どのサービスを再ログインするかは enum 型で表現する。
    /// 任意文字列を AppleScript に渡せないようにしてインジェクションを「型として」不能にする。
    enum LoginTarget {
        case claude
        case codex

        var command: String {
            switch self {
            case .claude: return "claude login"
            case .codex:  return "codex login"
            }
        }
    }

    func openClaudeLogin() { spawnLogin(.claude) }
    func openCodexLogin()  { spawnLogin(.codex) }

    private func spawnLogin(_ target: LoginTarget) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(target.command)"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do { try process.run() } catch {
            Logger.ui.error("login spawn failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 永続化

    private static let intervalKey = "pollingInterval"

    private static func loadPersistedInterval() -> PollingInterval {
        let raw = UserDefaults.standard.integer(forKey: intervalKey)
        return PollingInterval(rawValue: raw) ?? .default
    }

    private func persistInterval() {
        UserDefaults.standard.set(pollingInterval.rawValue, forKey: Self.intervalKey)
    }
}
