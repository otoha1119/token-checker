import Foundation

/// Claude / Codex / Mock を差し替え可能にするための抽象。
protocol UsageProvider: Sendable {
    /// 1 サービスぶんの使用状況を返す。失敗時は DomainError を throw。
    func fetch() async throws -> ServiceUsage
}
