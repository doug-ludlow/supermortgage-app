import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// The nonce Sign in with Apple carries to Identity Platform: 32 random bytes, base64url; the
/// request gets its SHA-256 hex, the credential exchange gets the raw value.
enum AppleNonce {
    static func random(_ count: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// What Apple's credential gives the app. `fullName` and `email` arrive on the first authorization
/// only; the e-mail may be a private relay address, which is accepted as is.
struct AppleCredential: Equatable {
    let identityToken: String
    let authorizationCode: String?
    let fullName: PersonNameComponents?
    let email: String?
}

/// A fresh Sign in with Apple authorization at deletion time (Apple's codes live minutes).
@MainActor
protocol AppleReauthorizer: AnyObject {
    func authorizationCode() async throws -> String
}

/// Runs an `ASAuthorizationController` outside the SwiftUI button.
final class AppleReauthorization: NSObject, AppleReauthorizer, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?
    private var controller: ASAuthorizationController?

    @MainActor
    func authorizationCode() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { finish() }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.authorizationCode,
              let code = String(data: data, encoding: .utf8) else {
            continuation?.resume(throwing: AuthFlowError.failed("Apple returned no authorization code"))
            return
        }
        continuation?.resume(returning: code)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { finish() }
        if (error as? ASAuthorizationError)?.code == .canceled {
            continuation?.resume(throwing: AuthFlowError.cancelled)
        } else {
            continuation?.resume(throwing: AuthFlowError.failed(error.oneLine))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.keyWindowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func finish() {
        continuation = nil
        controller = nil
    }
}

extension UIApplication {
    var keyWindowScene: UIWindowScene? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// The view controller a provider's sheet is presented over.
    var presenter: UIViewController? {
        var top = keyWindowScene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
