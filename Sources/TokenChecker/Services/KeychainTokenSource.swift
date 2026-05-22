import Foundation

/// macOS Keychain から Claude Code の OAuth トークンを読み取る。
///
/// `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` を spawn する。
/// 直接 Security framework を叩いてもよいが、CLI 経由のほうが ACL 確認のダイアログ UX が
/// 安定する（CCMeter と同じ方針）。
struct KeychainTokenSource: Sendable {
    static let serviceName = "Claude Code-credentials"

    /// Keychain のレコード値（JSON）から access_token を抜き出して返す。
    func readAccessToken() async throws -> String {
        let username = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", username,
            "-s", Self.serviceName,
            "-w",
        ]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw DomainError.keychainTokenMissing
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DomainError.keychainTokenMissing
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let payload: KeychainPayload
        do {
            payload = try JSONDecoder().decode(KeychainPayload.self, from: data)
        } catch {
            throw DomainError.decoding("Keychain payload: \(error.localizedDescription)")
        }

        guard let token = payload.claudeAiOauth?.accessToken, !token.isEmpty else {
            throw DomainError.keychainTokenMissing
        }
        return token
    }
}

/// Claude Code が Keychain に保存する JSON 構造。CCMeter のフィクスチャと一致する形を採用。
private struct KeychainPayload: Decodable {
    let claudeAiOauth: OAuth?

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claudeAiOauth"
    }

    struct OAuth: Decodable {
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "accessToken"
        }
    }
}
