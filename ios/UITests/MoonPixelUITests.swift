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
    /// The panel slides in: on a slow simulator a tap made while it moves can land beside the button, so
    /// wait until the button is there and can be hit before tapping it.
    private func more(_ app: XCUIApplication, _ name: String) {
        let open = app.buttons["more"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the More button is there")
        open.tap()
        let b = app.buttons[name].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 10), "\(name) is in the More panel")
        let until = Date().addingTimeInterval(8)
        while !b.isHittable && Date() < until { usleep(200_000) }
        usleep(600_000)                                   // let the slide finish
        b.tap()
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
        more(app, "Clean")                                 // the toast lasts a few seconds: look for it at once
        // the toast fades after a few seconds; the last message stays readable for tests
        let last = app.staticTexts["last-toast"]
        let cleaned = NSPredicate(format: "label CONTAINS 'Cleaned'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: cleaned, evaluatedWith: last)], timeout: 15), .completed, "clean was announced")
        app.buttons["64×"].tap(); sleep(8)
        shot("05-fast")
        // cheats unlock every power; the arsenal lists five schools; a storm is called
        // (at 1x, so the storm is still there when it is checked: at 64x it can pass within a second)
        if app.buttons["1×"].exists { app.buttons["1×"].tap(); sleep(1) }
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
        // beyond the first three: every nation of the known world, in a list that grows with history
        app.buttons["realm-tab-world"].tap(); sleep(1)
        let summary = app.descendants(matching: .any)["civ-summary"]
        for _ in 0..<4 where !summary.isHittable { app.swipeUp(); sleep(1) }
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "the known world is listed")
        shot("05c-world-nations")
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'civ-open-'")).firstMatch
        if open.waitForExistence(timeout: 3) {
            open.tap(); sleep(2)
            XCTAssertTrue(app.descendants(matching: .any)["civ-ledger"].waitForExistence(timeout: 4), "a nation in full: its people's ledger")
            shot("05d-nation-detail")
            app.buttons["close-panel"].firstMatch.tap(); sleep(1)
        }
        app.buttons["close-panel"].firstMatch.tap(); sleep(1)
        // free building: choose a piece, drag a line, confirm (at normal speed, so nothing scrolls away)
        app.buttons["1×"].tap(); sleep(1)
        app.buttons["Build"].tap(); sleep(2)
        shot("09-build-panel")
        XCTAssertTrue(app.buttons["piece-wall_stone"].exists && app.buttons["piece-furnace"].exists && app.buttons["piece-lever"].exists, "pieces to build")
        app.buttons["piece-floor_wood"].tap(); sleep(1)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.30)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.30))
        from.press(forDuration: 0.1, thenDragTo: to); sleep(1)
        shot("10-build-preview")
        print("UITEST build: " + app.staticTexts["save-state"].label + " toast: " + app.staticTexts["last-toast"].label)
        XCTAssertTrue(app.buttons["build-confirm"].waitForExistence(timeout: 3), "a preview waits for confirmation")
        XCTAssertTrue(text(app, containing: "tiles").exists, "the preview tells how many tiles and what it costs")
        app.buttons["build-confirm"].tap(); sleep(1)
        XCTAssertFalse(app.buttons["build-confirm"].exists, "the plan was carried out (or refused) and is no longer pending")
        shot("11-built")
        app.buttons["build-done"].tap(); sleep(1)
        // crafting
        more(app, "Craft"); sleep(2)
        shot("12-craft")
        XCTAssertTrue(text(app, containing: "Smelt iron").exists && text(app, containing: "Siege engine").exists, "recipes listed")
        app.buttons["close-panel"].tap(); sleep(1)
        // cities and capitals
        more(app, "Cities"); sleep(2)
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
        more(app, "War"); sleep(2)
        shot("16-war-panel")
        XCTAssertTrue(text(app, containing: "morale").exists, "armies with morale and rations")
        app.buttons["close-panel"].tap(); sleep(1)
        more(app, "History"); sleep(2)
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
        more(app, "Worlds")
        _ = app.buttons["create-world"].waitForExistence(timeout: 30)          // leaving waits for the save
        shot("06-world-list")
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 5), "the saved world is listed")
        // second world from one sentence: a suggestion fills the composer, the analysis shows live
        app.buttons["suggestion-0"].tap(); sleep(1)
        shot("06b-sentence")
        XCTAssertTrue(text(app, containing: "Climate: Snow").exists, "the sentence was analysed (climate)")
        XCTAssertTrue(text(app, containing: "Industrial age").exists, "the sentence was analysed (era)")
        app.buttons["create-world"].tap(); sleep(6)
        shot("06c-sentence-world")
        more(app, "Worlds")
        // leaving waits for the save of this (larger, industrial-age) world before the list appears
        _ = app.buttons["create-world"].waitForExistence(timeout: 30)
        sleep(1)
        shot("07-two-worlds")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "Play").count, 2, "two worlds side by side")
        app.buttons["Play"].firstMatch.tap(); sleep(4)
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 8), "re-entered a saved world")
        shot("08-reopened")
    }

    /// A save that fails keeps the world open (and paused); retrying and succeeding then leaves.
    func testFailedSaveBlocksLeavingAndRetryLeaves() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--fail-exit-saves", "1"]     // the save made for leaving fails once; the retry succeeds
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 15), "in the world")
        sleep(3)
        more(app, "Worlds")
        _ = app.buttons["retry-exit"].waitForExistence(timeout: 15)      // the failing save runs on a background queue first
        shot("20-exit-blocked")
        print("UITEST save-state: " + app.staticTexts["save-state"].label + " toast: " + app.staticTexts["last-toast"].label)
        XCTAssertTrue(app.otherElements["exit-blocked"].exists || app.buttons["retry-exit"].exists, "leaving was refused with an explanation")
        XCTAssertTrue(app.buttons["Map"].exists, "the world is still open")
        XCTAssertFalse(app.buttons["create-world"].exists, "not back at the world list")
        app.buttons["retry-exit"].tap(); sleep(4)
        XCTAssertTrue(app.buttons["create-world"].waitForExistence(timeout: 10), "after a good save it leaves")
        XCTAssertTrue(app.buttons["Play"].firstMatch.exists, "and the world is listed")
        shot("21-left-after-retry")
    }

    /// The 3D view is another way of drawing the same running game: switch to it, use the HUD, switch back.
    func testThreeDViewShowsTheSameGameAndSwitchesBack() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--2d"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20), "the game started")
        sleep(4)
        shot("3d-00-flat")
        let solid = app.descendants(matching: .any)["Solid3D"]
        XCTAssertFalse(solid.exists, "2D to begin with")
        more(app, "View3D"); sleep(8)
        shot("3d-01-solid")
        XCTAssertTrue(solid.waitForExistence(timeout: 5), "the 3D view is on screen")
        // the HUD is the same one and still works over it
        let status = app.buttons.containing(NSPredicate(format: "label CONTAINS 'people'")).firstMatch
        XCTAssertTrue(status.exists, "the status capsule is there in 3D")
        app.buttons["Map"].tap(); sleep(2)
        XCTAssertTrue(text(app, containing: "chunks mapped").waitForExistence(timeout: 4), "the map opens in 3D")
        app.buttons["Map"].tap(); sleep(1)
        // turn the camera, zoom, tap the ground: nothing may crash and the game goes on
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).press(forDuration: 0.1, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)))
        sleep(2)
        shot("3d-02-turned")
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55)).tap(); sleep(1)
        print("UITEST frames: window \(win.frame) 64x \(app.buttons["64×"].frame) status \(status.frame) jump \(app.buttons["jump"].frame) hotbar \(app.buttons["hotbar-0"].frame) more \(app.buttons["more"].frame)")
        app.buttons["64×"].tap(); sleep(6)
        shot("3d-03-fast")
        XCTAssertTrue(status.exists)
        if app.buttons["1×"].exists { app.buttons["1×"].tap(); sleep(1) }
        more(app, "View3D"); sleep(4)
        shot("3d-04-flat-again")
        XCTAssertFalse(solid.exists, "back in 2D")
        XCTAssertTrue(status.exists, "the same game is still running")
    }

    /// Command mode: a battle of its own beside the world. Enter it, order a reactor, see it finish, leave; the world is still there.
    func testCommandModeBuildsAndReturnsToTheWorld() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--2d", "--new-battle"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20), "the game started")
        sleep(3)
        more(app, "Command")
        let credits = app.staticTexts["cmd-credits"].exists ? app.staticTexts["cmd-credits"] : app.descendants(matching: .any)["cmd-credits"]
        XCTAssertTrue(credits.waitForExistence(timeout: 15), "the battle's HUD is up")
        sleep(3)
        shot("cmd-00-start")
        XCTAssertFalse(app.buttons["Map"].exists, "the world's HUD is away while the battle runs")
        let reactor = app.buttons["cmd-build-reactor"]
        XCTAssertTrue(reactor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cmd-build-works"].isEnabled, "an engine works needs a refinery first")
        reactor.tap()
        // eight seconds of work: then it waits to be put down, and tapping it and the map puts it down
        XCTAssertTrue(app.descendants(matching: .any)["cmd-cancel"].waitForExistence(timeout: 5), "a structure is being made")
        sleep(11)
        shot("cmd-01-ready")
        reactor.tap(); sleep(1)
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.32)).tap(); sleep(2)
        shot("cmd-02-placed")
        app.buttons["cmd-army"].tap(); sleep(1)
        XCTAssertTrue(app.descendants(matching: .any)["cmd-selection"].waitForExistence(timeout: 4), "the army is selected")
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap(); sleep(3)
        shot("cmd-03-ordered")
        app.buttons["cmd-exit"].tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 15), "back in the world")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'people'")).firstMatch.exists, "and the world went on waiting")
        shot("cmd-04-back")
    }

    /// Metro mode: found a city, lay a street, zone along it, open the budget, leave; the city is kept.
    func testMetroModeBuildsAndKeepsTheCity() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--2d"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20), "the game started")
        sleep(3)
        more(app, "Metro")
        let money = app.descendants(matching: .any)["metro-money"]
        XCTAssertTrue(money.waitForExistence(timeout: 15), "the city's HUD is up")
        sleep(2)
        shot("metro-00-start")
        let before = money.label
        app.buttons["metro-group-roads"].tap(); sleep(1)
        app.buttons["metro-tool-street"].tap(); sleep(1)
        let win = app.windows.firstMatch
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).press(forDuration: 0.2, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
        sleep(2)
        shot("metro-01-street")
        XCTAssertNotEqual(money.label, before, "a street was paid for")
        app.buttons["metro-group-zones"].tap(); sleep(1)
        app.buttons["metro-tool-R"].tap(); sleep(1)
        win.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.38)).press(forDuration: 0.2, thenDragTo: win.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.52)))
        sleep(2)
        shot("metro-02-zoned")
        app.buttons["metro-done"].tap(); sleep(1)
        app.buttons["metro-budget"].tap(); sleep(1)
        XCTAssertTrue(app.descendants(matching: .any)["metro-budget-line"].waitForExistence(timeout: 4), "the budget opens")
        shot("metro-03-budget")
        app.buttons["metro-budget-close"].tap(); sleep(1)
        app.buttons["metro-speed-0"].tap(); sleep(2)          // paused: the city is left exactly as it is
        let spent = money.label
        app.buttons["metro-exit"].tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 15), "back in the world")
        more(app, "Metro")
        XCTAssertTrue(money.waitForExistence(timeout: 15))
        sleep(1)
        XCTAssertEqual(money.label, spent, "the city was kept as it was left (and reopens paused)")
        shot("metro-04-reopened")
        app.buttons["metro-speed-1"].tap()
        app.buttons["metro-exit"].tap()
    }

    /// A city whose save fails is not closed: leaving is refused with an explanation, the city stays,
    /// and a retry that saves leaves.
    func testMetroFailedSaveKeepsTheCityAndRetryLeaves() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--2d", "--fail-metro-saves", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20), "the game started")
        sleep(3)
        more(app, "Metro")
        XCTAssertTrue(app.descendants(matching: .any)["metro-money"].waitForExistence(timeout: 15), "the city's HUD is up")
        sleep(1)
        app.buttons["metro-exit"].tap()
        XCTAssertTrue(app.buttons["metro-retry-exit"].waitForExistence(timeout: 8), "leaving was refused with a way to retry")
        shot("metro-05-exit-blocked")
        XCTAssertTrue(app.descendants(matching: .any)["metro-money"].exists, "the city is still open")
        XCTAssertFalse(app.buttons["Map"].exists, "not back in the world")
        app.buttons["metro-retry-exit"].tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 15), "after a good save it leaves")
    }

    /// The pitch of the 3D view, read from the hidden "camera-state" text ("first yaw 0.40 pitch 0.80").
    private func pitch(_ app: XCUIApplication) -> Double? {
        let e = app.staticTexts["camera-state"]
        guard e.exists else { return nil }
        let parts = e.label.split(separator: " ")
        guard let i = parts.firstIndex(of: "pitch"), i + 1 < parts.count else { return nil }
        return Double(parts[i + 1])
    }

    /// v2.5: dragging up and down in 3D did not look up or down (an orbit camera clamped to look down at the
    /// traveller). In first person a drag on the right side changes the pitch, it stays changed over many
    /// frames, and it still works after a panel was opened and closed; moving, jumping and turning at once.
    func testFirstPersonLooksUpAndDownAndItStays() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--first-person"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20), "in the world")
        sleep(4)
        guard let p0 = pitch(app) else { return XCTFail("no camera state") }
        let view = app.otherElements["Solid3D"].exists ? app.otherElements["Solid3D"] : app.windows.firstMatch
        let from = view.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7)), to = view.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.35))
        from.press(forDuration: 0.05, thenDragTo: to)
        sleep(2)
        guard let p1 = pitch(app) else { return XCTFail("no camera state") }
        XCTAssertGreaterThan(p1, p0 + 0.2, "dragging up looks up (pitch \(p0) -> \(p1))")
        sleep(3)
        XCTAssertEqual(pitch(app) ?? 0, p1, accuracy: 0.001, "and it stays there: nothing pulls it back")
        shot("30-look-up")
        to.press(forDuration: 0.05, thenDragTo: view.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.75)))
        sleep(2)
        XCTAssertLessThan(pitch(app) ?? 1, p1 - 0.3, "and down again")
        // the backpack opens and closes; the drag still works afterwards
        XCTAssertTrue(app.buttons["backpack"].waitForExistence(timeout: 5))
        app.buttons["backpack"].tap(); sleep(1)
        shot("31-backpack")
        XCTAssertTrue(text(app, containing: "Backpack").exists || text(app, containing: "背包").exists)
        app.buttons["close-panel"].tap(); sleep(1)
        let p2 = pitch(app) ?? 0
        view.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7)).press(forDuration: 0.05, thenDragTo: view.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)))
        sleep(2)
        XCTAssertGreaterThan(pitch(app) ?? 0, p2 + 0.2, "no leftover layer swallows the drag after a panel closed")
        // jump: the height line shows the body in the air for a moment
        XCTAssertTrue(app.buttons["jump"].exists)
        app.buttons["jump"].tap()
        shot("32-jump")
    }

    /// The traveller rides an outside elevator up a six-storey house: the height shown climbs, and the
    /// elevator panel lists only the landings it stops at.
    func testRidingTheOutsideElevator() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--3d", "--lift-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20))
        let line = app.staticTexts["height-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 15), "the height is shown")
        sleep(2)
        shot("33-in-the-car")
        guard app.buttons["lift-open"].waitForExistence(timeout: 10) else { return XCTFail("no elevator button beside the car") }
        app.buttons["lift-open"].tap(); sleep(1)
        XCTAssertTrue(app.buttons["lift-stop-0"].exists && app.buttons["lift-stop-5"].exists, "its landings, ground to storey 5")
        XCTAssertFalse(app.buttons["lift-stop-6"].exists, "and none it does not stop at")
        shot("35-lift-panel")
        // where it is now (the demo sent it up), then down to the ground: the height shown falls
        let first = line.label
        app.buttons["lift-stop-0"].tap(); sleep(1)
        app.buttons["close-panel"].tap()
        sleep(6)
        let later = line.label
        print("UITEST lift: \(first) -> \(later)")
        XCTAssertNotEqual(first, later, "the car moved: \(first) -> \(later)")
        XCTAssertTrue(later.contains("Ground") || later.contains("地面"), "and stopped at the ground: \(later)")
        shot("34-car-down")
    }

    /// The transport demo: get into the car from the travel panel, drive it, hand it to the autopilot and back,
    /// brake, get out. The speed shown comes from the vehicle itself.
    func testDrivingACarFromTheTravelPanel() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7", "--transport-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 20))
        sleep(9)
        guard app.buttons["travel-open"].waitForExistence(timeout: 10) else { return XCTFail("no travel button") }
        app.buttons["travel-open"].tap(); sleep(1)
        shot("40-travel")
        let drive = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'board-drive-'")).firstMatch
        guard drive.waitForExistence(timeout: 5) else { return XCTFail("no vehicle to drive near the traveller") }
        drive.tap(); sleep(1)
        let speed = app.staticTexts["drive-speed"]
        guard speed.waitForExistence(timeout: 5) else { return XCTFail("no driving display") }
        let state = app.staticTexts["drive-state"]
        /// Wait until the vehicle itself reports `want` (its controls arrive on the next frames).
        func until(_ want: String, _ seconds: Double = 6) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { if state.label.contains(want) { return true }; usleep(200_000) }
            return false
        }
        XCTAssertTrue(app.sliders["drive-throttle"].exists, "the throttle")
        guard app.buttons["drive-throttle-up"].waitForExistence(timeout: 5) else { return XCTFail("no throttle buttons") }
        for _ in 0..<4 { app.buttons["drive-throttle-up"].tap() }
        XCTAssertTrue(until("in 1.00/0.00"), "the throttle reached the car: \(state.label)")
        sleep(2)
        let moving = speed.label
        print("UITEST drive: \(moving) | \(state.label)")
        print("UITEST demo: \(state.label.components(separatedBy: " | ").last ?? "")")
        XCTAssertNotEqual(moving, "0 km/h", "the car moves under its own power: \(moving) | \(state.label)")
        shot("41-driving")
        // the autopilot takes over (no destination: it holds), then back to the driver
        app.buttons["drive-auto"].tap()
        XCTAssertTrue(until("ctl auto"), "the autopilot has it: \(state.label)")
        print("UITEST drive auto: \(state.label)")
        shot("42-autopilot")
        app.buttons["drive-auto"].tap()
        XCTAssertTrue(until("ctl manual"), "back to the driver: \(state.label)")
        print("UITEST drive manual again: \(state.label)")
        guard app.buttons["drive-throttle-down"].waitForExistence(timeout: 5) else { return XCTFail("the controls did not come back") }
        for _ in 0..<4 { app.buttons["drive-throttle-down"].tap() }
        app.descendants(matching: .any)["drive-brake"].firstMatch.press(forDuration: 4)
        let stopped = until(" v 0.00 ", 8)
        print("UITEST drive stopped: \(speed.label) | \(state.label)")
        XCTAssertTrue(stopped, "it stopped: \(state.label)")
        guard app.buttons["drive-exit"].waitForExistence(timeout: 5) else { return XCTFail("no way out when stopped") }
        app.buttons["drive-exit"].tap(); sleep(1)
        XCTAssertFalse(app.staticTexts["drive-speed"].exists, "out of the car, the driving display is gone")
        shot("43-out")
    }
}

