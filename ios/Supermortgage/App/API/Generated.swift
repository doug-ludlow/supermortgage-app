// Generated from api/openapi.yaml by api/src/tools/gen-swift.ts. Do not edit; run `npm run gen:swift` in api/.

import Foundation

/// The API's request and response types, named as the components of openapi.yaml.
enum API {
    enum Provider: String, Codable, Equatable, CaseIterable {
        case apple = "apple"
        case google = "google"
        case email = "email"
    }

    enum OnboardingStage: String, Codable, Equatable, CaseIterable {
        case know = "know"
        case setup = "setup"
        case chat = "chat"
    }

    struct User: Codable, Equatable {
        var id: String
        var email: String?
        var emailVerified: Bool
        var displayName: String?
        /// Every door this account has used
        var providers: [Provider]
        /// The door of the current session
        var signedInWith: Provider
        /// ISO 8601 timestamp
        var createdAt: String
    }

    struct Household: Codable, Equatable {
        var id: String
        /// ISO 8601 timestamp
        var createdAt: String
    }

    struct Agent: Codable, Equatable {
        var name: String?
        var namedAt: String?
    }

    struct Onboarding: Codable, Equatable {
        var stage: OnboardingStage
        var completedAt: String?
    }

    struct Me: Codable, Equatable {
        var user: User
        var household: Household
        var agent: Agent
        var onboarding: Onboarding
    }

    struct EmailStartRequest: Codable, Equatable {
        var email: String
    }

    struct EmailVerifyRequest: Codable, Equatable {
        var email: String
        var code: String
    }

    struct EmailVerifyResponse: Codable, Equatable {
        /// Exchange with Auth.auth().signIn(withCustomToken:)
        var customToken: String
    }

    struct AgentPatch: Codable, Equatable {
        var name: String
    }

    struct OnboardingPatch: Codable, Equatable {
        var stage: OnboardingStage
    }

    struct Health: Codable, Equatable {
        var ok: Bool
        var version: String
        var db: String
    }

    struct Problem: Codable, Equatable {
        /// A stable machine-readable code
        var error: String
    }

    struct Empty: Codable, Equatable {
    }
}
