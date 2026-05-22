import SwiftUI
import AppKit

/// メニューバーに表示する「2 つのドーナツ + %」。
///
/// SwiftUI ビューを `ImageRenderer` で NSImage に焼いて、
/// `Image(nsImage:)` でメニューバーに渡す。
/// `MenuBarExtra` の label に SwiftUI ビューを直接渡すとフォント等が制限されるため。
struct MenuBarLabel: View {
    let viewModel: UsageViewModel

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Text("TC ⏳")
        }
    }

    private var renderedImage: NSImage? {
        let claude = utilization(from: viewModel.snapshot.claude)
        let codex = utilization(from: viewModel.snapshot.codex)
        let content = HStack(spacing: 6) {
            HStack(spacing: 3) {
                DonutChartView(
                    value: claude ?? 0,
                    size: 20,
                    lineWidth: 3,
                    center: .sfSymbol("sparkles", scale: 0.48)
                )
                Text(percentLabel(claude))
                    .font(.system(size: 11, weight: .semibold))
            }
            HStack(spacing: 3) {
                DonutChartView(
                    value: codex ?? 0,
                    size: 20,
                    lineWidth: 3,
                    center: .sfSymbol("terminal.fill", scale: 0.48)
                )
                Text(percentLabel(codex))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 2)
        .foregroundStyle(Color.primary)

        let renderer = ImageRenderer(content: content)
        // ビットマップは高 DPI で焼いておく．image.size には触らない
        // （触ると point 単位として誤認されて表示サイズまで縮んでしまう）．
        let maxScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        renderer.scale = max(maxScale, 3)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    private func utilization(from result: Result<ServiceUsage, DomainError>?) -> Double? {
        guard case .success(let usage) = result else { return nil }
        return usage.fiveHour?.utilization
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let v = value else { return "--%" }
        return "\(Int((v * 100).rounded()))%"
    }
}
