import SwiftUI

@main
struct TokenCheckerApp: App {
    @State private var viewModel = UsageViewModel()
    @StateObject private var launchAtLogin = LaunchAtLoginStore()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(viewModel: viewModel, launchAtLogin: launchAtLogin)
                .onAppear { launchAtLogin.refresh() }
        } label: {
            MenuBarLabel(viewModel: viewModel)
                .task(id: viewModel.pollingInterval) {
                    await viewModel.runPollingLoop()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
