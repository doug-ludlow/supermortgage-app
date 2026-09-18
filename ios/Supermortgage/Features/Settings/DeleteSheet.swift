import SwiftUI

/// Settings → Your data → Delete: the confirmation before the account, the agent and everything it
/// knows are deleted (SIGNUP-FOR-REAL.md §3.5; the HTML only toasts here).
struct DeleteSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.tokens) private var t

    var body: some View {
        SheetContainer(Copy.deleteTitle) {
            IntroText(Copy.deleteIntro, color: t.muted)
            ActionStack {
                PrimaryButton(Copy.deleteConfirm) { model.confirmDelete() }
                SecondaryButton(Copy.deleteKeep) { router.dismiss() }
            }
        }
    }
}
