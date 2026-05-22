@preconcurrency import Foundation

/// `codex app-server` を spawn して JSON-RPC で会話する actor。
///
/// 大まかな流れ:
///   1. `start()` で Process を spawn → `initialize` → `initialized` の handshake
///   2. `readRateLimits()` で `account/rateLimits/read` を叩く
///   3. アプリ終了時に `stop()` で Process を終了
actor CodexAppServerClient {
    private let candidates: [String]
    private let requestTimeout: TimeInterval

    private var nextId = 1
    private var pending: [Int: CheckedContinuation<RPCInbound, Error>] = [:]
    private var process: Process?
    private var stdin: Pipe?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var lineBuffer = JSONRPCLineBuffer()

    init(
        candidates: [String] = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ],
        requestTimeout: TimeInterval = 8
    ) {
        self.candidates = candidates
        self.requestTimeout = requestTimeout
    }

    // MARK: - Lifecycle

    func start() async throws {
        if process != nil { return }

        guard let executable = resolveExecutable() else {
            throw DomainError.codexCLINotFound
        }

        let proc = Process()
        let inP = Pipe(), outP = Pipe(), errP = Pipe()

        proc.executableURL = executable
        proc.arguments = ["app-server"]
        proc.environment = Self.childEnvironment(from: ProcessInfo.processInfo.environment)
        proc.standardInput = inP
        proc.standardOutput = outP
        proc.standardError = errP

        proc.terminationHandler = { [weak self] _ in
            Task { await self?.handleProcessTerminated() }
        }

        outP.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleStdout(data) }
        }
        errP.fileHandleForReading.readabilityHandler = { _ in
            // stderr は破棄（必要なら Logger に流す）
        }

        do {
            try proc.run()
        } catch {
            throw DomainError.network("codex app-server failed to start: \(error.localizedDescription)")
        }

        self.process = proc
        self.stdin = inP
        self.stdout = outP
        self.stderr = errP

        _ = try await request(method: "initialize", params: InitializeParams.defaultClient)
        try send(method: "initialized", params: EmptyParams(), isNotification: true)
    }

    func stop() {
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        try? stdin?.fileHandleForWriting.close()
        try? stdout?.fileHandleForReading.close()
        try? stderr?.fileHandleForReading.close()
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        lineBuffer.removeAll()
        failPending(with: DomainError.codexProcessExited)
    }

    // MARK: - RPC methods

    func readRateLimits() async throws -> CodexRateLimitsDTO {
        let envelope = try await request(method: "account/rateLimits/read", params: EmptyParams())
        guard let result = envelope.result else {
            throw DomainError.codexRPCError(message: "missing result for account/rateLimits/read")
        }
        do {
            return try result.decode(as: CodexRateLimitsDTO.self)
        } catch {
            throw DomainError.decoding("codex rateLimits: \(error.localizedDescription)")
        }
    }

    // MARK: - Internals

    private func resolveExecutable() -> URL? {
        candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// 子プロセス (`codex app-server`) に渡す環境変数を最小限の whitelist で構築する。
    ///
    /// 親プロセス（このアプリ）の環境変数をそのまま継承させると、ターミナル経由で
    /// 起動した場合に `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `AWS_*` 等の秘密が
    /// 子に渡ってしまう。codex 自身が必要とするのは PATH と HOME 程度なので、
    /// それ以外は意図的に渡さない。
    private static func childEnvironment(from base: [String: String]) -> [String: String] {
        // codex が動くのに必要な最小キーだけ通す
        let allowedKeys: Set<String> = [
            "HOME", "USER", "LOGNAME", "SHELL",
            "LANG", "LC_ALL", "LC_CTYPE",
            "TMPDIR",
            "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
            // codex CLI 固有
            "CODEX_HOME",
        ]
        var env: [String: String] = [:]
        for key in allowedKeys {
            if let value = base[key] { env[key] = value }
        }

        // PATH は固定セット + 親の PATH の安全な部分をマージ
        let basePathDirs = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var seen = Set<String>()
        let merged = (extras + basePathDirs).filter { seen.insert($0).inserted }.joined(separator: ":")
        env["PATH"] = merged
        return env
    }

    private func send<P: Encodable>(method: String, params: P?, isNotification: Bool = false) throws {
        guard let stdin else {
            throw DomainError.codexProcessExited
        }
        let id: Int? = isNotification ? nil : { defer { self.nextId += 1 }; return self.nextId }()
        let envelope = RPCOutbound(method: method, id: id, params: params)
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)
        stdin.fileHandleForWriting.write(data)
    }

    /// 1 リクエストを投げて、レスポンスかタイムアウトのどちらかで完了する。
    ///
    /// 競合状態の扱い：
    /// - 書き込みは actor isolated な同期処理として実行（hop なし）
    /// - `withCheckedThrowingContinuation` のクロージャ本体も同 actor 内で動くので
    ///   `pending[id] = cont` は atomic に登録される
    /// - タイムアウト Task が `cancelPending(id:)` を呼ぶことで継続が確実に解決される
    /// - レスポンスが先に来た場合は `defer` でタイムアウト Task を cancel して終了
    private func request<P: Encodable>(method: String, params: P) async throws -> RPCInbound {
        guard let stdin else { throw DomainError.codexProcessExited }
        let id = nextId
        nextId += 1
        let timeout = requestTimeout

        // 同期的にエンコードして書き込み（actor 内、hop なし）
        let envelope = RPCOutbound(method: method, id: id, params: params)
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)
        stdin.fileHandleForWriting.write(data)

        // タイムアウト監視タスクを別途起動
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled {
                await self?.cancelPending(id: id)
            }
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RPCInbound, Error>) in
            // クロージャは actor isolated な同期コンテキストで実行される
            pending[id] = cont
        }
    }

    /// レスポンス到着時に呼ぶ。継続がすでに無ければ no-op（タイムアウト後の到着など）。
    private func resumePending(id: Int, with result: Result<RPCInbound, Error>) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        switch result {
        case .success(let env): cont.resume(returning: env)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    /// タイムアウト時に呼ぶ。継続を timeout エラーで終わらせる。
    private func cancelPending(id: Int) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(throwing: DomainError.timeout)
    }

    private func failPending(with error: DomainError) {
        let snapshot = pending
        pending.removeAll()
        for cont in snapshot.values {
            cont.resume(throwing: error)
        }
    }

    // MARK: - Stream handling

    private func handleStdout(_ data: Data) {
        if data.isEmpty {
            handleProcessTerminated()
            return
        }
        for line in lineBuffer.append(data) {
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        do {
            let inbound = try JSONDecoder().decode(RPCInbound.self, from: data)
            if let id = inbound.id {
                resumePending(id: id, with: .success(inbound))
            }
            // notifications (no id) は今は無視
        } catch {
            // 不正な行は捨てる
        }
    }

    private func handleProcessTerminated() {
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        lineBuffer.removeAll()
        failPending(with: .codexProcessExited)
    }
}

