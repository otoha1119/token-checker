import Foundation

enum DomainError: Error, Equatable, LocalizedError, Sendable {
    case keychainTokenMissing
    case anthropicUnauthorized
    case anthropicRateLimited(retryAfter: TimeInterval?)
    case anthropicHTTP(status: Int)
    case codexCLINotFound
    case codexProcessExited
    case codexRPCError(message: String)
    case decoding(String)
    case timeout
    case network(String)

    var errorDescription: String? {
        switch self {
        case .keychainTokenMissing:
            return L10n.tr("error.keychain_token_missing")
        case .anthropicUnauthorized:
            return L10n.tr("error.anthropic_unauthorized")
        case .anthropicRateLimited(let retryAfter):
            if let sec = retryAfter {
                let mins = max(1, Int((sec / 60).rounded()))
                return L10n.format("error.anthropic_rate_limited_with_retry", mins)
            }
            return L10n.tr("error.anthropic_rate_limited")
        case .anthropicHTTP(let status):
            return L10n.format("error.anthropic_http", status)
        case .codexCLINotFound:
            return L10n.tr("error.codex_cli_not_found")
        case .codexProcessExited:
            return L10n.tr("error.codex_process_exited")
        case .codexRPCError(let message):
            return L10n.format("error.codex_rpc", message)
        case .decoding(let detail):
            return L10n.format("error.decoding", detail)
        case .timeout:
            return L10n.tr("error.timeout")
        case .network(let detail):
            return L10n.format("error.network", detail)
        }
    }
}
