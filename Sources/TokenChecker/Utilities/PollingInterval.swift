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
        case .sec30: return "30秒"
        case .min1:  return "1分"
        case .min2:  return "2分"
        case .min5:  return "5分"
        case .min10: return "10分"
        }
    }

    static let `default`: PollingInterval = .min1
}
