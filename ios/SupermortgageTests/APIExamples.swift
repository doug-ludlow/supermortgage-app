// Generated from the examples in api/openapi.yaml by api/src/tools/gen-swift.ts. Do not edit.

import Foundation

/// Example JSON for the API's response types, exactly as openapi.yaml documents them.
enum APIExamples {
    /// components.schemas.Me
    static let me: [String] = [
        #"""
        {
          "user": {
            "id": "7b8f5a6e-4c1d-4e2a-9f3b-1a2b3c4d5e6f",
            "email": "doug@example.com",
            "emailVerified": true,
            "displayName": null,
            "providers": [
              "apple"
            ],
            "signedInWith": "apple",
            "createdAt": "2026-09-18T00:00:00.000Z"
          },
          "household": {
            "id": "0c2f6f1e-5d3a-4b7c-8e9f-2b3c4d5e6f70",
            "createdAt": "2026-09-18T00:00:00.000Z"
          },
          "agent": {
            "name": "Hazel",
            "namedAt": "2026-09-18T00:01:00.000Z"
          },
          "onboarding": {
            "stage": "chat",
            "completedAt": "2026-09-18T00:01:00.000Z"
          }
        }
        """#,
        #"""
        {
          "user": {
            "id": "7b8f5a6e-4c1d-4e2a-9f3b-1a2b3c4d5e6f",
            "email": "walk@example.com",
            "emailVerified": true,
            "displayName": null,
            "providers": [
              "email"
            ],
            "signedInWith": "email",
            "createdAt": "2026-09-18T00:00:00.000Z"
          },
          "household": {
            "id": "0c2f6f1e-5d3a-4b7c-8e9f-2b3c4d5e6f70",
            "createdAt": "2026-09-18T00:00:00.000Z"
          },
          "agent": {
            "name": null,
            "namedAt": null
          },
          "onboarding": {
            "stage": "know",
            "completedAt": null
          }
        }
        """#,
    ]
    /// components.schemas.EmailStartRequest
    static let emailStartRequest: [String] = [
        #"""
        {
          "email": "you@example.com"
        }
        """#,
    ]
    /// components.schemas.EmailVerifyRequest
    static let emailVerifyRequest: [String] = [
        #"""
        {
          "email": "you@example.com",
          "code": "482913"
        }
        """#,
    ]
    /// components.schemas.EmailVerifyResponse
    static let emailVerifyResponse: [String] = [
        #"""
        {
          "customToken": "eyJhbGciOiJSUzI1NiJ9.e30.sig"
        }
        """#,
    ]
    /// components.schemas.AgentPatch
    static let agentPatch: [String] = [
        #"""
        {
          "name": "Hazel"
        }
        """#,
    ]
    /// components.schemas.OnboardingPatch
    static let onboardingPatch: [String] = [
        #"""
        {
          "stage": "chat"
        }
        """#,
    ]
    /// components.schemas.Health
    static let health: [String] = [
        #"""
        {
          "ok": true,
          "version": "supermortgage-app-api-00012-abc",
          "db": "ok"
        }
        """#,
    ]
    /// components.schemas.Problem
    static let problem: [String] = [
        #"""
        {
          "error": "code_invalid"
        }
        """#,
    ]
}
