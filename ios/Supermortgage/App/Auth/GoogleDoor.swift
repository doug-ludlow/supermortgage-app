import FirebaseCore
import Foundation
import GoogleSignIn
import UIKit

struct GoogleTokens: Equatable {
    let idToken: String
    let accessToken: String
}

/// "Continue with Google": the Google Sign-In sheet, ending in the tokens Identity Platform takes.
@MainActor
protocol GoogleSignInDoor: AnyObject {
    func signIn() async throws -> GoogleTokens
}

@MainActor
final class GoogleDoor: GoogleSignInDoor {
    /// `kGIDSignInErrorCodeCanceled`.
    private static let cancelledCode = -5

    func signIn() async throws -> GoogleTokens {
        // The client id comes from GoogleService-Info.plist; the callback scheme from Info.plist.
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AuthFlowError.notConfigured("Google Sign-In isn’t configured")
        }
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        guard AppConfig.urlSchemes.contains(reversed) else {
            throw AuthFlowError.notConfigured("Google Sign-In isn’t configured")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = UIApplication.shared.presenter else {
            throw AuthFlowError.failed("Nothing to present on")
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthFlowError.failed("Google returned no ID token")
            }
            return GoogleTokens(idToken: idToken, accessToken: result.user.accessToken.tokenString)
        } catch let error as AuthFlowError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == kGIDSignInErrorDomain && nsError.code == Self.cancelledCode {
                throw AuthFlowError.cancelled
            }
            throw AuthFlowError.failed(error.oneLine)
        }
    }

    /// The OAuth callback URL.
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
