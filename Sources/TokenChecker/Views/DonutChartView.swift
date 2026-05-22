import SwiftUI

/// 5h usage 1 本ぶんの円形プログレス。CCMeter の二重ドーナツから内側 7d を削除した版。
struct DonutChartView: View {
    let value: Double   // 0.0 〜 1.0
    var size: CGFloat = 18
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)
                .frame(width: size - lineWidth, height: size - lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var clamped: Double { min(max(value, 0), 1) }
    private var color: Color {
        if value < 0.5 { return .green }
        if value < 0.75 { return .orange }
        return .red
    }
}
