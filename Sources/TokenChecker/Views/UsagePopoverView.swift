import SwiftUI
import AppKit

struct UsagePopoverView: View {
    @Bindable var viewModel: UsageViewModel
    @ObservedObject var launchAtLogin: LaunchAtLoginStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ServiceSectionView(
                title: "Claude Code",
                symbol: "sparkles",
                result: viewModel.snapshot.claude,
                loginAction: { viewModel.openClaudeLogin() }
            )

            Divider()

            ServiceSectionView(
                title: "Codex",
                symbol: "chevron.left.forwardslash.chevron.right",
                result: viewModel.snapshot.codex,
                loginAction: { viewModel.openCodexLogin() }
            )

            Divider()
            settingsBlock
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text("Token Checker")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
    }

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("更新間隔")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $viewModel.pollingInterval) {
                    ForEach(PollingInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            HStack {
                Text("ログイン時に自動起動")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { _ in launchAtLogin.toggle() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.snapshot.fetchedAt > .distantPast {
                Text("更新: \(DateFormatter.localizedString(from: viewModel.snapshot.fetchedAt, dateStyle: .none, timeStyle: .short))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("今すぐ更新")

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
