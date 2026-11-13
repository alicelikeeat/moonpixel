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
        // cheats unlock every power; the arsenal lists five schools; a storm is called
        app.buttons["Cheats"].tap(); sleep(1)
        app.buttons["cheat-powers"].tap(); app.buttons["weather-3"].tap(); app.buttons["cheat-animals"].tap(); sleep(1)
        shot("05f-cheats")
        app.buttons["close-panel"].tap(); sleep(1)
        XCTAssertTrue(text(app, containing: "cheated").exists, "the save is marked as cheated")
        XCTAssertTrue(text(app, containing: "Thunderstorm").exists, "the weather changed")
        app.buttons["Powers"].tap(); sleep(2)
        shot("05g-arsenal")
        XCTAssertTrue(text(app, containing: "Arms").exists && text(app, containing: "Divine").exists && text(app, containing: "Words").exists, "schools of power listed")
        XCTAssertTrue(app.buttons["power-pistol"].exists && app.buttons["power-thunder"].exists, "powers listed")
        app.buttons["power-thunder"].tap(); sleep(1)
        app.buttons["close-panel"].tap(); sleep(1)
        XCTAssertTrue(app.buttons["Thunderbolt"].exists, "the equipped power shows on the tab bar")
        shot("05h-storm")
        // the map: zoom, pick a place, teleport
        map.tap(); sleep(2)
        app.buttons["2×"].tap(); sleep(1)
        app.images["map-image"].tap(); sleep(1)
        shot("05i-map-pick")
        XCTAssertTrue(app.buttons["teleport"].waitForExistence(timeout: 3), "a place was picked on the map")
        app.buttons["teleport"].tap(); sleep(2)
        XCTAssertFalse(text(app, containing: "chunks mapped").exists, "teleporting closes the map")
        XCTAssertTrue(text(app, containing: "Teleported").exists || app.buttons["Map"].exists)
        // three nations: territory, relations, pressure and fatigue are on screen
        app.buttons["Nations"].tap(); sleep(2)
        shot("05b-nations")
        XCTAssertTrue(text(app, containing: "Azure").exists && text(app, containing: "Crimson").exists && text(app, containing: "Golden").exists, "three nations listed")
        XCTAssertTrue(text(app, containing: "Pressure").exists && text(app, containing: "fatigue").exists, "pressure and fatigue shown")
        XCTAssertTrue(text(app, containing: "Free traveller").exists, "the player starts neutral")
        app.buttons["join-1"].tap(); sleep(1)
        XCTAssertTrue(text(app, containing: "Azure · HP").exists, "the player joined a nation")
        app.buttons["close-panel"].tap(); sleep(1)
        // world laws: one tap really deletes
        app.buttons["Laws"].tap(); sleep(2)
        shot("05c-laws")
        XCTAssertTrue(app.buttons["law-thanos"].exists && app.buttons["law-annihilation"].exists && app.buttons["law-genesis"].exists && app.buttons["law-guixu"].exists, "four laws")
        app.buttons["law-thanos"].tap(); sleep(4)
        shot("05d-thanos")
        XCTAssertTrue(text(app, containing: "Thanos deleted").waitForExistence(timeout: 6), "thanos reports what it deleted")
        app.buttons["law-guixu"].tap(); sleep(4)
        XCTAssertTrue(text(app, containing: "Guixu deleted").waitForExistence(timeout: 6), "guixu reports what it deleted")
        app.buttons["law-genesis"].tap(); sleep(6)
        shot("05e-genesis")
        XCTAssertTrue(text(app, containing: "Genesis deleted").waitForExistence(timeout: 8), "genesis rebuilt the world")
        app.buttons["close-panel"].tap(); sleep(1)
        XCTAssertTrue(app.buttons["Map"].exists, "the game goes on in the new world")
        // back to the world list, then a second world
        app.buttons["Worlds"].tap(); sleep(2)
        shot("06-world-list")
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5), "the saved world is listed")
        // second world from one sentence: a suggestion fills the composer, the analysis shows live
        app.buttons["suggestion-0"].tap(); sleep(1)
        shot("06b-sentence")
        XCTAssertTrue(text(app, containing: "Climate: Snow").exists, "the sentence was analysed (climate)")
        XCTAssertTrue(text(app, containing: "Industrial age").exists, "the sentence was analysed (era)")
        app.buttons["create-world"].tap(); sleep(6)
        shot("06c-sentence-world")
        app.buttons["Worlds"].tap(); sleep(2)
        shot("07-two-worlds")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Play").count, 2, "two worlds side by side")
        app.buttons["Play"].firstMatch.tap(); sleep(4)
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 8), "re-entered a saved world")
        shot("08-reopened")
    }
}
