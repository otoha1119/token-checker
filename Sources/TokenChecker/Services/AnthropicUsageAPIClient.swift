import Foundation

/// Anthropic の OAuth ベース usage エンドポイントを叩いて生 DTO を返す。
struct AnthropicUsageAPIClient: Sendable {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch(accessToken: String) async throws -> AnthropicUsageDTO {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DomainError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DomainError.network("Invalid response")
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw DomainError.anthropicUnauthorized
        default:
            throw DomainError.anthropicHTTP(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(AnthropicUsageDTO.self, from: data)
        } catch {
            throw DomainError.decoding("Anthropic usage: \(error.localizedDescription)")
        }
    }
}

// MARK: - DTO

struct AnthropicUsageDTO: Decodable, Sendable {
    let fiveHour: BucketDTO?
    let sevenDay: BucketDTO?
    let sevenDaySonnet: BucketDTO?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    struct BucketDTO: Decodable, Sendable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

extension AnthropicUsageDTO.BucketDTO {
    func toRateLimit() -> RateLimit? {
        guard let utilization, let resetsAt else { return nil }
        guard let date = ISO8601DateFormatter.standard.date(from: resetsAt)
                       ?? ISO8601DateFormatter.withFractional.date(from: resetsAt) else {
            return nil
        }
        return RateLimit(utilization: utilization / 100.0, resetsAt: date)
    }
}

extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
