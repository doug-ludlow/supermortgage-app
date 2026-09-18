import XCTest
@testable import Supermortgage

/// The front door on fakes: the three doors, the e-mail code sheets, sign out, delete, naming.
@MainActor
final class SignupTests: XCTestCase {
    private func world(responses: [FakeResponse] = []) -> TestWorld {
        let world = AppModel.testing(responses: responses)
        world.model.stage = .know
        world.model.signupOpen()
        return world
    }

    func testGetStartedOpensTheSignupStateAndBackCloses() {
        let world = AppModel.testing()
        world.model.stage = .know
        XCTAssertFalse(world.model.signup)
        world.model.signupOpen()
        XCTAssertTrue(world.model.signup)
        XCTAssertEqual(world.model.stage, .know, "the page stays; only its state changes")
        XCTAssertNil(world.model.account)
        world.model.signupClose()
        XCTAssertFalse(world.model.signup)
    }

    func testAppleDoor() async {
        let w = world(responses: [.ok(freshMe(provider: "apple", email: "relay@privaterelay.appleid.com"))])
        let nonce = w.model.beginApple()
        XCTAssertNotNil(nonce)
        XCTAssertEqual(w.model.authInProgress, .apple)
        XCTAssertNil(w.model.beginApple(), "every door is disabled while one is continuing")
        w.model.auth(.google)
        XCTAssertEqual(w.google.calls, 0)

        w.model.appleSucceeded(AppleCredential(identityToken: "apple-id-token", authorizationCode: "code", fullName: nil, email: nil))
        await w.model.drain()
        XCTAssertEqual(w.backend.currentUser, FakeAuthBackend.appleUser)
        XCTAssertEqual(w.transport.calls.first, "POST /v1/me/bootstrap")
        XCTAssertEqual(w.model.account, Account(provider: .apple, email: "relay@privaterelay.appleid.com"))
        XCTAssertEqual(w.model.accountLine, "Signed in with Apple · relay@privaterelay.appleid.com")
        XCTAssertTrue(w.model.log.contains { $0.text == "Signed up with Apple" })
        XCTAssertFalse(w.model.signup)
        XCTAssertNil(w.model.authInProgress)
        XCTAssertEqual(w.model.stage, .chat, "setup ran on the immediate clock")
        XCTAssertEqual(w.model.chat.count, 3, "the intro script ran")
    }

    func testAppleCancelIsSilentAndReenablesTheDoors() {
        let w = world()
        _ = w.model.beginApple()
        w.model.appleFailed(AuthFlowError.cancelled)
        XCTAssertNil(w.model.authInProgress)
        XCTAssertNil(w.model.router.toastText)
        XCTAssertEqual(w.model.session.state, .signedOut)
        XCTAssertNotNil(w.model.beginApple())
    }

