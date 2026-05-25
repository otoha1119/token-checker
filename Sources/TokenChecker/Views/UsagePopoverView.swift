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
                brand: .claude,
                result: viewModel.snapshot.claude,
                loginAction: { viewModel.openClaudeLogin() }
            )

            Divider()

            ServiceSectionView(
                title: "Codex",
                brand: .codex,
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
            Text("Token Checker")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
    }

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("settings.refresh_interval"))
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
                Text(L10n.tr("settings.launch_at_login"))
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
                Text(L10n.format(
                    "footer.updated_at",
                    DateFormatter.localizedString(from: viewModel.snapshot.fetchedAt, dateStyle: .none, timeStyle: .short)
                ))
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
            .help(L10n.tr("footer.refresh_now"))

            Button(L10n.tr("footer.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
