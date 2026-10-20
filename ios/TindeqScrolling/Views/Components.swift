import SwiftUI
import TindeqCore

enum Theme {
    // Same accents as the Android HUD.
    static let holding = Color(red: 0.41, green: 0.94, blue: 0.68)
    static let warning = Color(red: 1.00, green: 0.84, blue: 0.25)
    static let blocked = Color(red: 1.00, green: 0.32, blue: 0.32)
    static let scroll = Color(red: 0.49, green: 0.55, blue: 1.00)

    static func color(for mode: GateMode) -> Color {
        switch mode {
        case .holding: holding
        case .warning: warning
        case .blocked: blocked
        case .idle: .white
        }
    }
}

/// Horizontal force bar with tick marks at min pull and scroll pull.
struct ForceMeter: View {
    let weightKg: Float
    let minKg: Float
    let scrollKg: Float
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let scale = max(scrollKg * 1.25, weightKg, 1)
            let position = { (kg: Float) -> CGFloat in
                CGFloat(min(max(kg, 0), scale) / scale) * geo.size.width
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(fillColor)
                    .frame(width: position(weightKg))
                tick(at: position(minKg), color: .white)
                tick(at: position(scrollKg), color: Theme.scroll)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.08), value: weightKg)
        .accessibilityElement()
        .accessibilityLabel("Force meter")
    }

    private var fillColor: Color {
        if weightKg >= scrollKg { return Theme.scroll }
        if weightKg >= minKg { return Theme.holding }
        return Theme.warning
    }

    private func tick(at x: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: height + 6)
            .offset(x: x - 1)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
