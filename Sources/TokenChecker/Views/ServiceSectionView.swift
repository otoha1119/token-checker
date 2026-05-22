import SwiftUI

/// Claude / Codex 1 サービスぶんの詳細セクション。
struct ServiceSectionView: View {
    let title: String
    let symbol: String   // SF Symbol
    let result: Result<ServiceUsage, DomainError>?
    let loginAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    loginAction()
                } label: {
                    Image(systemName: "person.badge.key")
                }
                .buttonStyle(.borderless)
                .help("\(title) にログイン")
            }

            switch result {
            case .none:
                Text("取得中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .some(.success(let usage)):
                usageBlock(usage)
            case .some(.failure(let err)):
                errorBlock(err)
            }
        }
    }

    @ViewBuilder
    private func usageBlock(_ usage: ServiceUsage) -> some View {
        if let five = usage.fiveHour {
            limitRow(label: "5時間", limit: five)
        } else {
            Text("5時間ウィンドウのデータがありません")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        if let weekly = usage.weekly {
            secondaryRow(label: "週次", limit: weekly)
        }
        if let sonnet = usage.weeklySonnet {
            secondaryRow(label: "週次 (Sonnet)", limit: sonnet)
        }
    }

    private func limitRow(label: String, limit: RateLimit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(limit.percent)%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color(for: limit.utilization))
            }
            ProgressBarView(value: limit.utilization)
            Text(resetLabel(limit.resetsAt))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func secondaryRow(label: String, limit: RateLimit) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(limit.percent)%")
                .font(.system(size: 11))
                .foregroundStyle(color(for: limit.utilization))
        }
    }

    private func errorBlock(_ err: DomainError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("取得失敗")
                    .font(.system(size: 12, weight: .medium))
            }
            Text(err.errorDescription ?? "原因不明")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func color(for value: Double) -> Color {
        if value < 0.5 { return .green }
        if value < 0.75 { return .orange }
        return .red
    }

    private func resetLabel(_ date: Date) -> String {
        let now = Date()
        if date <= now { return "まもなくリセット" }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        let rel = f.string(from: now, to: date) ?? "—"
        let absolute = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        return "あと \(rel) (\(absolute) リセット)"
    }
}
