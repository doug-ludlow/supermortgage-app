import Foundation

/// The clock the chat script and every delayed action sleep on. Injected so tests run with no delay.
protocol AppClock {
    func sleep(ms: Int) async throws
}

struct RealClock: AppClock {
    func sleep(ms: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
    }
}

/// Returns at once, so a whole script runs in a test in one go. Like `Task.sleep`, it throws when the
/// task is cancelled — including when the cancellation lands while it is suspended in its yield.
struct ImmediateClock: AppClock {
    func sleep(ms: Int) async throws {
        try Task.checkCancellation()
        await Task.yield()
        try Task.checkCancellation()
    }
}
