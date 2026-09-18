import SwiftUI

/// `.ag-bar`: a 10pt `subtle` track with three segments — done in `accent`, pending in the
/// pending color, offered in `accentSoft`. Widths are fractions of the track; the caller applies
/// the prototype's 2% minimum for a non-zero value (`AppModel.barFraction`).
struct ProgressBar: View {
    let done: Double
    let pending: Double
    let offered: Double

    @Environment(\.tokens) private var t

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(t.accent).frame(width: geo.size.width * done)
                Rectangle().fill(t.pendingBar).frame(width: geo.size.width * pending)
                Rectangle().fill(t.accentSoft).frame(width: geo.size.width * offered)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(t.subtle)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
