import SwiftUI

struct ProgressBarView: View {
    let value: Double   // 0.0〜1.0
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
    }

    private var clamped: Double { min(max(value, 0), 1) }
    private var color: Color {
        if value < 0.5 { return .green }
        if value < 0.75 { return .orange }
        return .red
    }
}
