import SwiftUI

/// "Log in or sign up" — one e-mail field, the fine print, Continue.
struct LoginSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.tokens) private var t
    @State private var email = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetContainer(Copy.logInOrSignUp) {
            FieldBox(label: Copy.emailLabel) {
                TextField(Copy.emailPlaceholder, text: $email)
                    .textStyle(.body)
                    .foregroundStyle(t.text)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit { model.authEmail(email) }
                    .accessibilityIdentifier("signup.email")
            }
            FineText(Copy.codeFine)
                .padding(.top, -6)
            ActionStack {
                PrimaryButton("Continue") { model.authEmail(email) }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }
}

/// "Check your email" — the six-digit code field, Continue, and "Send a new code".
struct CheckEmailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.tokens) private var t
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetContainer(Copy.checkYourEmail) {
            (Text("Enter the six-digit code we sent to ")
                + Text(model.pendingEmail ?? "").fontWeight(.bold)
                + Text(". It expires in 10 minutes."))
                .textStyle(.support)
                .foregroundStyle(t.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
            FieldBox(label: Copy.codeLabel) {
                TextField(Copy.codePlaceholder, text: $code)
                    .textStyle(.body)
                    .foregroundStyle(t.text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .onChange(of: code) {
                        let digits = String(code.filter { $0.isNumber }.prefix(6))
                        if digits != code { code = digits }
                    }
                    .accessibilityIdentifier("signup.code")
            }
            ActionStack {
                PrimaryButton("Continue") { model.authCode(code) }
                LinkButton(Copy.sendNewCode) { model.resendCode() }
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }
}
