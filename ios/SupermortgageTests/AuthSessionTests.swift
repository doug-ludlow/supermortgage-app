import XCTest
@testable import Supermortgage

/// The session's state machine, on a fake Identity Platform.
@MainActor
final class AuthSessionTests: XCTestCase {
    func testStartsFromTheBackendsUser() {
        XCTAssertEqual(AuthSession(backend: FakeAuthBackend()).state, .signedOut)
        let signedIn = AuthSession(backend: FakeAuthBackend(user: FakeAuthBackend.googleUser))
        XCTAssertEqual(signedIn.state, .signedIn(FakeAuthBackend.googleUser))
        XCTAssertEqual(signedIn.user?.uid, "google-uid")
        XCTAssertTrue(signedIn.isSignedIn)
    }

    func testADoorContinuesThenLands() async throws {
        let backend = FakeAuthBackend()
        let session = AuthSession(backend: backend)
        var changes: [AuthState] = []
        session.onChange = { changes.append($0) }

        XCTAssertTrue(session.begin(.google))
        XCTAssertEqual(session.state, .signingIn(.google))
        XCTAssertEqual(session.signingIn, .google)
        XCTAssertFalse(session.begin(.apple), "one door at a time")
        XCTAssertNil(session.user)

        let user = try await session.signInWithGoogle(idToken: "id", accessToken: "access")
        XCTAssertEqual(user, FakeAuthBackend.googleUser)
        XCTAssertEqual(session.state, .signedIn(FakeAuthBackend.googleUser))
        XCTAssertFalse(session.begin(.email), "no door while signed in")
        let token = try await session.idToken()
        XCTAssertEqual(token, "id-token")

        session.signOut()
        XCTAssertEqual(session.state, .signedOut)
        XCTAssertEqual(backend.signOuts, 1)
        XCTAssertEqual(changes, [.signingIn(.google), .signedIn(FakeAuthBackend.googleUser), .signedOut])
    }

    func testCancelReturnsToSignedOut() {
        let session = AuthSession(backend: FakeAuthBackend())
        session.begin(.apple)
        session.cancel()
        XCTAssertEqual(session.state, .signedOut)
        session.cancel()
        XCTAssertEqual(session.state, .signedOut)
    }

    func testTheListenerEndsTheSessionFromOutside() {
        let backend = FakeAuthBackend(user: FakeAuthBackend.appleUser)
        let session = AuthSession(backend: backend)
        var changes: [AuthState] = []
        session.onChange = { changes.append($0) }
        backend.externalSignOut()
        XCTAssertEqual(session.state, .signedOut)
        XCTAssertEqual(changes, [.signedOut])
    }

    func testTheListenerIsIgnoredWhileADoorIsContinuing() async throws {
        let backend = FakeAuthBackend()
        let session = AuthSession(backend: backend)
        session.begin(.email)
        _ = try await backend.signIn(customToken: "token") // fires the listener before the door finishes
        XCTAssertEqual(session.state, .signingIn(.email), "the door lands the session itself")
        _ = try await session.signIn(customToken: "token")
        XCTAssertEqual(session.state, .signedIn(FakeAuthBackend.emailUser))
    }

    func testAFailedDoorLeavesNoSession() async {
        let backend = FakeAuthBackend()
        backend.signInError = AuthFlowError.failed("Network down")
        let session = AuthSession(backend: backend)
        session.begin(.google)
        do {
            _ = try await session.signInWithGoogle(idToken: "id", accessToken: "access")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AuthFlowError, .failed("Network down"))
        }
        XCTAssertEqual(session.state, .signingIn(.google), "the caller decides: cancel")
        session.cancel()
        XCTAssertEqual(session.state, .signedOut)
    }

    func testDeleteRevokesThenDeletesOnTheServerThenSignsOut() async throws {
        let backend = FakeAuthBackend(user: FakeAuthBackend.appleUser)
        let session = AuthSession(backend: backend)
        var order: [String] = []
        try await session.deleteAccount(appleAuthorizationCode: "fresh-code") {
            order.append("server")
            XCTAssertEqual(backend.revoked, ["fresh-code"], "revoked before the server delete")
        }
        order.append(session.state == .signedOut ? "signed-out" : "still-in")
        XCTAssertEqual(order, ["server", "signed-out"])
        XCTAssertEqual(backend.signOuts, 1)

        let google = AuthSession(backend: FakeAuthBackend(user: FakeAuthBackend.googleUser))
        try await google.deleteAccount(appleAuthorizationCode: nil) {}
        XCTAssertEqual(google.state, .signedOut)
    }

    func testProviderMapping() {
        XCTAssertEqual(AuthProvider(API.Provider.apple), .apple)
        XCTAssertEqual(AuthProvider(API.Provider.google), .google)
        XCTAssertEqual(AuthProvider(API.Provider.email), .email)
        XCTAssertTrue(FakeAuthBackend.appleUser.usedApple)
        XCTAssertFalse(FakeAuthBackend.emailUser.usedApple)
    }

    func testAppleNonce() {
        let raw = AppleNonce.random()
        XCTAssertEqual(raw.count, 43, "32 bytes, base64url without padding")
        XCTAssertNil(raw.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(raw, AppleNonce.random())
        XCTAssertEqual(AppleNonce.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testOneLineErrors() {
        XCTAssertEqual(AuthFlowError.failed("First line\nSecond line").oneLine, "First line")
        XCTAssertEqual(AuthFlowError.notConfigured("Google Sign-In isn’t configured").oneLine, "Google Sign-In isn’t configured")
        XCTAssertEqual(APIError.status(400, code: "code_invalid").oneLine, "code_invalid (400)")
        XCTAssertEqual(APIError.unauthorized.oneLine, "Your session ended")
        XCTAssertEqual(NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "  \n"]).oneLine, "Something went wrong")
    }
}
