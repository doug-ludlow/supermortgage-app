import SwiftUI

/// `.intro-point`: one of the prototype's icons at 24pt, a 17pt medium heading and a 15pt `muted` paragraph.
struct IntroPoint: View {
    let icon: IconName
    let title: String
    let text: String

    @Environment(\.tokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, size: 24)
                .foregroundStyle(t.text)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(t.text)
                Text(text)
                    .textStyle(.support)
                    .foregroundStyle(t.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