// MARK: - RPC params / DTOs

struct EmptyParams: Encodable, Sendable {}

struct InitializeParams: Encodable, Sendable {
    let clientInfo: ClientInfo
    let capabilities: Capabilities

    struct ClientInfo: Encodable, Sendable {
        let name: String
        let version: String
    }
    struct Capabilities: Encodable, Sendable {}

    static let defaultClient = InitializeParams(
        clientInfo: .init(name: "token-checker", version: "0.1.0"),
        capabilities: .init()
    )
}

/// `account/rateLimits/read` のレスポンス（ラフな構造 — bucket 配列を抜き出して使う）。
struct CodexRateLimitsDTO: Decodable, Sendable {
    let buckets: [Bucket]?
    let rateLimitWindows: [Bucket]?
    let rateLimits: [Bucket]?

    enum CodingKeys: String, CodingKey {
        case buckets
        case rateLimitWindows = "rate_limit_windows"
        case rateLimits = "rate_limits"
    }

    /// 名前が揺れることに備えて全候補をマージ。
    var allBuckets: [Bucket] {
        (buckets ?? []) + (rateLimitWindows ?? []) + (rateLimits ?? [])
    }

    struct Bucket: Decodable, Sendable {
        let windowMinutes: Int?
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case windowMinutes = "window_minutes"
            case utilization
            case resetsAt = "resets_at"
        }
    }
}

extension CodexRateLimitsDTO {
    /// 5h (300 分) バケットを抽出して RateLimit に変換。
    func fiveHourRateLimit() -> RateLimit? {
        rateLimit(forWindow: 300)
    }

    /// 週次 (10080 分) バケットを抽出。
    func weeklyRateLimit() -> RateLimit? {
        rateLimit(forWindow: 10080)
    }

    private func rateLimit(forWindow minutes: Int) -> RateLimit? {
        guard let bucket = allBuckets.first(where: { $0.windowMinutes == minutes }),
              let utilization = bucket.utilization,
              let resetsAt = bucket.resetsAt,
              let date = ISO8601DateFormatter.standard.date(from: resetsAt)
                          ?? ISO8601DateFormatter.withFractional.date(from: resetsAt) else {
            return nil
        }
        // Codex は 0.0〜1.0 で返す前提（仕様未確定なので念のため >1 にも対応）
        let normalized = utilization > 1.5 ? utilization / 100.0 : utilization
        return RateLimit(utilization: normalized, resetsAt: date)
    }
}
