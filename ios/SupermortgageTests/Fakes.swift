import Foundation
@testable import Supermortgage

// In-memory stand-ins for Identity Platform, the API transport and the two provider doors, and a
// model built on them.

@MainActor
final class FakeAuthBackend: AuthBackend {
    var currentUser: AuthUser?
    var signInError: Error?
    var idTokenValue = "id-token"
    private(set) var revoked: [String] = []
    private(set) var signOuts = 0
    private var listener: (@MainActor (AuthUser?) -> Void)?

    static let appleUser = AuthUser(uid: "apple-uid", email: "relay@privaterelay.appleid.com", providerIDs: ["apple.com"])
    static let googleUser = AuthUser(uid: "google-uid", email: "doug@gmail.example", providerIDs: ["google.com"])
    static let emailUser = AuthUser(uid: "email-uid", email: "doug@example.com", providerIDs: [])

    init(user: AuthUser? = nil) {
        currentUser = user
    }

    func observe(_ onChange: @escaping @MainActor (AuthUser?) -> Void) {
        listener = onChange
    }

    private func land(_ user: AuthUser) throws -> AuthUser {
        if let error = signInError {
            signInError = nil
            throw error
        }
        currentUser = user
        listener?(user)
        return user
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthUser {
        try land(Self.appleUser)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthUser {
        try land(Self.googleUser)
    }

    func signIn(customToken: String) async throws -> AuthUser {
        try land(Self.emailUser)
    }

    func idToken(forceRefresh: Bool) async throws -> String {
        guard currentUser != nil else { throw APIError.notSignedIn }
        return idTokenValue
    }

    func signOut() throws {
        signOuts += 1
        currentUser = nil
        listener?(nil)
    }

    func revokeApple(authorizationCode: String) async throws {
        revoked.append(authorizationCode)
    }

    /// The session ended outside the app (a revoked token, a deleted user).
    func externalSignOut() {
        currentUser = nil
        listener?(nil)
    }
}

struct FakeResponse {
    let status: Int
    let body: String

    static func ok(_ body: String) -> FakeResponse { FakeResponse(status: 200, body: body) }
    static func problem(_ status: Int, _ code: String) -> FakeResponse { FakeResponse(status: status, body: "{\"error\":\"\(code)\"}") }
}

/// Scripted answers, in order; when the script runs out every call gets the fresh `Me`.
final class FakeTransport: HTTPTransport {
    var responses: [FakeResponse]
    var failNext: Error?
    private(set) var requests: [URLRequest] = []

    init(responses: [FakeResponse] = []) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error = failNext {
            failNext = nil
            throw error
        }
        let response = responses.isEmpty ? FakeResponse.ok(APIExamples.me[1]) : responses.removeFirst()
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!
        return (Data(response.body.utf8), http)
    }

    /// "METHOD /path" for every request so far.
    var calls: [String] {
        requests.map { "\($0.httpMethod ?? "?") \($0.url?.path ?? "?")" }
    }

    func body(_ index: Int) -> [String: Any] {
        guard requests.indices.contains(index), let data = requests[index].httpBody,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
}

@MainActor
final class FakeGoogle: GoogleSignInDoor {
    var result: Result<GoogleTokens, Error> = .success(GoogleTokens(idToken: "google-id-token", accessToken: "google-access-token"))
    private(set) var calls = 0

    func signIn() async throws -> GoogleTokens {
        calls += 1
        return try result.get()
    }
}

@MainActor
final class FakeAppleReauth: AppleReauthorizer {
    var result: Result<String, Error> = .success("apple-authorization-code")
    private(set) var calls = 0

    func authorizationCode() async throws -> String {
        calls += 1
        return try result.get()
    }
}

/// A fresh `Me` (nothing named, onboarding at `know`) for a given door and address.
func freshMe(provider: String, email: String) -> String {
    let object: [String: Any] = [
        "user": ["id": "7b8f5a6e-4c1d-4e2a-9f3b-1a2b3c4d5e6f", "email": email, "emailVerified": true, "displayName": NSNull(),
                 "providers": [provider], "signedInWith": provider, "createdAt": "2026-09-18T00:00:00.000Z"],
        "household": ["id": "0c2f6f1e-5d3a-4b7c-8e9f-2b3c4d5e6f70", "createdAt": "2026-09-18T00:00:00.000Z"],
        "agent": ["name": NSNull(), "namedAt": NSNull()],
        "onboarding": ["stage": "know", "completedAt": NSNull()],
    ]
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

struct TestWorld {
    let model: AppModel
    let transport: FakeTransport
    let backend: FakeAuthBackend
    let google: FakeGoogle
    let reauth: FakeAppleReauth
}

extension AppModel {
    /// A model on fakes: an immediate clock, no timers, in-memory auth, a scripted API.
    @MainActor
    static func testing(user: AuthUser? = nil, responses: [FakeResponse] = [], clock: AppClock = ImmediateClock()) -> TestWorld {
        let backend = FakeAuthBackend(user: user)
        let session = AuthSession(backend: backend)
        let transport = FakeTransport(responses: responses)
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:8080")!, transport: transport) { [weak session] in
            try await session?.idToken()
        }
        let google = FakeGoogle()
        let reauth = FakeAppleReauth()
        let model = AppModel(clock: clock, runsTimers: false, session: session, api: api, google: google, appleReauth: reauth)
        return TestWorld(model: model, transport: transport, backend: backend, google: google, reauth: reauth)
    }

    /// The shell tests' model: fakes behind the same two arguments they always passed.
    @MainActor
    convenience init(clock: AppClock = ImmediateClock(), runsTimers: Bool = false) {
        let backend = FakeAuthBackend()
        let session = AuthSession(backend: backend)
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:8080")!, transport: FakeTransport()) { [weak session] in
            try await session?.idToken()
        }
        self.init(clock: clock, runsTimers: runsTimers, session: session, api: api, google: FakeGoogle(), appleReauth: FakeAppleReauth())
    }
}
