import Foundation

/// One HTTP exchange. `URLSessionTransport` is the real one; tests script responses.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Not an HTTP response") }
        return (data, http)
    }
}

enum APIError: Error, Equatable, LocalizedError {
    case notSignedIn
    case unauthorized
    /// A non-2xx answer with the API's stable error code when it sent one.
    case status(Int, code: String?)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .unauthorized: return "Your session ended"
        case .status(let status, let code): return code.map { "\($0) (\(status))" } ?? "The server answered \(status)"
        case .transport(let text): return text
        case .decoding(let text): return "Unexpected answer: \(text)"
        }
    }
}

/// The API (api/openapi.yaml): the base URL from the build configuration, the Identity Platform ID
/// token as Bearer on every call, the generated types. A 401 ends the session.
@MainActor
final class APIClient {
    let baseURL: URL
    /// Called on a 401 before the error is thrown.
    var onUnauthorized: (() -> Void)?

    private let transport: HTTPTransport
    private let token: () async throws -> String?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, transport: HTTPTransport = URLSessionTransport(), token: @escaping () async throws -> String?) {
        self.baseURL = baseURL
        self.transport = transport
        self.token = token
    }

    // MARK: The routes

    func emailStart(email: String) async throws {
        let _: API.Empty = try await send("POST", "/v1/auth/email/start", body: API.EmailStartRequest(email: email), authenticated: false)
    }

    func emailVerify(email: String, code: String) async throws -> API.EmailVerifyResponse {
        try await send("POST", "/v1/auth/email/verify", body: API.EmailVerifyRequest(email: email, code: code), authenticated: false)
    }

    func bootstrap() async throws -> API.Me {
        try await send("POST", "/v1/me/bootstrap")
    }

    func me() async throws -> API.Me {
        try await send("GET", "/v1/me")
    }

    func patchAgent(name: String) async throws -> API.Me {
        try await send("PATCH", "/v1/me/agent", body: API.AgentPatch(name: name))
    }

    func patchOnboarding(stage: API.OnboardingStage) async throws -> API.Me {
        try await send("PATCH", "/v1/me/onboarding", body: API.OnboardingPatch(stage: stage))
    }

    func deleteMe() async throws {
        let _: API.Empty = try await send("DELETE", "/v1/me")
    }

    // MARK: Plumbing

    private func send<Out: Decodable>(_ method: String, _ path: String, authenticated: Bool = true) async throws -> Out {
        try await perform(method, path, body: nil, authenticated: authenticated)
    }

    private func send<In: Encodable, Out: Decodable>(_ method: String, _ path: String, body: In, authenticated: Bool = true) async throws -> Out {
        try await perform(method, path, body: try encoder.encode(body), authenticated: authenticated)
    }

    private func perform<Out: Decodable>(_ method: String, _ path: String, body: Data?, authenticated: Bool) async throws -> Out {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw APIError.transport("Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let idToken = try await token(), !idToken.isEmpty else { throw APIError.notSignedIn }
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.oneLine)
        }
        switch response.statusCode {
        case 200 ..< 300:
            if data.isEmpty, let empty = API.Empty() as? Out { return empty }
            do {
                return try decoder.decode(Out.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        case 401:
            onUnauthorized?()
            throw APIError.unauthorized
        default:
            let code = (try? decoder.decode(API.Problem.self, from: data))?.error
            throw APIError.status(response.statusCode, code: code)
        }
    }
}
