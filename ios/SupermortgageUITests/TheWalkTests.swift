import XCTest

/// The walk (§8): one test, in the order of the HTML smoke tests.
final class TheWalkTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let found = element.waitForExistence(timeout: timeout)
        if !found {
            // The whole accessibility tree, in the xcodebuild log, so a failure can be read without the result bundle.
            print("=== accessibility hierarchy when \(element) was missing ===\n\(app.debugDescription)\n=== end hierarchy ===")
        }
        XCTAssertTrue(found, "missing \(element)", file: file, line: line)
    }

    /// Waits for the element, scrolls it into view if needed, and taps it.
    private func tap(_ element: XCUIElement, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, timeout, file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private var shot = 0

    /// Keeps a screenshot in the result bundle (CI exports them as an artifact).
    private func snap(_ name: String) {
        shot += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%02d-%@", shot, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTheWalk() throws {
        // Welcome auto-advances → Get started
        waitFor(app.staticTexts["Welcome to Supermortgage"], 10)
        snap("welcome")
        waitFor(app.buttons["button.Get started"], 15)
        snap("how-i-work")
        tap(app.buttons["button.Get started"], 15)

        // Chat intro → Hazel
        waitFor(app.buttons["chat.option.Hazel"], 20)
        snap("chat-intro")
        tap(app.buttons["chat.option.Hazel"], 20)
        waitFor(text(containing: "Hazel it is"), 10)

        // The three connections: statement · Yes, go ahead · Plaid → Continue
        tap(app.buttons["chat.option.Upload a statement"], 15)
        tap(app.buttons["chat.option.Yes, go ahead"], 15)
        tap(app.buttons["chat.option.Connect with Plaid"], 15)
        waitFor(app.buttons["button.Continue"], 10)
        snap("plaid")
        tap(app.buttons["button.Continue"], 10)

        // The number appears
        waitFor(app.staticTexts["chat.number"], 20)
        XCTAssertEqual(app.staticTexts["chat.number"].label, "$3,188")
        waitFor(app.buttons["chat.option.Start the refinance"], 20)
        snap("chat-number")

        // Review it → Approve
        tap(app.buttons["chat.option.Review it"], 15)
        waitFor(app.staticTexts["sheet.title"], 10)
        XCTAssertEqual(app.staticTexts["sheet.title"].label, "Cancel PMI")
        snap("approval")
        tap(app.buttons["button.Approve"], 10)

        // Feed shows "PMI cancellation sent"
        tap(app.buttons["tab.feed"], 10)
        waitFor(text(containing: "PMI cancellation sent"), 10)
        snap("feed")

        // Work shows "2 need you"
        tap(app.buttons["tab.work"], 10)
        waitFor(text(containing: "2 need you"), 10)
        snap("work")

        // Tap a Needs-you row → sheet → close
        tap(app.buttons["work.row.w1"], 10)
        waitFor(app.staticTexts["sheet.title"], 10)
        waitFor(app.staticTexts["History"], 10)
        snap("work-sheet")
        tap(app.buttons["sheet.close"], 10)

        // Goals shows "$3,114"
        tap(app.buttons["tab.goals"], 10)
        waitFor(app.staticTexts["goals.number"], 10)
        XCTAssertEqual(app.staticTexts["goals.number"].label, "$3,114")
        snap("goals")

        // Artifacts → Refinance comparison → Start the refinance
        tap(app.buttons["tab.artifacts"], 10)
        waitFor(app.buttons["artifact.refi"], 10)
        snap("artifacts")
        tap(app.buttons["artifact.refi"], 10)
        waitFor(app.staticTexts["Your loan today vs the offer"], 10)
        snap("artifact-refinance")
        tap(app.buttons["button.Start the refinance"], 10)

        // The Refinance cover → Hand back
        waitFor(app.staticTexts["refinance.title"], 20)
        snap("refinance-cover")
        tap(app.buttons["refinance.handback"], 10)

        // Chat shows "I’ve got it from here"
        waitFor(text(containing: "I’ve got it from here"), 15)
        snap("chat-handed-back")

        // Avatar → Permissions → Memory → close
        tap(app.buttons["header.avatar"], 10)
        tap(app.buttons["segment.Permissions"], 10)
        waitFor(app.staticTexts["Does on its own"], 10)
        snap("agent-permissions")
        tap(app.buttons["segment.Memory"], 10)
        waitFor(app.textViews["agent.memory"], 10)
        snap("agent-memory")
        tap(app.buttons["sheet.close"], 10)

        // Menu → Settings → Dark → close
        tap(app.buttons["header.menu"], 10)
        waitFor(app.buttons["menu.Settings"], 10)
        snap("menu")
        tap(app.buttons["menu.Settings"], 10)
        waitFor(app.staticTexts["Appearance"], 10)
        tap(app.buttons["segment.Dark"], 10)
        snap("settings-dark")
        tap(app.buttons["sheet.close"], 10)

        // Type "what is my number now?" → the reply contains "$3,114"
        let field = app.textFields["composer.field"]
        tap(field, 10)
        field.typeText("what is my number now?")
        tap(app.buttons["composer.send"], 10)
        waitFor(text(containing: "$3,114"), 15)
        snap("chat-reply-dark")

        // Pause everything → header reads "Paused"
        tap(app.buttons["header.avatar"], 10)
        tap(app.buttons["agent.pause"], 10)
        tap(app.buttons["sheet.close"], 10)
        let snippet = app.staticTexts["header.snippet"]
        waitFor(snippet, 10)
        XCTAssertEqual(snippet.label, "Paused")
        snap("paused-dark")
    }
}
