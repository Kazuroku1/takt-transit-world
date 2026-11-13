import XCTest

final class TaktUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testBuyQuestTramAndUpgrade() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--freeze-clock"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        app.buttons["open-lines"].tap()
        let second = app.buttons["buy-b33"]
        scrollTo(second,in: app)
        XCTAssertTrue(second.isEnabled)
        second.tap()
        XCTAssertTrue(app.staticTexts["route-b33-owned"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Aufgaben"].tap()
        let reward = app.buttons["claim-second"]
        scrollTo(reward,in: app); reward.tap()
        XCTAssertFalse(app.buttons["claim-second"].exists)
        app.tabBars.buttons["Linien"].tap()
        let tram = app.buttons["buy-t4"]
        scrollTo(tram,in: app); XCTAssertTrue(tram.isEnabled); tram.tap()
        XCTAssertTrue(app.staticTexts["route-t4-owned"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Aufgaben"].tap()
        let tramReward = app.buttons["claim-tram"]
        scrollTo(tramReward,in: app); tramReward.tap()
        app.tabBars.buttons["Linien"].tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let upgrade = app.buttons["upgrade-b31"]
        scrollTo(upgrade,in: app); XCTAssertTrue(upgrade.isEnabled); upgrade.tap()
        XCTAssertTrue(app.staticTexts["2/5 Fahrzeuge"].waitForExistence(timeout: 3))
        capture("Native Linien und Ausbau")
    }
    func testNativeCityAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        sleep(3)
        capture("Native Stadt")
        app.tabBars.buttons["Welt"].tap()
        XCTAssertTrue(app.staticTexts["Nächster Halt: die Welt."].waitForExistence(timeout: 5))
        capture("Native Weltkarte")
        app.tabBars.buttons["Flotte"].tap()
        XCTAssertTrue(app.buttons["vehicle-bus"].waitForExistence(timeout: 5))
        app.buttons["vehicle-bus"].tap()
        XCTAssertTrue(app.buttons["buy-b33"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.switches["Abendstimmung"].waitForExistence(timeout: 5))
        app.switches["Abendstimmung"].tap()
        app.buttons["Fertig"].tap()
        app.tabBars.buttons["Stadt"].tap()
        capture("Native Abendstimmung")
    }
    func testAllNativeVehiclesRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--demo-all"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        sleep(4)
        capture("Native Flotte in Bewegung")
    }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable,"Element is not reachable: \(element)")
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
