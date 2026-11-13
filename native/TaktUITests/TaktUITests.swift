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
        closeSheet(in: app)
        app.buttons["open-quests"].tap()
        let reward = app.buttons["claim-second"]
        scrollTo(reward,in: app); reward.tap()
        XCTAssertFalse(app.buttons["claim-second"].exists)
        closeSheet(in: app)
        app.buttons["open-lines"].tap()
        let tram = app.buttons["buy-t4"]
        scrollTo(tram,in: app); XCTAssertTrue(tram.isEnabled); tram.tap()
        XCTAssertTrue(app.staticTexts["route-t4-owned"].waitForExistence(timeout: 3))
        closeSheet(in: app)
        app.buttons["open-quests"].tap()
        let tramReward = app.buttons["claim-tram"]
        scrollTo(tramReward,in: app); tramReward.tap()
        closeSheet(in: app)
        app.buttons["open-lines"].tap()
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
        waitForMap(in: app)
        capture("Native Stadt")
        app.buttons["current-city"].tap()
        XCTAssertTrue(app.staticTexts["Nächster Halt: die Welt."].waitForExistence(timeout: 5))
        capture("Native Weltkarte")
        closeSheet(in: app)
        app.buttons["open-fleet"].tap()
        XCTAssertTrue(app.buttons["vehicle-bus"].waitForExistence(timeout: 5))
        app.buttons["vehicle-bus"].tap()
        XCTAssertTrue(app.buttons["buy-b33"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        closeSheet(in: app)
        app.buttons["settings"].tap()
        XCTAssertTrue(app.switches["Abendstimmung"].waitForExistence(timeout: 5))
        let nightSwitch = app.switches["Abendstimmung"]
        nightSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.92,dy: 0.5)).tap()
        XCTAssertEqual(nightSwitch.value as? String,"1")
        capture("Native Einstellungen")
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["open-lines"].isHittable)
        let lighting = app.descendants(matching: .any).matching(identifier: "city-lighting").firstMatch
        XCTAssertTrue(lighting.waitForExistence(timeout: 5))
        XCTAssertEqual(lighting.label,"Nachtmodus")
        sleep(1)
        capture("Native Abendstimmung")
    }
    func testAllNativeVehiclesRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--demo-all"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        waitForMap(in: app)
        capture("Native Flotte in Bewegung")
    }
    func testMapRemainsBehindSheetsAndOverview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--freeze-clock"]
        app.launch()
        XCTAssertTrue(app.buttons["city-overview"].waitForExistence(timeout: 15))
        waitForMap(in: app)
        XCTAssertEqual(app.tabBars.count, 0)
        let map = app.descendants(matching: .any).matching(identifier: "native-city").firstMatch
        XCTAssertTrue(map.exists)
        let viewport = app.frame
        XCTAssertGreaterThan(map.frame.height, viewport.height * 0.9)
        app.buttons["zoom-in"].tap()
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)
        let explored = map.value as? String
        XCTAssertNotNil(explored, "The canvas exposes its camera for accessibility")
        app.buttons["open-lines"].tap()
        scrollTo(app.buttons["view-b31"], in: app)
        closeSheet(in: app)
        XCTAssertEqual(map.value as? String, explored, "Closing a sheet must preserve the explored camera")
        app.buttons["open-lines"].tap()
        scrollTo(app.buttons["view-b31"], in: app)
        app.buttons["view-b31"].tap()
        XCTAssertTrue(app.buttons["city-overview"].waitForExistence(timeout: 5))
        app.buttons["city-overview"].tap()
        XCTAssertNotEqual(map.value as? String, explored)
        capture("Whole city overview")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["open-lines"].isHittable)
        XCTAssertTrue(app.buttons["settings"].isHittable)
        capture("Landscape city HUD")
    }
    private func waitForMap(in app: XCUIApplication) {
        let map = app.descendants(matching: .any).matching(identifier: "native-city").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let ready = NSPredicate(format: "value CONTAINS %@", "Amtliche Stadtkarte")
        expectation(for: ready, evaluatedWith: map)
        waitForExpectations(timeout: 60)
    }
    private func closeSheet(in app: XCUIApplication) {
        let close = app.buttons["close-sheet"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let returned = NSPredicate(format: "hittable == true")
        expectation(for: returned, evaluatedWith: app.buttons["open-lines"])
        waitForExpectations(timeout: 5)
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
