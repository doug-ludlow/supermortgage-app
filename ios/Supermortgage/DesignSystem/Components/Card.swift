import SwiftUI

/// `.card`: `surface` on a 1pt `cardLine` border, 28pt corners, 18pt padding, the card shadow.
struct Card<Content: View>: View {
    let content: Content

    @Environment(\.tokens) private var t

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(t.cardLine, lineWidth: 1))
        .shadow(color: .black.opacity(t.cardShadowOpacity), radius: 12.5, x: 0, y: 7)
    }
}

/// `.ag-preview` / `.ag-approve`: the bordered box inside an artifact or approval sheet — 20pt corners, 16pt padding.
struct PreviewBox<Content: View>: View {
    let content: Content

    @Environment(\.tokens) private var t

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(t.cardLine, lineWidth: 1))
        .padding(.top, 6)
    }
}

extension View {
    /// A 1pt `line` hairline along the bottom edge (`border-bottom:1px solid var(--line)`).
    func bottomLine(_ color: Color) -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(color).frame(height: 1)
        }
    }

    /// A 1pt hairline along the top edge.
    func topLine(_ color: Color) -> some View {
        overlay(alignment: .top) {
            Rectangle().fill(color).frame(height: 1)
        }
    }

    /// `@keyframes enter`: from 75% opacity and 3pt down — 0.16s for a tab screen, 0.24s for an
    /// onboarding screen. Off under Reduce Motion.
    func screenEnter(duration: Double = 0.16) -> some View {
        modifier(ScreenEnter(duration: duration))
    }
}

private struct ScreenEnter: ViewModifier {
    let duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    func body(content: Content) -> some View {
        content
            .opacity(entered || reduceMotion ? 1 : 0.75)
            .offset(y: entered || reduceMotion ? 0 : 3)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { entered = true }
            }
    }
}
