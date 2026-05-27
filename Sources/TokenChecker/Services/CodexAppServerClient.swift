@preconcurrency import Foundation
import OSLog

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
    /// `codex --version` の出力は actor ライフタイム中変わらないため、
    /// 最初に検出した起動フローを保持して再起動時の subprocess spawn を避ける。
    private var cachedLaunchFlow: CodexLaunchFlow?

    init(
        candidates: [String]? = nil,
        requestTimeout: TimeInterval = 8
    ) {
        self.candidates = candidates ?? Self.defaultCandidates()
        self.requestTimeout = requestTimeout
    }

    // MARK: - Lifecycle

    /// codex の起動方法は CLI のバージョンによって異なる。バージョン文字列を解析する
    /// 代わりに、複数の起動パターンを **順に試して** 最初に成立したものを採用する
    /// try-and-fallback 方式を採る。これにより codex 側がさらにコマンド体系を
    /// 変えてきても、新パターンを `CodexLaunchFlow.defaultProbeOrder` に足すだけで
    /// 対応できる (バージョン番号と紐付かない)。
    ///
    /// キャッシュ: 一度動いたフローを actor stored property に保持し、次回 `start()` 時
    /// は最優先で試す。失敗時のみ残りのパターンへフォールバックして自己修復する。
    func start() async throws {
        if process != nil { return }

        guard let executable = await resolveExecutable() else {
            throw DomainError.codexCLINotFound
        }

        let probeOrder = makeProbeOrder()

        var lastError: Error?
        for attempt in probeOrder {
            do {
                try await launch(executable: executable, attempt: attempt)
                if cachedLaunchFlow != attempt {
                    Logger.codex.info("launch succeeded with \(String(describing: attempt), privacy: .public)")
                    cachedLaunchFlow = attempt
                }
                return
            } catch {
                Logger.codex.notice("launch attempt \(String(describing: attempt), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
                // 中途半端な状態 (process が立っている / pipes が開いている) を確実に
                // 掃除してから次の attempt に移る。handleProcessTerminated が先に
                // 走っていれば stop() はほぼ no-op だが安全側で常に呼ぶ。
                stop()
                continue
            }
        }

        throw lastError ?? DomainError.codexProcessExited
    }

    /// キャッシュがあればそれを最優先、続いて残りの既定パターンを並べた probe 順を返す。
    private func makeProbeOrder() -> [CodexLaunchFlow] {
        let defaults = CodexLaunchFlow.defaultProbeOrder
        guard let cached = cachedLaunchFlow else { return defaults }
        return [cached] + defaults.filter { $0 != cached }
    }

    /// 単一の起動パターンを試行する。失敗時は throw、成功時は `self.process` 等が
    /// セットされ initialize handshake まで完了した状態で返る。
    private func launch(executable: URL, attempt: CodexLaunchFlow) async throws {
        // 旧 attempt の readabilityHandler が既に dispatch 済みのデータブロックを actor に
        // hop で持ち込みうる (stop() でハンドラを nil にしても、カーネル側が dispatch
        // した直後のブロックは取り消せない)。新 attempt の lineBuffer に残滓が混入すると
        // 後続 RPC の解析が乱れるため、defense-in-depth で冒頭でも消す。
        lineBuffer.removeAll()

        if attempt == .daemonAndProxy {
            try await Self.ensureDaemon(executable: executable)
        }

        let proc = Process()
        let inP = Pipe(), outP = Pipe(), errP = Pipe()

        proc.executableURL = executable
        // v0.130 以前: `codex app-server` 単体で stdio JSON-RPC サーバ
        // v0.133 以降: app-server は引数なし起動が廃止され、`app-server daemon start` で
        //              daemon を立て、`app-server proxy` が stdio bytes をリレーする
        proc.arguments = (attempt == .daemonAndProxy) ? ["app-server", "proxy"] : ["app-server"]
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
        errP.fileHandleForReading.readabilityHandler = { handle in
            // stderr を捨てるとしても availableData を読まなければ macOS のパイプバッファ
            // (既定 64 KiB) が解放されず、子プロセスが write(2) でブロックする。必ずドレインする。
            _ = handle.availableData
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
        // stop() → start() の再起動シーケンスで、旧プロセスの terminationHandler が
        // 遅延発火 → handleProcessTerminated() が actor に hop → 新プロセスの状態を
        // 破壊する race を防ぐため、terminate より前にハンドラを解除する。
        process?.terminationHandler = nil
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

    /// codex バイナリの絶対パスを決定する。
    ///
    /// 解決順序:
    ///   1. UserDefaults `codexPath` … `defaults write <bundle-id> codexPath /full/path`
    ///      で設定できる手動 escape hatch。未知の Node 環境管理ツールでも最終的に救える。
    ///   2. 既知の候補パス（Homebrew / nodebrew / volta / bun / asdf / nvm / fnm）。
    ///      シェル spawn を伴わないので最速。
    ///   3. ユーザーのログインシェル経由で `command -v codex`。
    ///      上記で見つからない場合の最終手段。3 秒でタイムアウト。
    ///      `.zshrc` 等を source する副作用に注意。
    private func resolveExecutable() async -> URL? {
        if let userPath = UserDefaults.standard.string(forKey: "codexPath"),
           !userPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: userPath) {
            return URL(fileURLWithPath: userPath)
        }

        if let known = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: known)
        }

        if let resolved = await Self.resolveViaShell() {
            return URL(fileURLWithPath: resolved)
        }

        return nil
    }

    /// 既知のインストール先候補。nvm / fnm はバージョン番号が中間ディレクトリに入るので
    /// 実在するエントリを降順に展開（新しい Node バージョンを優先）。
    private static func defaultCandidates() -> [String] {
        let home = NSHomeDirectory()
        var paths: [String] = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "\(home)/.nodebrew/current/bin/codex",
            "\(home)/.volta/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.asdf/shims/codex",
        ]

        paths.append(contentsOf: versionedCandidates(
            base: "\(home)/.nvm/versions/node",
            suffix: "bin/codex"
        ))

        paths.append(contentsOf: versionedCandidates(
            base: "\(home)/.local/share/fnm/node-versions",
            suffix: "installation/bin/codex"
        ))

        return paths
    }

    private static func versionedCandidates(base: String, suffix: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            return []
        }
        // 辞書順だと "v9.x" が "v22.x" より「大きい」になり古い Node を優先してしまう。
        // `.numeric` (locale 非依存) で数値部分を整数として比較し、semver 順で
        // 新しい版を先頭に。プレリリースタグ付き (e.g. "v22.0.0-rc.1") は
        // 正規リリースより後ろに送って rc ビルドを優先しないようにする。
        return entries
            .sorted { lhs, rhs in
                let lhsPre = lhs.contains("-")
                let rhsPre = rhs.contains("-")
                if lhsPre != rhsPre { return rhsPre }
                return lhs.compare(rhs, options: .numeric, locale: nil) == .orderedDescending
            }
            .map { "\(base)/\($0)/\(suffix)" }
    }

    /// ログインシェル経由で `command -v codex` を実行して絶対パスを得る。
    /// `command -v` は alias / function の場合に `/` で始まらない文字列を返すため、
    /// 出力行のうち `/` で始まり、かつ executable file である最後の行のみ採用する。
    private static func resolveViaShell() async -> String? {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shellPath)
        proc.arguments = ["-ilc", "command -v codex"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            proc.terminationHandler = { _ in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                _ = errPipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8) ?? ""
                let path = raw
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last { $0.hasPrefix("/") }

                if let path, FileManager.default.isExecutableFile(atPath: path) {
                    continuation.resume(returning: path)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if proc.isRunning {
                    proc.terminate()
                }
            }
        }
    }

    // MARK: - v0.133 daemon bootstrap

    /// v0.133+ で `codex app-server daemon start` を実行し daemon を確実に起動する。
    /// Issue #2 報告者の記述に従う (`app-server` のサブコマンドとして `daemon` が追加された)。
    /// 「準備完了まで待機して exit 0」想定で、既起動の場合も idempotent に成功する想定。
    /// タイムアウト 5 秒。
    private static func ensureDaemon(executable: URL) async throws {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = ["app-server", "daemon", "start"]
        proc.environment = childEnvironment(from: ProcessInfo.processInfo.environment)

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        enum Outcome {
            case ok
            case timedOut
            case badExit(Int32, String)
            case spawnFailed(String)
        }

        let outcome: Outcome = await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
            proc.terminationHandler = { p in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                _ = outPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                // タイムアウト時は自前で `terminate()` を呼ぶため、シグナル終了として観測される。
                // ここでは `.timedOut` を返し、報告メッセージを「exit=15」より明確な
                // 「タイムアウト」表記に切り替える。
                if p.terminationReason == .uncaughtSignal {
                    cont.resume(returning: .timedOut)
                } else if p.terminationStatus == 0 {
                    cont.resume(returning: .ok)
                } else {
                    cont.resume(returning: .badExit(p.terminationStatus, stderr))
                }
            }
            do {
                try proc.run()
            } catch {
                cont.resume(returning: .spawnFailed(error.localizedDescription))
                return
            }
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if proc.isRunning { proc.terminate() }
            }
        }

        switch outcome {
        case .ok:
            return
        case .timedOut:
            Logger.codex.error("app-server daemon start timed out after 5s")
            throw DomainError.network("codex app-server daemon start がタイムアウトしました (5s)")
        case .badExit(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.codex.error("app-server daemon start failed (exit=\(code, privacy: .public)): \(detail, privacy: .public)")
            throw DomainError.network("codex app-server daemon start failed (exit=\(code))")
        case .spawnFailed(let detail):
            Logger.codex.error("app-server daemon start spawn failed: \(detail, privacy: .public)")
            throw DomainError.network("codex app-server daemon start spawn failed: \(detail)")
        }
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
        // 子プロセスの異常終了 (外部 kill / OOM 等) でこの経路を通る場合、
        // stop() を介さないため Pipe の fd を明示的に閉じる必要がある。
        // 閉じないと CodexUsageProvider の再起動ループで fd が累積し枯渇する。
        try? stdin?.fileHandleForWriting.close()
        try? stdout?.fileHandleForReading.close()
        try? stderr?.fileHandleForReading.close()
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

/// `account/rateLimits/read` のレスポンス。
///
/// 実際の構造（codex-usage-menu のテストフィクスチャから確認）:
/// ```json
/// {
///   "rateLimits": {
///     "limitId": "codex",
///     "primary":   { "usedPercent": 25, "windowDurationMins": 300,   "resetsAt": 1760000000 },
///     "secondary": { "usedPercent": 28, "windowDurationMins": 10080, "resetsAt": 1760604800 },
///     "planType": "pro"
///   },
///   "rateLimitsByLimitId": { "codex": { ... 同じ構造 ... } }
/// }
/// ```
///
/// - JSON キーは camelCase（snake_case ではない）
/// - `usedPercent` は **0〜100 の Int**
/// - `resetsAt` は **Unix epoch 秒の Int64**
/// - `windowDurationMins`: 300 = 5 時間、10080 = 週次
struct CodexRateLimitsDTO: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?

    struct RateLimitSnapshot: Decodable, Sendable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Int?
        let windowDurationMins: Int64?
        let resetsAt: Int64?
    }
}

