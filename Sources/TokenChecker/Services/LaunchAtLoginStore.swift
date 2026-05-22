import Foundation
import ServiceManagement
import OSLog

/// macOS 13+ の `SMAppService.mainApp` を扱うラッパ。
@MainActor
final class LaunchAtLoginStore: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        self.isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Logger.app.error("LaunchAtLogin toggle failed: \(error.localizedDescription)")
        }
        refresh()
    }
}
