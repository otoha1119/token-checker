import Foundation

enum DomainError: Error, Equatable, LocalizedError, Sendable {
    case keychainTokenMissing
    case anthropicUnauthorized
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
            return "Claude Code の OAuth トークンが Keychain に見つかりません。ターミナルで `claude login` を実行してください。"
        case .anthropicUnauthorized:
            return "Anthropic からの認証エラー (401)。`claude login` で再ログインしてください。"
        case .anthropicHTTP(let status):
            return "Anthropic API エラー (status \(status))"
        case .codexCLINotFound:
            return "Codex CLI が見つかりません。`npm i -g @openai/codex` を実行してください。"
        case .codexProcessExited:
            return "codex app-server が終了しました。再起動を試みます。"
        case .codexRPCError(let message):
            return "Codex RPC エラー: \(message)"
        case .decoding(let detail):
            return "レスポンスのデコードに失敗: \(detail)"
        case .timeout:
            return "通信がタイムアウトしました。"
        case .network(let detail):
            return "ネットワークエラー: \(detail)"
        }
    }
}