extension CodexRateLimitsDTO {
    /// 5h (300 分) ウィンドウを抽出。
    func fiveHourRateLimit() -> RateLimit? {
        window(forDurationMins: 300).flatMap(Self.toRateLimit)
    }

    /// 週次 (10080 分) ウィンドウを抽出。
    func weeklyRateLimit() -> RateLimit? {
        window(forDurationMins: 10080).flatMap(Self.toRateLimit)
    }

    /// 指定分数のウィンドウを探す。primary/secondary 両方を見る。
    ///
    /// 優先順位:
    ///   1. トップレベル `rateLimits` … 現アカウントの直接スナップショット
    ///   2. `rateLimitsByLimitId` … 複数 limitId が同居しうる。Dictionary の
    ///      iteration 順は Hasher seed 依存で起動ごとに変動するため、
    ///      key ソートで安定化してから走査する。
    private func window(forDurationMins minutes: Int64) -> Window? {
        if let snap = rateLimits {
            if let p = snap.primary,   p.windowDurationMins == minutes { return p }
            if let s = snap.secondary, s.windowDurationMins == minutes { return s }
        }
        let sortedSnapshots = (rateLimitsByLimitId ?? [:]).sorted(by: { $0.key < $1.key })
        for (_, snap) in sortedSnapshots {
            if let p = snap.primary,   p.windowDurationMins == minutes { return p }
            if let s = snap.secondary, s.windowDurationMins == minutes { return s }
        }
        return nil
    }

