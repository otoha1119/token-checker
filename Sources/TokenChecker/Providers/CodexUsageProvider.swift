import Foundation

/// `codex app-server` を介して Codex の rate limit を取得。
/// アプリのライフタイム中 1 プロセスを共有する。失敗時は再起動を試みる。
final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    private let client: CodexAppServerClient

    init(client: CodexAppServerClient = .init()) {
        self.client = client
    }

    func fetch() async throws -> ServiceUsage {
        do {
            try await client.start()
            let dto = try await client.readRateLimits()
            return ServiceUsage(
                fiveHour: dto.fiveHourRateLimit(),
                weekly: dto.weeklyRateLimit(),
                weeklySonnet: nil
            )
        } catch DomainError.codexProcessExited {
            // 一度落ちていたら再起動して再試行
            await client.stop()
            try await client.start()
            let dto = try await client.readRateLimits()
            return ServiceUsage(
                fiveHour: dto.fiveHourRateLimit(),
                weekly: dto.weeklyRateLimit(),
                weeklySonnet: nil
            )
        }
    }

    func shutdown() async {
        await client.stop()
    }
}
