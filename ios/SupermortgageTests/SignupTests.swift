import XCTest
@testable import Supermortgage

/// Addendum 1: the sign-up step between "Here’s how I work" and setup.
@MainActor
final class SignupTests: XCTestCase {
    private func makeModel() -> AppModel {
        let model = AppModel(clock: ImmediateClock(), runsTimers: false)
        model.stage = .know
        return model
    }

    func testGetStartedOpensTheSignupStateAndBackCloses() {
        let model = makeModel()
        XCTAssertFalse(model.signup)
        model.signupOpen()
        XCTAssertTrue(model.signup)
        XCTAssertEqual(model.stage, .know, "the page stays; only its state changes")
        XCTAssertNil(model.account)
        model.signupClose()
        XCTAssertFalse(model.signup)
        XCTAssertEqual(model.stage, .know)
    }

    func testAppleDoor() async {
        let model = makeModel()
        model.signupOpen()
        model.auth(.apple)
        XCTAssertEqual(model.authInProgress, .apple)
        XCTAssertEqual(model.account, Account(provider: .apple))
        XCTAssertEqual(model.log.first?.text, "Signed up with Apple")
        XCTAssertTrue(model.signup, "the doors stay up while Continuing with Apple…")
        model.auth(.google)
        XCTAssertEqual(model.account, Account(provider: .apple), "every door is disabled while one is continuing")
        await model.drain()
        XCTAssertFalse(model.signup)
        XCTAssertNil(model.authInProgress)
        XCTAssertEqual(model.stage, .chat)
        XCTAssertEqual(model.accountLine, "Signed in with Apple")
        XCTAssertEqual(model.chat.count, 3, "the intro script ran")
    }

    func testGoogleDoor() async {
        let model = makeModel()
        model.signupOpen()
        model.auth(.google)
        XCTAssertEqual(model.account, Account(provider: .google))
        XCTAssertEqual(model.log.first?.text, "Signed up with Google")
        await model.drain()
        XCTAssertFalse(model.signup)
        XCTAssertEqual(model.stage, .chat)
        XCTAssertEqual(model.accountLine, "Signed in with Google")
    }

    func testEmailDoor() async {
        let model = makeModel()
        model.signupOpen()
        model.auth(.email)
        XCTAssertEqual(model.router.sheet, .login)
        XCTAssertNil(model.account)

        model.authEmail("   ")
        XCTAssertEqual(model.router.toastText, "Enter your email")
        XCTAssertEqual(model.router.sheet, .login)

        model.authEmail("  doug@example.com ")
        XCTAssertEqual(model.pendingEmail, "doug@example.com")
        XCTAssertEqual(model.router.sheet, .checkEmail)

        model.authCode("123")
        XCTAssertEqual(model.router.toastText, "Six digits")
        XCTAssertEqual(model.router.sheet, .checkEmail)
        XCTAssertNil(model.account)

        model.resendCode()
        XCTAssertEqual(model.router.toastText, "Code sent again")

        model.authCode("123456")
        XCTAssertNil(model.router.sheet)
        XCTAssertEqual(model.account, Account(provider: .email, email: "doug@example.com"))
        XCTAssertEqual(model.log.first?.text, "Signed up with e-mail · doug@example.com")
        XCTAssertEqual(model.accountLine, "Signed in with e-mail · doug@example.com")
        await model.drain()
        XCTAssertFalse(model.signup)
        XCTAssertEqual(model.stage, .chat)
    }

    func testNotSignedInLine() {
        let model = makeModel()
        XCTAssertEqual(model.accountLine, "Not signed in")
    }

    func testSignOutResetsEverythingAndToasts() async {
        let model = makeModel()
        model.signupOpen()
        model.auth(.apple)
        await model.drain()
        model.name = "Hazel"
        model.approvePMI()
        model.signOut()
        XCTAssertEqual(model.stage, .welcome)
        XCTAssertNil(model.account)
        XCTAssertFalse(model.signup)
        XCTAssertNil(model.authInProgress)
        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.pmi, .ready)
        XCTAssertEqual(model.chat.count, 0)
        XCTAssertEqual(model.router.toastText, "Signed out")
    }

    func testDeleteAlsoResetsTheAccount() async {
        let model = makeModel()
        model.signupOpen()
        model.auth(.google)
        await model.drain()
        model.deleteData()
        XCTAssertNil(model.account)
        XCTAssertFalse(model.signup)
        XCTAssertEqual(model.stage, .welcome)
    }
}
