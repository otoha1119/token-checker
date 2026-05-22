import Foundation

/// 1 つのレート制限ウィンドウ。
struct RateLimit: Equatable, Sendable {
    /// 0.0 〜 1.0+。1.0 で 100% 使用。たまに 1.0 を超えることがある（API 側仕様）。
    let utilization: Double
    /// ウィンドウがリセットされる時刻。
    let resetsAt: Date

    var percent: Int { Int((utilization * 100).rounded()) }
}

/// 1 サービス（Claude / Codex）の使用状況。
struct ServiceUsage: Equatable, Sendable {
    let fiveHour: RateLimit?
    let weekly: RateLimit?
    /// Claude のみ。Sonnet 専用 7d ウィンドウ。
    let weeklySonnet: RateLimit?
}

/// 取得結果。片方が失敗しても他方は表示できるよう個別に保持。
struct UsageSnapshot: Equatable, Sendable {
    let claude: Result<ServiceUsage, DomainError>?
    let codex: Result<ServiceUsage, DomainError>?
    let fetchedAt: Date

    static let empty = UsageSnapshot(claude: nil, codex: nil, fetchedAt: .distantPast)
}
