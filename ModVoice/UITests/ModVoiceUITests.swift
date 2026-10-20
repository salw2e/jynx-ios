import XCTest

final class ModVoiceUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
    }

    func testSetupScreen() {
        app.launchArguments = ["-uitest"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chill"].waitForExistence(timeout: 10))
        shot("01 app")
        app.staticTexts["Chill"].tap()
        XCTAssertTrue(app.navigationBars["Chill"].waitForExistence(timeout: 5))
        shot("02 tone editor")
        app.buttons["Cancel"].tap()
        XCUIDevice.shared.appearance = .dark
        Thread.sleep(forTimeInterval: 1.5)
        shot("03 app dark")
    }

    func testKeyboard() {
        app.launchArguments = ["-uitest", "-harness"]
        app.launch()
        let field = app.textViews["harness"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(key("q").waitForExistence(timeout: 5))
        shot("10 keyboard")

        type("teh")
        XCTAssertEqual(text(field), "Teh")
        XCTAssertTrue(app.buttons["“Teh”"].exists, "the typed word is shown in quotes when it will be corrected")
        XCTAssertTrue(app.buttons["The"].exists, "the correction is offered")
        shot("11 suggestions")
        key("space").tap()
        XCTAssertEqual(text(field), "The ")
        key("delete").tap()
        XCTAssertEqual(text(field), "Teh", "backspace right after a correction puts the word back")
        key("space").tap()
        XCTAssertEqual(text(field), "Teh ", "a word put back is learned and left alone")

        type("dont")
        key("space").tap()
        type("gng")
        key("space").tap()
        XCTAssertEqual(text(field), "Teh don't gng ")

        type("i")
        key("layer").tap()
        XCTAssertTrue(key("1").waitForExistence(timeout: 3))
        shot("12 numbers")
        key(".").tap()
        key("space").tap()
        XCTAssertEqual(text(field), "Teh don't gng I. ")
        XCTAssertTrue(key("q").exists, "space goes back to letters")
        type("ok")
        XCTAssertEqual(text(field), "Teh don't gng I. Ok", "a new sentence starts with a capital")

        key("layer").tap()
        key("symbols").tap()
        XCTAssertTrue(key("€").waitForExistence(timeout: 3))
        shot("13 symbols")
        key("numbers").tap()
        key("layer").tap()

        key("emoji").tap()
        XCTAssertTrue(app.buttons["😂"].waitForExistence(timeout: 3))
        shot("14 emoji")
        app.buttons["😂"].tap()
        XCTAssertEqual(text(field), "Teh don't gng I. Ok😂")
        key("letters").tap()
        XCTAssertTrue(key("q").waitForExistence(timeout: 3))

        app.buttons["tone-button"].tap()
        XCTAssertTrue(app.buttons["Firm"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Chill"].exists, "your own tones are listed")
        shot("15 tones")
        app.buttons["Firm"].tap()
        XCTAssertTrue(app.buttons["tone-button"].label.contains("Firm"), app.buttons["tone-button"].label)

        app.buttons["fix"].tap()
        XCTAssertTrue(app.staticTexts["bar-message"].waitForExistence(timeout: 30))
        shot("16 fix message")
        app.buttons["close-bar"].tap()

        XCUIDevice.shared.appearance = .dark
        Thread.sleep(forTimeInterval: 1.5)
        type("hey")
        shot("17 dark")
        key("emoji").tap()
        shot("18 emoji dark")
    }

    private func key(_ name: String) -> XCUIElement {
        app.buttons["key-\(name)"]
    }

    private func type(_ s: String) {
        for c in s { key(String(c)).tap() }
    }

    private func text(_ field: XCUIElement) -> String {
        field.value as? String ?? ""
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
