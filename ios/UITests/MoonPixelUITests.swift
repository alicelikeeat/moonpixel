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

    /// Lesser used actions live in the More menu.
    private func more(_ app: XCUIApplication, _ name: String) {
        app.buttons["more"].tap(); sleep(1)
        app.buttons[name].firstMatch.tap()
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
        more(app, "Clean"); sleep(1)
        XCTAssertTrue(text(app, containing: "Cleaned").waitForExistence(timeout: 3), "clean toast shown")
        app.buttons["64×"].tap(); sleep(8)
        shot("05-fast")
        // cheats unlock every power; the arsenal lists five schools; a storm is called
        more(app, "Cheats"); sleep(1)
        app.buttons["cheat-rich"].tap(); app.buttons["cheat-powers"].tap(); app.buttons["weather-3"].tap(); app.buttons["cheat-animals"].tap(); sleep(1)
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
        // free building: choose a piece, drag a line, confirm (at normal speed, so nothing scrolls away)
        app.buttons["1×"].tap(); sleep(1)
        app.buttons["Build"].tap(); sleep(2)
        shot("09-build-panel")
        XCTAssertTrue(app.buttons["piece-wall_stone"].exists && app.buttons["piece-furnace"].exists && app.buttons["piece-lever"].exists, "pieces to build")
        app.buttons["piece-floor_wood"].tap(); sleep(1)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.30)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.30))
        from.press(forDuration: 0.1, thenDragTo: to); sleep(1)
        shot("10-build-preview")
        XCTAssertTrue(app.buttons["build-confirm"].waitForExistence(timeout: 3), "a preview waits for confirmation")
        XCTAssertTrue(text(app, containing: "tiles").exists, "the preview tells how many tiles and what it costs")
        app.buttons["build-confirm"].tap(); sleep(1)
        XCTAssertFalse(app.buttons["build-confirm"].exists, "the plan was carried out (or refused) and is no longer pending")
        shot("11-built")
        app.buttons["build-done"].tap(); sleep(1)
        // crafting
        app.buttons["Craft"].tap(); sleep(2)
        shot("12-craft")
        XCTAssertTrue(text(app, containing: "Smelt iron").exists && text(app, containing: "Siege engine").exists, "recipes listed")
        app.buttons["close-panel"].tap(); sleep(1)
        // cities and capitals
        app.buttons["Cities"].tap(); sleep(2)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'city-'")).firstMatch.tap(); sleep(2)
        shot("13-cities")
        XCTAssertTrue(text(app, containing: "people").exists && text(app, containing: "governance").exists, "a city's state is shown")
        XCTAssertTrue(text(app, containing: "★").exists, "capitals are marked")
        app.buttons["city-locate"].tap(); sleep(2)
        XCTAssertTrue(app.buttons["stop-watching"].waitForExistence(timeout: 3), "the camera went to the city, apart from the character")
        shot("14-city-view")
        app.buttons["stop-watching"].tap(); sleep(1)
        // a war, followed with the camera
        more(app, "Cheats"); sleep(1)
        app.buttons["cheat-war"].tap(); sleep(3)
        XCTAssertTrue(text(app, containing: "Following").waitForExistence(timeout: 4), "the camera follows the army")
        app.buttons["4×"].tap(); sleep(6)
        shot("15-war-march")
        app.buttons["War"].tap(); sleep(2)
        shot("16-war-panel")
        XCTAssertTrue(text(app, containing: "morale").exists, "armies with morale and rations")
        app.buttons["close-panel"].tap(); sleep(1)
        app.buttons["History"].tap(); sleep(2)
        shot("17-chronicle")
        let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS 'declared war'")).firstMatch
        XCTAssertTrue(entry.exists || text(app, containing: "declared war").exists, "numbered history, with the war in it")
        app.buttons["close-panel"].tap(); sleep(1)
        if app.buttons["stop-watching"].exists { app.buttons["stop-watching"].tap(); sleep(1) }
        app.buttons["1×"].tap(); sleep(1)
        // world laws: one tap really deletes
        more(app, "Laws"); sleep(2)
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
        more(app, "Worlds"); sleep(2)
        shot("06-world-list")
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5), "the saved world is listed")
        // second world from one sentence: a suggestion fills the composer, the analysis shows live
        app.buttons["suggestion-0"].tap(); sleep(1)
        shot("06b-sentence")
        XCTAssertTrue(text(app, containing: "Climate: Snow").exists, "the sentence was analysed (climate)")
        XCTAssertTrue(text(app, containing: "Industrial age").exists, "the sentence was analysed (era)")
        app.buttons["create-world"].tap(); sleep(6)
        shot("06c-sentence-world")
        more(app, "Worlds"); sleep(2)
        shot("07-two-worlds")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Play").count, 2, "two worlds side by side")
        app.buttons["Play"].firstMatch.tap(); sleep(4)
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 8), "re-entered a saved world")
        shot("08-reopened")
    }
}
