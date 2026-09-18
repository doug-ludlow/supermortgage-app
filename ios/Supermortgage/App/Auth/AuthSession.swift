import Foundation
import Observation

/// Who is signed in, as Identity Platform sees it.
struct AuthUser: Equatable {
    let uid: String
    let email: String?
    /// Identity Platform provider ids ("apple.com", "google.com"); empty for the e-mail door, which
    /// signs in with a custom token.
    let providerIDs: [String]

    var usedApple: Bool { providerIDs.contains("apple.com") }
}

enum AuthState: Equatable {
    case signedOut
    case signingIn(AuthProvider)
    case signedIn(AuthUser)
}

/// What a door can end with, besides success.
enum AuthFlowError: Error, Equatable, LocalizedError {
    /// The person dismissed the provider's sheet: the doors re-enable silently.
    case cancelled
    /// The build is missing what the provider needs (GoogleService-Info.plist, the URL scheme).
    case notConfigured(String)
    /// Anything else, already shortened to one line.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Cancelled"
        case .notConfigured(let text), .failed(let text): return text
        }
    }
}

/// Everything the app asks of Identity Platform. `FirebaseAuthBackend` is the real one; the unit
/// tests use an in-memory fake. Every call is made from the main actor.
@MainActor
protocol AuthBackend: AnyObject {
    var currentUser: AuthUser? { get }
    /// Called whenever the signed-in user changes: sign-in, sign-out, a revoked or deleted account.
    func observe(_ onChange: @escaping @MainActor (AuthUser?) -> Void)
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthUser
    func signIn(customToken: String) async throws -> AuthUser
    func idToken(forceRefresh: Bool) async throws -> String
    func signOut() throws
    /// Apple requires the refresh token revoked at deletion, with a fresh authorization code.
    func revokeApple(authorizationCode: String) async throws
}

/// The session: `signedOut`, `signingIn(door)` while a door is continuing, or `signedIn(user)`.
/// Wraps the backend's state listener; the ID token comes from the SDK, which refreshes it.
@MainActor
@Observable
final class AuthSession {
    private(set) var state: AuthState
    /// Fired after every change, on the main actor (AppModel republishes and reacts to sign-outs).
    var onChange: ((AuthState) -> Void)?

    private let backend: AuthBackend

    init(backend: AuthBackend) {
        self.backend = backend
        self.state = backend.currentUser.map { .signedIn($0) } ?? .signedOut
        backend.observe { [weak self] user in
            self?.userChanged(user)
        }
    }

    var user: AuthUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var signingIn: AuthProvider? {
        if case .signingIn(let provider) = state { return provider }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    /// Marks a door as continuing. False while another door is continuing or someone is signed in.
    @discardableResult
    func begin(_ provider: AuthProvider) -> Bool {
        guard case .signedOut = state else { return false }
        transition(to: .signingIn(provider))
        return true
    }

    /// The door was cancelled or failed before a user landed.
    func cancel() {
        if case .signingIn = state { transition(to: .signedOut) }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        let user = try await backend.signInWithApple(idToken: idToken, rawNonce: rawNonce, fullName: fullName)
        transition(to: .signedIn(user))
        return user
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthUser {
        let user = try await backend.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        transition(to: .signedIn(user))
        return user
    }

    func signIn(customToken: String) async throws -> AuthUser {
        let user = try await backend.signIn(customToken: customToken)
        transition(to: .signedIn(user))
        return user
    }

    /// The current ID token; the SDK refreshes it when it is about to expire.
    func idToken() async throws -> String {
        try await backend.idToken(forceRefresh: false)
    }

    func signOut() {
        try? backend.signOut()
        transition(to: .signedOut)
    }

    /// Deletion, in Apple's required order: revoke the Apple token (when there is a fresh code),
    /// delete on the server (which removes the Identity Platform user), then sign out locally.
    func deleteAccount(appleAuthorizationCode: String?, deleteOnServer: () async throws -> Void) async throws {
        if let appleAuthorizationCode {
            try await backend.revokeApple(authorizationCode: appleAuthorizationCode)
        }
        try await deleteOnServer()
        signOut()
    }

    private func userChanged(_ user: AuthUser?) {
        switch (state, user) {
        case (.signingIn, _):
            // The door finishes its own transition once the server bootstrap succeeds.
            break
        case (_, .some(let user)):
            transition(to: .signedIn(user))
        case (_, .none):
            transition(to: .signedOut)
        }
    }

    private func transition(to new: AuthState) {
        guard new != state else { return }
        state = new
        onChange?(new)
    }
}

extension AuthProvider {
    /// The API's `Provider` → the door.
    init(_ provider: API.Provider) {
        switch provider {
        case .apple: self = .apple
        case .google: self = .google
        case .email: self = .email
        }
    }
}

extension Error {
    /// The provider's message shortened to one line, for a toast.
    var oneLine: String {
        let text = (self as? LocalizedError)?.errorDescription ?? (self as NSError).localizedDescription
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Something went wrong" : trimmed
    }
}
