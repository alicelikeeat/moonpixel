import XCTest

/// Drives the real app in the simulator: taps HUD buttons and records screenshots.
final class MoonPixelUITests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testHUDButtonsRespond() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--autostart", "7"]
        app.launch()
        sleep(6)
        shot("01-start")
        print("UITEST buttons: \(app.buttons.allElementsBoundByIndex.map { "\($0.label)|\($0.identifier)|hittable=\($0.isHittable)" })")
        let map = app.buttons["Map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "map button exists")
        map.tap()
        sleep(2)
        shot("02-after-map-tap")
        let caption = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'chunks mapped'")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 4), "map opened after tapping the Map button")
        if caption.exists { map.tap(); sleep(1) }
        let clean = app.buttons["Clean"]
        if clean.exists { clean.tap(); sleep(1); shot("03-after-clean-tap") }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Cleaned'")).firstMatch.waitForExistence(timeout: 3), "clean toast shown")
        let x16 = app.buttons["16×"]
        if x16.exists { x16.tap(); sleep(2); shot("04-after-speed-tap") }
    }
}
