import SwiftUI

/// "Here’s how I work:" — the mark, the heading, three intro points, the terms line and "Get started".
/// "Get started" switches the same page into its sign-up state (addendum 1): a back button, the mark,
/// "Setup your home assistant", and three doors above the terms line.
struct HowIWorkView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.tokens) private var t

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.signup {
                signupPage
            } else {
                introPage
            }
            if model.signup {
                IconButton(icon: .back, iconSize: 26, chrome: true, label: "Back") { model.signupClose() }
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .accessibilityIdentifier("signup.back")
            }
        }
        .id(model.signup)
    }

    private var introPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
            Text(Copy.knowTitle)
                .textStyle(.onboardingTitle)
                .foregroundStyle(t.text)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 34)
            VStack(alignment: .leading, spacing: 28) {
                IntroPoint(icon: .refresh, title: Copy.introPoints[0].title, text: Copy.introPoints[0].body)
                IntroPoint(icon: .wallet, title: Copy.introPoints[1].title, text: Copy.introPoints[1].body)
                IntroPoint(icon: .minus, title: Copy.introPoints[2].title, text: Copy.introPoints[2].body)
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 32)
            terms
                .padding(.bottom, 16)
            PrimaryButton(Copy.getStarted) { model.signupOpen() }
        }
        .padding(.top, 58)
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .screenEnter(duration: 0.24)
    }

    /// `.ag-signup-on`: the mark, the heading, then the doors and the terms at the bottom.
    private var signupPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
            Text(Copy.signupTitle)
                .textStyle(.onboardingTitle)
                .foregroundStyle(t.text)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 34)
            Spacer(minLength: 32)
            VStack(spacing: 8) {
                DoorButton(Copy.continueWithApple, busyTitle: Copy.continuingWith(.apple), inverted: true,
                           busy: model.authInProgress == .apple, disabled: model.authInProgress != nil) {
                    Image("Apple")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 22, height: 22)
                } action: { model.auth(.apple) }
                DoorButton(Copy.continueWithGoogle, busyTitle: Copy.continuingWith(.google),
                           busy: model.authInProgress == .google, disabled: model.authInProgress != nil) {
                    Image("Google")
                        .resizable()
                        .frame(width: 22, height: 22)
                } action: { model.auth(.google) }
                DoorButton(Copy.logInOrSignUp, busyTitle: Copy.logInOrSignUp,
                           busy: false, disabled: model.authInProgress != nil) {
                    Icon(.mail, size: 22)
                } action: { model.auth(.email) }
            }
            .padding(.bottom, 18)
            .accessibilityElement(children: .contain)
            terms
                .padding(.bottom, 16)
        }
        .padding(.top, 58)
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .screenEnter(duration: 0.24)
    }

    private var mark: some View {
        BrandMark(size: 86)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .padding(.trailing, 6)
            .padding(.top, 10)
            .padding(.bottom, 48)
    }

    /// The two link-styled words do nothing.
    private var terms: some View {
        (Text(Copy.termsPrefix)
            + Text(Copy.termsLink1).foregroundStyle(t.accentText)
            + Text(Copy.termsMiddle)
            + Text(Copy.termsLink2).foregroundStyle(t.accentText)
            + Text(Copy.termsSuffix))
            .textStyle(.meta)
            .foregroundStyle(t.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `.ag-door`: a 52pt `surface` door with a 1pt `cardLine` border and 16pt corners — the icon and a
/// semibold label centered, 10pt apart. `inverted` is the Apple door: `text` fill, `paper` label.
/// While busy it shows a small spinner and its busy title; while disabled it sits at 60% opacity.
struct DoorButton<Leading: View>: View {
    let title: String
    let busyTitle: String
    var inverted: Bool = false
    var busy: Bool = false
    var disabled: Bool = false
    let leading: Leading
    let action: () -> Void

    @Environment(\.tokens) private var t

    init(_ title: String, busyTitle: String, inverted: Bool = false, busy: Bool = false, disabled: Bool = false,
         @ViewBuilder leading: () -> Leading, action: @escaping () -> Void) {
        self.title = title
        self.busyTitle = busyTitle
        self.inverted = inverted
        self.busy = busy
        self.disabled = disabled
        self.leading = leading()
        self.action = action
    }

    private var foreground: Color { inverted ? t.paper : t.text }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    Spinner(size: 18, topColor: foreground)
                } else {
                    leading
                }
                Text(busy ? busyTitle : title)
                    .textStyle(.bodySemibold)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(inverted ? t.text : t.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(inverted ? t.text : t.cardLine, lineWidth: 1))
            .shadow(color: .black.opacity(t.cardShadowOpacity), radius: 12.5, x: 0, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
        .accessibilityIdentifier("button.\(title)")
    }
}
