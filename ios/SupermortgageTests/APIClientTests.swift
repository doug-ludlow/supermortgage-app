import XCTest
@testable import Supermortgage

/// The client against the examples openapi.yaml documents, on a scripted transport.
@MainActor
final class APIClientTests: XCTestCase {
    private func client(_ responses: [FakeResponse], token: String? = "id-token") -> (APIClient, FakeTransport) {
        let transport = FakeTransport(responses: responses)
        let client = APIClient(baseURL: URL(string: "http://127.0.0.1:8080")!, transport: transport) { token }
        return (client, transport)
    }

    func testDecodesTheDocumentedMe() async throws {
        let (client, transport) = client([.ok(APIExamples.me[0])])
        let me = try await client.me()
        XCTAssertEqual(me.user.email, "doug@example.com")
        XCTAssertEqual(me.user.providers, [.apple])
        XCTAssertEqual(me.user.signedInWith, .apple)
        XCTAssertTrue(me.user.emailVerified)
        XCTAssertNil(me.user.displayName)
        XCTAssertEqual(me.agent.name, "Hazel")
        XCTAssertEqual(me.agent.namedAt, "2026-09-18T00:01:00.000Z")
        XCTAssertEqual(me.onboarding.stage, .chat)
        XCTAssertEqual(me.onboarding.completedAt, "2026-09-18T00:01:00.000Z")
        XCTAssertEqual(me.household.id, "0c2f6f1e-5d3a-4b7c-8e9f-2b3c4d5e6f70")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer id-token")
        XCTAssertNil(request.httpBody)
    }

    func testDecodesTheFreshMe() async throws {
        let (client, _) = client([.ok(APIExamples.me[1])])
        let me = try await client.bootstrap()
        XCTAssertEqual(me.user.email, "walk@example.com")
        XCTAssertEqual(me.user.signedInWith, .email)
        XCTAssertNil(me.agent.name)
        XCTAssertNil(me.agent.namedAt)
        XCTAssertEqual(me.onboarding.stage, .know)
        XCTAssertNil(me.onboarding.completedAt)
    }

    func testEmailStartSendsTheBodyWithoutABearer() async throws {
        let (client, transport) = client([.ok("{}")], token: nil)
        try await client.emailStart(email: "you@example.com")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.calls, ["POST /v1/auth/email/start"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(transport.body(0)["email"] as? String, "you@example.com")
    }

    func testVerifyReturnsTheCustomTokenAndErrorsCarryTheCode() async throws {
        let (client, transport) = client([
            .ok(APIExamples.emailVerifyResponse[0]),
            .problem(400, "code_invalid"),
            .problem(410, "code_expired_or_burned"),
        ], token: nil)
        let verified = try await client.emailVerify(email: "you@example.com", code: "482913")
        XCTAssertEqual(verified.customToken, "eyJhbGciOiJSUzI1NiJ9.e30.sig")
        XCTAssertEqual(transport.body(0)["code"] as? String, "482913")
        do {
            _ = try await client.emailVerify(email: "you@example.com", code: "000000")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .status(400, code: "code_invalid"))
        }
        do {
            _ = try await client.emailVerify(email: "you@example.com", code: "000000")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .status(410, code: "code_expired_or_burned"))
        }
    }

    func testUnauthorizedEndsTheSession() async {
        let (client, _) = client([.problem(401, "unauthorized")])
        var ended = 0
        client.onUnauthorized = { ended += 1 }
        do {
            _ = try await client.me()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertEqual(ended, 1)
    }

    func testPatchesCarryTheirBodies() async throws {
        let (client, transport) = client([.ok(APIExamples.me[0]), .ok(APIExamples.me[0])])
        _ = try await client.patchAgent(name: "Hazel")
        _ = try await client.patchOnboarding(stage: .chat)
        XCTAssertEqual(transport.calls, ["PATCH /v1/me/agent", "PATCH /v1/me/onboarding"])
        XCTAssertEqual(transport.body(0)["name"] as? String, "Hazel")
        XCTAssertEqual(transport.body(1)["stage"] as? String, "chat")
    }

    func testDeleteAcceptsAnEmptyAnswer() async throws {
        let (client, transport) = client([FakeResponse(status: 204, body: "")])
        try await client.deleteMe()
        XCTAssertEqual(transport.calls, ["DELETE /v1/me"])
    }

    func testNoTokenMeansNoRequest() async {
        let (client, transport) = client([], token: nil)
        do {
            _ = try await client.me()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .notSignedIn)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTransportFailuresBecomeOneLine() async {
        let (client, transport) = client([])
        transport.failNext = URLError(.notConnectedToInternet)
        do {
            _ = try await client.me()
            XCTFail("should throw")
        } catch {
            guard case APIError.transport(let text)? = error as? APIError else { return XCTFail("\(error)") }
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("\n"))
        }
    }

    func testTheDocumentedHealthAndProblemDecode() throws {
        let health = try JSONDecoder().decode(API.Health.self, from: Data(APIExamples.health[0].utf8))
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.db, "ok")
        let problem = try JSONDecoder().decode(API.Problem.self, from: Data(APIExamples.problem[0].utf8))
        XCTAssertEqual(problem.error, "code_invalid")
    }
}
