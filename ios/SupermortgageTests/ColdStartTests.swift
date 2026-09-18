import XCTest
@testable import Supermortgage

/// Cold start (SIGNUP-FOR-REAL.md §3.4, §6): no user → Welcome; a user with unfinished onboarding →
/// Setup and the intro; a user whose onboarding is complete → Chat with the saved name.
@MainActor
final class ColdStartTests: XCTestCase {
    func testNoUserStaysOnWelcomeUntilTheTimer() async {
        let world = AppModel.testing()
        world.model.welcomeAppeared()
        await world.model.drain()
        XCTAssertEqual(world.model.stage, .welcome, "the 2.6s advance is a timer, off in tests")
        XCTAssertTrue(world.transport.requests.isEmpty)
        XCTAssertNil(world.model.account)
    }

    func testUserWithUnfinishedOnboardingGoesThroughSetupToTheIntro() async {
        let world = AppModel.testing(user: FakeAuthBackend.emailUser, responses: [.ok(APIExamples.me[1])])
        world.model.welcomeAppeared()
        await world.model.drain()
        XCTAssertEqual(world.model.stage, .chat)
        XCTAssertEqual(world.model.name, "")
        XCTAssertEqual(world.model.account, Account(provider: .email, email: "walk@example.com"))
        XCTAssertEqual(world.model.accountLine, "Signed in with e-mail · walk@example.com")
        XCTAssertEqual(world.model.chat.count, 3, "the intro script asked for a name")
        XCTAssertEqual(world.transport.calls.first, "GET /v1/me")
        XCTAssertEqual(world.transport.calls.filter { $0 == "PATCH /v1/me/onboarding" }.count, 2, "setup, then chat")
        let stages = world.transport.requests.indices.filter { world.transport.calls[$0].hasPrefix("PATCH") }.map { world.transport.body($0)["stage"] as? String }
        XCTAssertEqual(stages, ["setup", "chat"])
    }

    func testUserWithCompletedOnboardingGoesStraightToChatWithTheSavedName() async {
        let world = AppModel.testing(user: FakeAuthBackend.appleUser, responses: [.ok(APIExamples.me[0])])
        world.model.welcomeAppeared()
        await world.model.drain()
        XCTAssertEqual(world.model.stage, .chat)
        XCTAssertEqual(world.model.tab, .chat)
        XCTAssertEqual(world.model.name, "Hazel")
        XCTAssertEqual(world.model.displayName, "Hazel")
        XCTAssertEqual(world.model.account, Account(provider: .apple, email: "doug@example.com"))
        XCTAssertEqual(world.model.accountLine, "Signed in with Apple · doug@example.com")
        XCTAssertEqual(world.model.chat.count, 2)
        guard case .text(let greeting)? = world.model.chat.first?.body else { return XCTFail("no greeting") }
        XCTAssertTrue(greeting.contains("Hazel"), greeting)
        XCTAssertEqual(world.model.chat.last?.visibleOptions.map(\.label), ["Sign in to your servicer", "Upload a statement", "Take a photo"])
        XCTAssertEqual(world.transport.calls, ["GET /v1/me"], "nothing to record")
    }

    func testAnAccountTheServerHasNeverSeenIsBootstrapped() async {
        let world = AppModel.testing(user: FakeAuthBackend.googleUser,
                                     responses: [.problem(404, "not_bootstrapped"), .ok(freshMe(provider: "google", email: "doug@gmail.example"))])
        world.model.welcomeAppeared()
        await world.model.drain()
        XCTAssertEqual(Array(world.transport.calls.prefix(2)), ["GET /v1/me", "POST /v1/me/bootstrap"])
        XCTAssertEqual(world.model.account, Account(provider: .google, email: "doug@gmail.example"))
        XCTAssertEqual(world.model.stage, .chat)
    }

    func testASessionThatEndsElsewhereReturnsToWelcome() async {
        let world = AppModel.testing(user: FakeAuthBackend.appleUser, responses: [.ok(APIExamples.me[0])])
        world.model.welcomeAppeared()
        await world.model.drain()
        XCTAssertEqual(world.model.stage, .chat)
        world.backend.externalSignOut()
        XCTAssertEqual(world.model.stage, .welcome)
        XCTAssertNil(world.model.account)
        XCTAssertEqual(world.model.name, "")
    }

    func testAnUnauthorizedAnswerEndsTheSession() async {
        let world = AppModel.testing(user: FakeAuthBackend.appleUser, responses: [.ok(APIExamples.me[0]), .problem(401, "unauthorized")])
        world.model.welcomeAppeared()
        await world.model.drain()
        world.model.nameAgent("Reed")
        await world.model.drain()
        XCTAssertEqual(world.model.stage, .welcome, "a 401 signs out, which resets to Welcome")
        XCTAssertNil(world.backend.currentUser)
    }
}
