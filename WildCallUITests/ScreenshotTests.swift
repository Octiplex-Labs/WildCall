import XCTest

/// Captures the App Store screenshots. Run through
/// `Tools/screenshots/capture.sh`, which picks the simulator, sets the
/// language and collects the PNG files.
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["SCREENSHOT_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Set by capture.sh ; French by default.
    private var language: String { ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] ?? "fr" }
    private var region: String { ProcessInfo.processInfo.environment["SCREENSHOT_REGION"] ?? "FR" }

    private var localeArguments: [String] {
        ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_\(region)"]
    }

    /// Pack opened for the "ranges" screenshot : the one enabled for the
    /// region under test, the French one elsewhere.
    private var featuredPack: String {
        switch region {
        case "US": "us.complaints"
        case "ES": "es.cnmc"
        case "DE": "de.bnetza"
        default: "fr.arcep"
        }
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-WildCallScreenshots", "-wildcall.has_seen_onboarding", "YES"] + localeArguments
        app.launch()

        // First launch installs the embedded packs : wait for the list.
        let pack = element(app, "rules.pack.\(featuredPack)")
        XCTAssertTrue(pack.waitForExistence(timeout: 300), "packs never appeared")
        // Let the "preparing the filter" card finish and leave.
        sleep(8)
        capture(app, "01-filters")

        pack.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 20))
        sleep(1)
        capture(app, "02-pack-ranges")
        app.navigationBars.buttons.firstMatch.tap()

        let add = element(app, "rules.add")
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()
        let field = element(app, "addRule.number")
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("0162*")
        sleep(1)
        capture(app, "03-new-rule")
        element(app, "addRule.cancel").tap()

        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(element(app, "status.ready").waitForExistence(timeout: 120), "filter never became ready")
        sleep(1)
        capture(app, "04-settings")
        app.swipeUp(velocity: .slow)
        sleep(1)
        capture(app, "05-packs")
    }

    @MainActor
    func testCaptureIntroduction() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-WildCallScreenshots", "-wildcall.has_seen_onboarding", "NO"] + localeArguments
        app.launch()

        let next = element(app, "onboarding.next")
        XCTAssertTrue(next.waitForExistence(timeout: 60), "introduction never appeared")
        next.tap()
        sleep(1)
        capture(app, "06-intro-wildcards")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let outputDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: outputDirectory.appending(path: "\(name).png"))
        } catch {
            XCTFail("could not write \(name).png: \(error)")
        }
    }
}