    func testAppleFailureToastsOneLine() {
        let w = world()
        _ = w.model.beginApple()
        w.model.appleFailed(NSError(domain: "com.apple.AuthenticationServices.AuthorizationError", code: 1000,
                                    userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed.\nMore detail."]))
        XCTAssertNil(w.model.authInProgress)
        XCTAssertEqual(w.model.router.toastText, "The operation couldn’t be completed.")
    }

    func testGoogleDoor() async {
        let w = world(responses: [.ok(freshMe(provider: "google", email: "doug@gmail.example"))])
        w.model.auth(.google)
        XCTAssertEqual(w.model.authInProgress, .google)
        await w.model.drain()
        XCTAssertEqual(w.google.calls, 1)
        XCTAssertEqual(w.backend.currentUser, FakeAuthBackend.googleUser)
        XCTAssertEqual(w.model.account, Account(provider: .google, email: "doug@gmail.example"))
        XCTAssertEqual(w.model.accountLine, "Signed in with Google · doug@gmail.example")
        XCTAssertTrue(w.model.log.contains { $0.text == "Signed up with Google" })
        XCTAssertEqual(w.model.stage, .chat)
    }

    func testGoogleCancelAndFailure() async {
        let w = world()
        w.google.result = .failure(AuthFlowError.cancelled)
        w.model.auth(.google)
        await w.model.drain()
        XCTAssertNil(w.model.authInProgress)
        XCTAssertNil(w.model.router.toastText)
        XCTAssertNil(w.backend.currentUser)

        w.google.result = .failure(AuthFlowError.notConfigured("Google Sign-In isn’t configured"))
        w.model.auth(.google)
        await w.model.drain()
        XCTAssertNil(w.model.authInProgress)
        XCTAssertEqual(w.model.router.toastText, "Google Sign-In isn’t configured")
        XCTAssertTrue(w.transport.requests.isEmpty)
    }

    func testADoorThatCannotBootstrapSignsOutAgain() async {
        let w = world(responses: [.problem(500, "internal")])
        w.model.auth(.google)
        await w.model.drain()
        XCTAssertNil(w.backend.currentUser, "no half session remains")
        XCTAssertEqual(w.model.session.state, .signedOut)
        XCTAssertNil(w.model.authInProgress)
        XCTAssertEqual(w.model.router.toastText, "internal (500)")
        XCTAssertNil(w.model.account)
    }

    func testEmailDoor() async {
        let w = world(responses: [
            .ok("{}"),                                                   // start
            .problem(400, "code_invalid"),                               // wrong code
            .problem(410, "code_expired_or_burned"),                     // burned
            .ok("{}"),                                                   // send a new code
            .ok(APIExamples.emailVerifyResponse[0]),                     // the right code
            .ok(freshMe(provider: "email", email: "doug@example.com")),  // bootstrap
        ])
        w.model.auth(.email)
        XCTAssertEqual(w.model.router.sheet, .login)
        XCTAssertNil(w.model.account)

        w.model.authEmail("   ")
        XCTAssertEqual(w.model.router.toastText, "Enter your email")
        XCTAssertTrue(w.transport.requests.isEmpty)

        w.model.authEmail("  doug@example.com ")
        await w.model.drain()
        XCTAssertEqual(w.transport.calls, ["POST /v1/auth/email/start"])
        XCTAssertEqual(w.transport.body(0)["email"] as? String, "doug@example.com")
        XCTAssertEqual(w.model.pendingEmail, "doug@example.com")
        XCTAssertEqual(w.model.router.sheet, .checkEmail)

        w.model.authCode("123")
        XCTAssertEqual(w.model.router.toastText, "Six digits")
        XCTAssertEqual(w.transport.calls.count, 1, "no request for fewer than six digits")

        w.model.authCode("000000")
        await w.model.drain()
        XCTAssertEqual(w.model.router.toastText, "That code didn’t work")
        XCTAssertEqual(w.model.router.sheet, .checkEmail, "the sheet stays")
        XCTAssertNil(w.model.account)

        w.model.authCode("000000")
        await w.model.drain()
        XCTAssertEqual(w.model.router.toastText, "Ask for a new code")
        XCTAssertEqual(w.model.router.sheet, .checkEmail)

        w.model.resendCode()
        await w.model.drain()
        XCTAssertEqual(w.model.router.toastText, "Code sent again")
        XCTAssertEqual(w.transport.calls.last, "POST /v1/auth/email/start")

        w.model.authCode("482913")
        await w.model.drain()
        XCTAssertEqual(w.transport.body(4)["code"] as? String, "482913")
        XCTAssertTrue(w.transport.calls.contains("POST /v1/me/bootstrap"))
        XCTAssertNil(w.model.router.sheet)
        XCTAssertEqual(w.backend.currentUser, FakeAuthBackend.emailUser)
        XCTAssertEqual(w.model.account, Account(provider: .email, email: "doug@example.com"))
        XCTAssertEqual(w.model.accountLine, "Signed in with e-mail · doug@example.com")
        XCTAssertTrue(w.model.log.contains { $0.text == "Signed up with e-mail · doug@example.com" })
        XCTAssertFalse(w.model.signup)
        XCTAssertEqual(w.model.stage, .chat)
    }

    func testNotSignedInLine() {
        XCTAssertEqual(AppModel.testing().model.accountLine, "Not signed in")
    }

    func testNamingIsRecordedAndRevertsWhenTheServerRefuses() async {
        let w = world(responses: [.ok(freshMe(provider: "google", email: "doug@gmail.example"))])
        w.model.auth(.google)
        await w.model.drain()
        w.model.nameAgent("Hazel")
        await w.model.drain()
        XCTAssertEqual(w.model.name, "Hazel")
        let patch = w.transport.calls.firstIndex(of: "PATCH /v1/me/agent")
        XCTAssertNotNil(patch)
        XCTAssertEqual(w.transport.body(patch ?? -1)["name"] as? String, "Hazel")

        w.transport.failNext = URLError(.timedOut)
        w.model.saveName("Reed")
        await w.model.drain()
        XCTAssertEqual(w.model.name, "Hazel", "reverted")
        XCTAssertNotNil(w.model.router.toastText)
    }

    func testSignOutResetsEverythingAndToasts() async {
        let w = world(responses: [.ok(freshMe(provider: "apple", email: "relay@privaterelay.appleid.com"))])
        _ = w.model.beginApple()
        w.model.appleSucceeded(AppleCredential(identityToken: "t", authorizationCode: nil, fullName: nil, email: nil))
        await w.model.drain()
        w.model.nameAgent("Hazel")
        w.model.approvePMI()
        w.model.signOut()
        XCTAssertEqual(w.model.stage, .welcome)
        XCTAssertNil(w.model.account)
        XCTAssertNil(w.backend.currentUser)
        XCTAssertEqual(w.model.session.state, .signedOut)
        XCTAssertFalse(w.model.signup)
        XCTAssertNil(w.model.authInProgress)
        XCTAssertEqual(w.model.name, "")
        XCTAssertEqual(w.model.pmi, .ready)
        XCTAssertEqual(w.model.chat.count, 0)
        XCTAssertEqual(w.model.router.toastText, "Signed out")
    }

    func testDeleteAsksFirstThenRevokesAppleDeletesOnTheServerAndReturnsToWelcome() async {
        let w = world(responses: [.ok(freshMe(provider: "apple", email: "relay@privaterelay.appleid.com"))])
        _ = w.model.beginApple()
        w.model.appleSucceeded(AppleCredential(identityToken: "t", authorizationCode: nil, fullName: nil, email: nil))
        await w.model.drain()
        w.model.deleteData()
        XCTAssertEqual(w.model.router.sheet, .confirmDelete)
        XCTAssertEqual(w.model.stage, .chat, "nothing happens until it is confirmed")

        w.transport.responses = [FakeResponse(status: 204, body: "")]
        w.model.confirmDelete()
        await w.model.drain()
        XCTAssertEqual(w.reauth.calls, 1, "a fresh Apple authorization at deletion time")
        XCTAssertEqual(w.backend.revoked, ["apple-authorization-code"])
        XCTAssertEqual(w.transport.calls.last, "DELETE /v1/me")
        XCTAssertNil(w.backend.currentUser)
        XCTAssertEqual(w.model.stage, .welcome)
        XCTAssertNil(w.model.account)
        XCTAssertNil(w.model.router.sheet)
    }

    func testDeleteWithoutAppleSkipsTheReauthorization() async {
        let w = world(responses: [.ok(freshMe(provider: "google", email: "doug@gmail.example"))])
        w.model.auth(.google)
        await w.model.drain()
        w.model.deleteData()
        w.transport.responses = [FakeResponse(status: 204, body: "")]
        w.model.confirmDelete()
        await w.model.drain()
        XCTAssertEqual(w.reauth.calls, 0)
        XCTAssertEqual(w.backend.revoked, [])
        XCTAssertEqual(w.transport.calls.last, "DELETE /v1/me")
        XCTAssertEqual(w.model.stage, .welcome)
    }

    func testCancellingTheAppleReauthorizationKeepsEverything() async {
        let w = world(responses: [.ok(freshMe(provider: "apple", email: "relay@privaterelay.appleid.com"))])
        _ = w.model.beginApple()
        w.model.appleSucceeded(AppleCredential(identityToken: "t", authorizationCode: nil, fullName: nil, email: nil))
        await w.model.drain()
        w.reauth.result = .failure(AuthFlowError.cancelled)
        let calls = w.transport.calls.count
        w.model.deleteData()
        w.model.confirmDelete()
        await w.model.drain()
        XCTAssertEqual(w.model.stage, .chat)
        XCTAssertNotNil(w.backend.currentUser)
        XCTAssertEqual(w.transport.calls.count, calls, "no DELETE")
        XCTAssertNil(w.model.router.toastText)
    }
}
