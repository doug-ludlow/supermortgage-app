import FirebaseAuth
import FirebaseCore
import SwiftUI

@main
struct SupermortgageApp: App {
    @StateObject private var model: AppModel

    init() {
        Self.configureFirebase()
        if AppConfig.resetAuthAtLaunch {
            try? Auth.auth().signOut()
        }
        _model = StateObject(wrappedValue: Self.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.router)
                .onOpenURL { url in
                    _ = GoogleDoor.handle(url)
                }
        }
    }

    /// GoogleService-Info.plist when it is in the bundle (the real project); otherwise options that
    /// only work against the Auth emulator. Debug builds point the SDK at the emulator.
    private static func configureFirebase() {
        guard FirebaseApp.app() == nil else { return }
        if AppConfig.hasGoogleServiceInfo {
            FirebaseApp.configure()
        } else {
            let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000000", gcmSenderID: "000000000000")
            options.projectID = "demo-supermortgage"
            options.apiKey = "demo-api-key"
            options.bundleID = Bundle.main.bundleIdentifier ?? "com.supermortgage.app"
            FirebaseApp.configure(options: options)
        }
        if let emulator = AppConfig.authEmulator {
            Auth.auth().useEmulator(withHost: emulator.host, port: emulator.port)
        }
    }

    /// The real session, API and doors.
    private static func live() -> AppModel {
        let session = AuthSession(backend: FirebaseAuthBackend())
        let api = APIClient(baseURL: AppConfig.apiBaseURL) { [weak session] in
            try await session?.idToken()
        }
        return AppModel(session: session, api: api, google: GoogleDoor(), appleReauth: AppleReauthorization())
    }
}
