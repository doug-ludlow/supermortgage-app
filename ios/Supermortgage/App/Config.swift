import Foundation

/// Build-time configuration, read from Info.plist keys that the build settings fill in:
/// API_BASE_URL (Debug: the local API; Release: nonprod) and AUTH_EMULATOR_HOST (Debug only).
enum AppConfig {
    static var apiBaseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SMAPIBaseURL") as? String)?.trimmed ?? ""
        return URL(string: raw.isEmpty ? "https://api-nonprod.supermortgage.com" : raw)
            ?? URL(string: "https://api-nonprod.supermortgage.com")!
    }

    /// "host:port" of the Firebase Auth emulator, or nil for the real Identity Platform.
    static var authEmulator: (host: String, port: Int)? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SMAuthEmulatorHost") as? String)?.trimmed ?? ""
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }

    /// The real Firebase configuration, once Doug commits it to Resources/.
    static var hasGoogleServiceInfo: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// The URL schemes the app registered (Google Sign-In's callback must be one of them).
    static var urlSchemes: [String] {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    /// The UI test asks for a signed-out start.
    static var resetAuthAtLaunch: Bool {
        ProcessInfo.processInfo.environment["SM_RESET_AUTH"] == "1"
    }
}
