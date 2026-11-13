import XCTest

/// Drives the real app in the simulator: creates worlds from the menu, taps
/// HUD buttons and records screenshots.
final class MoonPixelUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func text(_ app: XCUIApplication, containing s: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func testMenuWorldsAndHUDButtons() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        shot("01-menu")
        let create = app.buttons["create-world"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "create button exists")
        create.tap()
        sleep(6)
        shot("02-new-world")
        let map = app.buttons["Map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "entered the game from the menu")
        map.tap(); sleep(2)
        shot("03-map")
        XCTAssertTrue(text(app, containing: "chunks mapped").waitForExistence(timeout: 4), "map opened")
        map.tap(); sleep(1)
        // the status capsule opens the details sheet (tech, map size, memory)
        let status = app.buttons.containing(NSPredicate(format: "label CONTAINS 'people'")).firstMatch
        XCTAssertTrue(status.exists)
        status.tap(); sleep(2)
        shot("04-details")
        XCTAssertTrue(text(app, containing: "of 5 GB").exists || text(app, containing: "/ 5 GB").exists, "map size is shown against the 5 GB cap")
        XCTAssertTrue(text(app, containing: "Tech:").exists, "technology line is shown")
        status.tap(); sleep(1)
        app.buttons["Clean"].tap(); sleep(1)
        XCTAssertTrue(text(app, containing: "Cleaned").waitForExistence(timeout: 3), "clean toast shown")
        app.buttons["64×"].tap(); sleep(8)
        shot("05-fast")
        // back to the world list, then a second world
        app.buttons["Worlds"].tap(); sleep(2)
        shot("06-world-list")
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5), "the saved world is listed")
        app.buttons["create-world"].tap(); sleep(5)
        app.buttons["Worlds"].tap(); sleep(2)
        shot("07-two-worlds")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Play").count, 2, "two worlds side by side")
        app.buttons["Play"].firstMatch.tap(); sleep(4)
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 8), "re-entered a saved world")
        shot("08-reopened")
    }
}
