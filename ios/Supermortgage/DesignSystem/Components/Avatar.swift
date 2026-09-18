import SwiftUI

/// The agent's face: `AVATAR`, exported to the asset catalog as `Avatar.svg` (vector data preserved),
/// at 66×66 with a soft drop shadow.
struct AvatarMark: View {
    var body: some View {
        Image("Avatar")
            .resizable()
            .frame(width: 66, height: 66)
            .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 6)
            .accessibilityHidden(true)
    }
}

/// The avatar with its working ring: a thin `accentSoft` ring with an `accent` arc turning once per 1.5s.
struct AvatarView: View {
    let working: Bool

    @Environment(\.tokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            AvatarMark()
            if working {
                ZStack {
                    Circle().stroke(t.accentSoft, lineWidth: 2)
                    Circle().trim(from: 0.625, to: 0.875).stroke(t.accent, lineWidth: 2)
                }
                .frame(width: 74, height: 74)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false), value: spinning)
                .onAppear { spinning = true }
                .onDisappear { spinning = false }
            }
        }
        .frame(width: 76, height: 76)
    }
}

/// The brand mark "s" in Georgia Italic, `accent`.
struct BrandMark: View {
    var size: CGFloat = 86

    @Environment(\.tokens) private var t

    var body: some View {
        Text("s")
            .font(.georgiaItalic(size))
            .foregroundStyle(t.accent)
            .accessibilityHidden(true)
    }
}
