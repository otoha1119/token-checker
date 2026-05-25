import Foundation

enum PollingInterval: Int, CaseIterable, Identifiable, Codable, Sendable {
    case sec30 = 30
    case min1 = 60
    case min2 = 120
    case min5 = 300
    case min10 = 600

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .sec30: return L10n.tr("interval.sec30")
        case .min1:  return L10n.tr("interval.min1")
        case .min2:  return L10n.tr("interval.min2")
        case .min5:  return L10n.tr("interval.min5")
        case .min10: return L10n.tr("interval.min10")
        }
    }

    /// Anthropic OAuth usage エンドポイントの暗黙レートリミットを考慮して 5 分をデフォルトに。
    /// 値表示用としては十分で、`oauth/usage` への過剰アクセスを避けられる。
    static let `default`: PollingInterval = .min5
}
