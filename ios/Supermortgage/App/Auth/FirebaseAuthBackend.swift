import FirebaseAuth
import Foundation

/// Identity Platform through the Firebase Auth SDK. Tokens are minted, refreshed and revoked there.
@MainActor
final class FirebaseAuthBackend: AuthBackend {
    private let auth: Auth
    private var handle: AuthStateDidChangeListenerHandle?

    init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    var currentUser: AuthUser? {
        auth.currentUser.map(AuthUser.init(firebase:))
    }

    func observe(_ onChange: @escaping @MainActor (AuthUser?) -> Void) {
        if let handle { auth.removeStateDidChangeListener(handle) }
        handle = auth.addStateDidChangeListener { _, user in
            let mapped = user.map(AuthUser.init(firebase:))
            Task { @MainActor in onChange(mapped) }
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        let result = try await auth.signIn(with: credential)
        return AuthUser(firebase: result.user)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthUser {
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let result = try await auth.signIn(with: credential)
        return AuthUser(firebase: result.user)
    }

    func signIn(customToken: String) async throws -> AuthUser {
        let result = try await auth.signIn(withCustomToken: customToken)
        return AuthUser(firebase: result.user)
    }

    func idToken(forceRefresh: Bool) async throws -> String {
        guard let user = auth.currentUser else { throw APIError.notSignedIn }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }

    func signOut() throws {
        try auth.signOut()
    }

    func revokeApple(authorizationCode: String) async throws {
        try await auth.revokeToken(withAuthorizationCode: authorizationCode)
    }
}

extension AuthUser {
    init(firebase user: User) {
        self.init(uid: user.uid, email: user.email, providerIDs: user.providerData.map(\.providerID))
    }
}
