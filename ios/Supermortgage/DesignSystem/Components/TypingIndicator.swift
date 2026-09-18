import SwiftUI

/// `.ag-typing`: three 7pt `quiet` dots on the prototype's `agBlink` — a 1.2s cycle from 0.3 to 1 at 40%,
/// back to 0.3 at 80% and held, the second and third dots 0.2s and 0.4s behind.
struct TypingIndicator: View {
    @Environment(\.tokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(t.quiet)
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 1 : TypingIndicator.opacity(at: elapsed, delay: Double(i) * 0.2))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .accessibilityLabel("Typing")
    }

    /// `@keyframes agBlink{0%,80%,100%{opacity:.3}40%{opacity:1}}` over 1.2s, after `delay`.
    static func opacity(at elapsed: TimeInterval, delay: TimeInterval) -> Double {
        let local = elapsed - delay
        if local < 0 { return 0.3 }
        let phase = local.truncatingRemainder(dividingBy: 1.2)
        if phase < 0.48 { return 0.3 + 0.7 * (phase / 0.48) }
        if phase < 0.96 { return 1 - 0.7 * ((phase - 0.48) / 0.48) }
        return 0.3
    }
}
