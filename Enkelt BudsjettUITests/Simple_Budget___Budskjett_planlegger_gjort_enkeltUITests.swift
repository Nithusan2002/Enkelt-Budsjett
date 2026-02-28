import XCTest

final class Simple_Budget___Budskjett_planlegger_gjort_enkeltUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["UITEST_IN_MEMORY_STORE", "UITEST_DISABLE_FACEID", "UITEST_SKIP_ONBOARDING"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testMainTabsAreVisible() throws {
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Budsjett"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Investeringer"].exists)
        XCTAssertTrue(app.tabBars.buttons["Oversikt"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tips & Triks"].exists)
        XCTAssertTrue(app.tabBars.buttons["Innstillinger"].exists)
    }

    @MainActor
    func testOnboardingShowsOnFreshLaunchWithoutSkipFlag() throws {
        let onboardingApp = XCUIApplication()
        onboardingApp.launchArguments = ["UITEST_IN_MEMORY_STORE", "UITEST_DISABLE_FACEID"]
        onboardingApp.launch()

        XCTAssertTrue(onboardingApp.navigationBars["Kom i gang"].waitForExistence(timeout: 5))
        XCTAssertTrue(onboardingApp.buttons["Kom i gang"].exists)
    }

    @MainActor
    func testSettingsShowsDataAndDeleteConfirmation() throws {
        app.launch()

        app.tabBars.buttons["Innstillinger"].tap()

        XCTAssertTrue(app.staticTexts["Trygg lagring"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Data"].exists)

        let deleteButton = app.buttons["Slett all data"]
        XCTAssertTrue(deleteButton.exists)
        deleteButton.tap()

        XCTAssertTrue(app.alerts["Slett alle data?"].waitForExistence(timeout: 3))
        app.alerts["Slett alle data?"].buttons["Avbryt"].tap()
    }
}