    /// `usedPercent` または `resetsAt` が欠落しているウィンドウは「データなし」として nil 返却。
    /// 旧実装は欠落値を 0 にフォールバックしていたため、Codex API がフィールドを返さなくなった
    /// 際に `resetsAt = 1970-01-01` となり UI が永続的に「まもなくリセット」を表示してしまっていた。
    private static func toRateLimit(_ window: Window) -> RateLimit? {
        guard let used = window.usedPercent, let resets = window.resetsAt else { return nil }
        // Window モデル内の usedPercent は 0-100 の Int 想定なので /100 で 0.0-1.0 化。
        // 負値は API バグとして 0 に丸める。上限は呼び出し側 (MenuBarLabel) で表示時に処理。
        let utilization = max(0, Double(used) / 100.0)
        let date = Date(timeIntervalSince1970: TimeInterval(resets))
        return RateLimit(utilization: utilization, resetsAt: date)
    }
}

// MARK: - Codex CLI version model

/// `codex app-server` の起動方法は CLI のバージョンで異なる。
///
/// バージョン文字列を解析する代わりに `defaultProbeOrder` を順に試す
/// try-and-fallback 方式 (CodexAppServerClient.start() を参照)。新しいパターンが
/// 出てきたら enum と `defaultProbeOrder` に足すだけで追従できる。
fileprivate enum CodexLaunchFlow: Sendable {
    /// v0.130 まで: `codex app-server` 単体で stdio JSON-RPC サーバ。
    case stdio
    /// v0.133 以降: `codex app-server daemon start` で daemon を起動し、
    /// `codex app-server proxy` で stdio をリレー。
    case daemonAndProxy

    /// 試行順序。新しい方を先頭に置く (将来 v0.150 等で別の方式が来たらここに追加)。
    /// v0.130 ユーザーの初回起動は先頭の失敗で 1〜2 秒遅れるが、actor 内キャッシュで
    /// 2 回目以降は即座に成功パターンが選ばれる。
    static let defaultProbeOrder: [CodexLaunchFlow] = [.daemonAndProxy, .stdio]
}
