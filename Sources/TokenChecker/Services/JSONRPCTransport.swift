import Foundation

/// 行区切り JSON を組み立てる軽量バッファ。
struct JSONRPCLineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let line = pending.subdata(in: pending.startIndex..<nl)
            if !line.isEmpty { lines.append(line) }
            pending.removeSubrange(pending.startIndex...nl)
        }
        return lines
    }

    mutating func removeAll() { pending.removeAll(keepingCapacity: false) }
}

// MARK: - JSON-RPC envelope

struct RPCOutbound<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let id: Int?
    let params: Params?
}

struct RPCInbound: Decodable {
    let id: Int?
    let result: AnyDecodable?
    let error: RPCError?
    let method: String?

    struct RPCError: Decodable, Sendable {
        let code: Int?
        let message: String
    }
}

/// 任意の JSON 値を保持し、後で型付きにデコードし直すための包み。
struct AnyDecodable: Decodable, Sendable {
    let raw: Data

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(JSONValue.self) {
            self.raw = (try? JSONEncoder().encode(v)) ?? Data()
        } else {
            self.raw = Data()
        }
    }

    func decode<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: raw)
    }
}

/// 任意 JSON 値を一度受けるためのヘルパ。
indirect enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .number(let n):  try c.encode(n)
        case .string(let s):  try c.encode(s)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }
}
