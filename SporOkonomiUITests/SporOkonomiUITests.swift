import XCTest

final class SporOkonomiUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["UITEST_IN_MEMORY_STORE", "UITEST_DISABLE_FACEID", "UITEST_SKIP_ONBOARDING"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func launchApp() {
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    private func continuePastAuthChoiceIfNeeded(_ targetApp: XCUIApplication) {
        let continueButton = targetApp.buttons["Fortsett uten konto"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }
    }

    private func openTab(_ title: String) {
        let tabButton = app.tabBars.buttons[title]
        XCTAssertTrue(tabButton.waitForExistence(timeout: 5))
        tabButton.tap()
    }

    @MainActor
    func testMainTabsAreVisible() throws {
        launchApp()

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
        continuePastAuthChoiceIfNeeded(onboardingApp)

        XCTAssertTrue(onboardingApp.otherElements["onboarding.step.intro"].waitForExistence(timeout: 5))
        XCTAssertTrue(onboardingApp.buttons["onboarding.primary_cta"].exists)
        XCTAssertTrue(onboardingApp.buttons["onboarding.secondary_cta"].exists)
    }

    @MainActor
    func testOnboardingFlowCanCompleteUsingCurrentUI() throws {
        let onboardingApp = XCUIApplication()
        onboardingApp.launchArguments = ["UITEST_IN_MEMORY_STORE", "UITEST_DISABLE_FACEID"]
        onboardingApp.launch()
        continuePastAuthChoiceIfNeeded(onboardingApp)

        XCTAssertTrue(onboardingApp.otherElements["onboarding.step.intro"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.primary_cta"].tap()

        XCTAssertTrue(onboardingApp.otherElements["onboarding.step.goals"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.option.spare_mer"].tap()
        onboardingApp.buttons["onboarding.primary_cta"].tap()

        XCTAssertTrue(onboardingApp.otherElements["onboarding.step.income"].waitForExistence(timeout: 5))
        let incomeField = onboardingApp.textFields["onboarding.income_input"]
        XCTAssertTrue(incomeField.waitForExistence(timeout: 5))
        incomeField.tap()
        incomeField.typeText("12000")
        onboardingApp.buttons["onboarding.primary_cta"].tap()

        XCTAssertTrue(onboardingApp.otherElements["onboarding.step.fixed_costs"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.option.husleie"].tap()
        onboardingApp.buttons["onboarding.primary_cta"].tap()

        XCTAssertTrue(onboardingApp.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(onboardingApp.tabBars.buttons["Oversikt"].exists)
    }

    @MainActor
    func testSettingsShowsDataAndDeleteConfirmation() throws {
        launchApp()

        openTab("Innstillinger")

        XCTAssertTrue(app.staticTexts["Trygg lagring"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Data"].exists)

        let deleteButton = app.buttons["Slett all data"]
        XCTAssertTrue(deleteButton.exists)
        deleteButton.tap()

        XCTAssertTrue(app.alerts["Slett alle data?"].waitForExistence(timeout: 3))
        app.alerts["Slett alle data?"].buttons["Avbryt"].tap()
    }

    @MainActor
    func testBudgetShowsEmptyStateOnFreshStore() throws {
        launchApp()
        openTab("Budsjett")

        XCTAssertTrue(app.navigationBars["Budsjett"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sett grenser"].exists)
        XCTAssertTrue(app.staticTexts["Ingen grenser satt ennå. Du kan fortsatt følge forbruket, og legge til grenser når du vil."].exists)
        XCTAssertTrue(app.staticTexts["Legg til første utgift for å starte sporing."].exists)
    }

    @MainActor
    func testInvestmentsShowsEmptyStateOnFreshStore() throws {
        launchApp()
        openTab("Investeringer")

        XCTAssertTrue(app.navigationBars["Investeringer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ingen aktive beholdninger ennå."].exists)
        XCTAssertTrue(app.buttons["Legg til type"].exists)
        XCTAssertTrue(app.staticTexts["Legg inn første snapshot (tar 20 sek)"].exists)
        XCTAssertTrue(app.buttons["Ny innsjekk"].exists)
    }

    @MainActor
    func testOverviewShowsEmptyStatePromptsOnFreshStore() throws {
        launchApp()
        openTab("Oversikt")

        XCTAssertTrue(app.navigationBars["Oversikt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ny innsjekk"].exists)
        XCTAssertTrue(app.staticTexts["Legg inn én måned til for å se utvikling."].exists)
        XCTAssertTrue(app.staticTexts["Legg inn første tall for å se fordeling."].exists)
        XCTAssertTrue(app.staticTexts["Sett formuemål"].exists)
    }
}
