import Foundation

/// Keychain → Anthropic OAuth usage エンドポイント。
struct ClaudeUsageProvider: UsageProvider {
    let keychain: KeychainTokenSource
    let api: AnthropicUsageAPIClient

    init(keychain: KeychainTokenSource = .init(), api: AnthropicUsageAPIClient = .init()) {
        self.keychain = keychain
        self.api = api
    }

    func fetch() async throws -> ServiceUsage {
        let token = try await keychain.readAccessToken()
        let dto = try await api.fetch(accessToken: token)
        return ServiceUsage(
            fiveHour: dto.fiveHour?.toRateLimit(),
            weekly: dto.sevenDay?.toRateLimit(),
            weeklySonnet: dto.sevenDaySonnet?.toRateLimit()
        )
    }
}
