import XCTest

final class TaktUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 { capture("Fehlgeschlagener Ablauf") }
    }
    func testMountainBusesQuestAndUpgrade() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--freeze-clock"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        waitForMap(in: app)
        XCTAssertEqual(app.buttons["current-city"].label, "Andermatt")
        app.buttons["open-lines"].tap()
        XCTAssertTrue(app.navigationBars["Dein Liniennetz"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["buy-t4"].exists, "Mountain regions begin with buses only")
        let second = app.buttons["buy-b33"]
        scrollTo(second,in: app)
        XCTAssertTrue(second.isEnabled)
        second.tap()
        XCTAssertTrue(app.staticTexts["route-b33-owned"].waitForExistence(timeout: 3))
        closeSheet(in: app)
        let wallet = app.descendants(matching: .any).matching(identifier: "wallet").firstMatch
        XCTAssertTrue(wallet.label.contains("Guthaben 650 Münzen"), "Scrolling must not purchase a vehicle")
        XCTAssertTrue(app.buttons["open-quests"].waitForExistence(timeout: 5))
        app.buttons["open-quests"].tap()
        XCTAssertTrue(app.navigationBars["Deine Aufgaben"].waitForExistence(timeout: 5))
        let reward = app.buttons["claim-second"]
        scrollTo(reward,in: app); reward.tap()
        XCTAssertFalse(app.buttons["claim-second"].exists)
        closeSheet(in: app)
        app.buttons["open-lines"].tap()
        let upgrade = app.buttons["upgrade-b31"]
        scrollTo(upgrade,in: app); XCTAssertTrue(upgrade.isEnabled); upgrade.tap()
        XCTAssertTrue(app.staticTexts["2/5 Fahrzeuge"].waitForExistence(timeout: 3))
        capture("Bergbus Linien und Ausbau")
    }
    func testNativeCityAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        waitForMap(in: app)
        capture("Andermatt Bergbus Start")
        app.buttons["current-city"].tap()
        XCTAssertTrue(app.staticTexts["Vom Bergdorf zur Schweiz."].waitForExistence(timeout: 5))
        capture("Schweiz Regionen Fortschritt")
        closeSheet(in: app)
        app.buttons["open-fleet"].tap()
        XCTAssertTrue(app.buttons["vehicle-bus"].waitForExistence(timeout: 5))
        app.buttons["vehicle-bus"].tap()
        scrollTo(app.buttons["buy-b33"], in: app)
        app.buttons["close-vehicle-detail"].tap()
        closeSheet(in: app)
        app.buttons["settings"].tap()
        XCTAssertTrue(app.switches["Abendstimmung"].waitForExistence(timeout: 5))
        let nightSwitch = app.switches["Abendstimmung"]
        nightSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.92,dy: 0.5)).tap()
        XCTAssertEqual(nightSwitch.value as? String,"1")
        capture("Native Einstellungen")
        app.buttons["close-sheet"].tap()
        XCTAssertTrue(app.buttons["open-lines"].isHittable)
        let lighting = app.descendants(matching: .any).matching(identifier: "city-lighting").firstMatch
        XCTAssertTrue(lighting.waitForExistence(timeout: 5))
        XCTAssertEqual(lighting.label,"Nachtmodus")
        sleep(1)
        capture("Andermatt Abendstimmung")
    }
    func testAllNativeVehiclesRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--demo-all"]
        app.launch()
        XCTAssertTrue(app.buttons["open-lines"].waitForExistence(timeout: 15))
        waitForMap(in: app)
        capture("Zuerich Bus Tram S-Bahn Fernzug")
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
        capture("Ganze Schweiz")
        app.buttons["region-focus"].tap()
        XCTAssertNotEqual(map.value as? String, explored)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["open-lines"].isHittable)
        XCTAssertTrue(app.buttons["settings"].isHittable)
        capture("Landscape city HUD")
    }
    func testUnlockValleyAndReturnToMountains() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--freeze-clock", "--test-valley-ready"]
        app.launch()
        XCTAssertTrue(app.buttons["current-city"].waitForExistence(timeout: 15))
        waitForMap(in: app)
        app.buttons["current-city"].tap()
        let unlock = app.buttons["visit-altdorf"]
        scrollTo(unlock, in: app)
        XCTAssertTrue(unlock.isEnabled)
        unlock.tap()
        let arrived = NSPredicate(format: "label == %@", "Altdorf")
        expectation(for: arrived, evaluatedWith: app.buttons["current-city"])
        waitForExpectations(timeout: 10)
        app.buttons["open-lines"].tap()
        XCTAssertTrue(app.staticTexts["route-b31-owned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["buy-t4"].exists)
        closeSheet(in: app)
        app.buttons["current-city"].tap()
        let returnToMountains = app.buttons["visit-andermatt"]
        scrollTo(returnToMountains, in: app)
        XCTAssertTrue(returnToMountains.isEnabled)
        returnToMountains.tap()
        let returned = NSPredicate(format: "label == %@", "Andermatt")
        expectation(for: returned, evaluatedWith: app.buttons["current-city"])
        waitForExpectations(timeout: 10)
        capture("Zurueck im Bergdorf")
    }
    private func waitForMap(in app: XCUIApplication) {
        let map = app.descendants(matching: .any).matching(identifier: "native-city").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let ready = NSPredicate(format: "value CONTAINS %@", "Schweiz bereit")
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
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            // Stay in the empty outer gutter, never press a purchase button
            // while initiating a synthetic scroll gesture.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.78))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.38))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture("Element nicht erreichbar")
        XCTAssertTrue(element.exists && element.isHittable,"Element is not reachable: \(element)")
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
