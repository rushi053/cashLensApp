//
//  RuntimeSmokeUITest.swift
//  CashLensUITests
//
//  THROWAWAY runtime smoke test written by the release runtime tester.
//  EXCLUDE THIS FILE FROM THE RELEASE COMMIT — it is not app source.
//
//  Walks: onboarding -> currency picker -> add expense via FAB ->
//  all four tabs -> Activity calendar + search -> Subscriptions ->
//  Manage Budgets (create one) -> paywall (verify StoreKit products
//  loaded) -> dismiss. Includes deliberate ~20s idles on Today,
//  Activity and the paywall so a host-side CPU sampler can hunt for
//  animation/recompute loops. Emits NSLog markers for correlation.
//

import XCTest

final class RuntimeSmokeUITest: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func marker(_ name: String) {
        NSLog("RUNTIME-TEST MARKER: %@", name)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        marker("shot-\(name)")
    }

    private func assertAlive(_ context: String) {
        XCTAssertEqual(app.state, .runningForeground, "App not in foreground at: \(context)")
    }

    @discardableResult
    private func tapElement(_ element: XCUIElement, _ name: String, timeout: TimeInterval = 8) -> Bool {
        let target = element.firstMatch
        guard target.waitForExistence(timeout: timeout) else {
            marker("MISS-\(name)")
            shot("missing-\(name)")
            return false
        }
        if target.isHittable {
            target.tap()
        } else {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        marker("tapped-\(name)")
        return true
    }

    private func idle(_ seconds: TimeInterval, label: String) {
        marker("IDLE-START-\(label)")
        Thread.sleep(forTimeInterval: seconds)
        marker("IDLE-END-\(label)")
        assertAlive("after idle \(label)")
    }

    // MARK: - The walkthrough

    func testFullRuntimeWalkthrough() throws {
        app.launch()
        marker("launched")
        assertAlive("initial launch")

        // ---------- 1. Onboarding (fresh install only) ----------
        let continueButton = app.buttons["Continue"].firstMatch
        if continueButton.waitForExistence(timeout: 10) {
            shot("onboarding-1-welcome")
            continueButton.tap()

            shot("onboarding-2-privacy")
            tapElement(app.buttons["Continue"], "privacy-continue")

            Thread.sleep(forTimeInterval: 1.5)
            shot("onboarding-3-capability")
            tapElement(app.buttons["Continue"], "capability-continue")

            Thread.sleep(forTimeInterval: 1.0)
            shot("onboarding-4-first-expense")
            let amountField = app.textFields.firstMatch
            if amountField.waitForExistence(timeout: 5) {
                amountField.tap()
                amountField.typeText("420")
            }
            let groceriesChip = app.buttons["Groceries"].firstMatch
            if groceriesChip.exists && groceriesChip.isHittable {
                groceriesChip.tap()
            }
            shot("onboarding-4-amount-entered")
            tapElement(app.buttons["Save Expense"], "save-first-expense")

            Thread.sleep(forTimeInterval: 2.0)
            shot("onboarding-5-finish")
            tapElement(app.buttons["Get Started"], "get-started")
        } else {
            marker("no-onboarding-shown")
            shot("no-onboarding")
        }
        assertAlive("after onboarding")

        // ---------- 2. Initial currency picker ----------
        let currencyContinue = app.buttons["Continue"].firstMatch
        if currencyContinue.waitForExistence(timeout: 6) {
            shot("currency-picker")
            currencyContinue.tap()
            marker("currency-picker-dismissed")
        } else {
            marker("no-currency-picker")
        }
        Thread.sleep(forTimeInterval: 1.5)
        shot("today-after-onboarding")
        assertAlive("Today after onboarding")

        let has420 = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '420'")
        ).firstMatch.waitForExistence(timeout: 4)
        marker(has420 ? "first-expense-visible" : "first-expense-NOT-visible")

        // ---------- 3. Idle on Today (loop hunt) ----------
        idle(20, label: "today")
        shot("today-after-idle")

        // ---------- 4. Add an expense via the FAB ----------
        let fabByLabel = app.buttons["Add"].firstMatch
        if fabByLabel.exists && fabByLabel.isHittable {
            fabByLabel.tap()
            marker("fab-tapped-by-label")
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.84)).tap()
            marker("fab-tapped-by-coordinate")
        }
        Thread.sleep(forTimeInterval: 1.5)
        shot("add-expense-sheet")

        let addAmount = app.textFields.firstMatch
        if addAmount.waitForExistence(timeout: 5) {
            addAmount.tap()
            addAmount.typeText("129")
        }
        // Title is REQUIRED in the real add sheet (unlike onboarding).
        let titleField = app.textFields["What was it for?"].firstMatch
        if titleField.waitForExistence(timeout: 4) {
            titleField.tap()
            titleField.typeText("Coffee")
        }
        shot("add-expense-filled")
        tapElement(app.buttons["Add Expense"], "add-expense-save")
        Thread.sleep(forTimeInterval: 2.0)
        // Verify sheet is gone: the Add Expense button should vanish.
        let sheetGone = !app.buttons["Add Expense"].firstMatch.exists
        marker(sheetGone ? "add-sheet-dismissed" : "add-sheet-STILL-OPEN")
        if !sheetGone {
            // Close it so the rest of the walk isn't blocked.
            tapElement(app.buttons["Close"], "add-sheet-close", timeout: 3)
            Thread.sleep(forTimeInterval: 1.0)
        }
        shot("today-after-second-expense")
        assertAlive("after adding second expense")

        // ---------- 5. Activity tab: calendar + search ----------
        tapElement(app.buttons["Activity"], "tab-activity")
        Thread.sleep(forTimeInterval: 1.0)
        shot("activity-list")
        idle(20, label: "activity")

        // The header segmented toggle exposes "Calendar view" / "List view".
        tapElement(app.buttons["Calendar view"], "calendar-toggle", timeout: 5)
        Thread.sleep(forTimeInterval: 1.0)
        shot("activity-calendar")
        tapElement(app.buttons["List view"], "list-toggle", timeout: 5)
        Thread.sleep(forTimeInterval: 0.6)

        tapElement(app.buttons["Search expenses"], "activity-search", timeout: 5)
        Thread.sleep(forTimeInterval: 0.8)
        let searchField = app.searchFields.firstMatch.exists
            ? app.searchFields.firstMatch
            : app.textFields.matching(
                NSPredicate(format: "placeholderValue CONTAINS[c] 'search'")
              ).firstMatch
        if searchField.waitForExistence(timeout: 4) {
            searchField.tap()
            searchField.typeText("Coffee")
            Thread.sleep(forTimeInterval: 1.0)
            shot("activity-search-results")
        } else {
            marker("MISS-search-field")
            shot("missing-search-field")
        }
        // The search screen is a sheet with a circular X labelled "Close".
        tapElement(app.buttons["Close"], "search-close", timeout: 4)
        Thread.sleep(forTimeInterval: 1.0)
        assertAlive("after Activity search")

        // ---------- 6. Insights tab ----------
        // Safety: if any sheet is still up, close it before tab hopping.
        if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.0)
            marker("closed-lingering-sheet")
        }
        tapElement(app.buttons["Insights"], "tab-insights")
        Thread.sleep(forTimeInterval: 1.5)
        shot("insights")
        assertAlive("Insights tab")

        // ---------- 7. You tab: Subscriptions ----------
        tapElement(app.buttons["You"], "tab-you")
        Thread.sleep(forTimeInterval: 1.0)
        shot("you-tab")

        if tapElement(app.staticTexts["Subscriptions"], "row-subscriptions", timeout: 5) {
            Thread.sleep(forTimeInterval: 1.2)
            shot("subscriptions")
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.exists {
                backButton.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        assertAlive("after Subscriptions")

        // ---------- 8. Manage Budgets: create a budget ----------
        if !app.staticTexts["Manage Budgets"].firstMatch.exists {
            app.swipeUp()
        }
        if tapElement(app.staticTexts["Manage Budgets"], "row-manage-budgets", timeout: 5) {
            Thread.sleep(forTimeInterval: 1.0)
            shot("budget-list")
            if tapElement(app.buttons["Add budget"], "add-budget", timeout: 5) {
                Thread.sleep(forTimeInterval: 1.0)
                shot("budget-setup")
                let budgetAmount = app.textFields.firstMatch
                if budgetAmount.waitForExistence(timeout: 4) {
                    budgetAmount.tap()
                    budgetAmount.typeText("5000")
                }
                tapElement(app.buttons["Create Budget"], "create-budget", timeout: 5)
                Thread.sleep(forTimeInterval: 1.5)
                shot("budget-created")
            }
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.exists { backButton.tap() }
            Thread.sleep(forTimeInterval: 0.8)
        }
        assertAlive("after budgets")

        // ---------- 9. Paywall from You tab ----------
        var upgradeFound = app.buttons["Upgrade to Pro"].firstMatch.exists
            || app.staticTexts["Upgrade to Pro"].firstMatch.exists
        var swipes = 0
        while !upgradeFound && swipes < 4 {
            app.swipeUp()
            swipes += 1
            upgradeFound = app.buttons["Upgrade to Pro"].firstMatch.exists
                || app.staticTexts["Upgrade to Pro"].firstMatch.exists
        }
        let upgrade = app.buttons["Upgrade to Pro"].firstMatch.exists
            ? app.buttons["Upgrade to Pro"]
            : app.staticTexts["Upgrade to Pro"]
        if tapElement(upgrade, "upgrade-to-pro", timeout: 5) {
            let pricePredicate = NSPredicate(
                format: "label CONTAINS '₹' OR label CONTAINS '$' OR label CONTAINS '€' OR label CONTAINS '£'"
            )
            let priceText = app.staticTexts.matching(pricePredicate).firstMatch
            let productsLoaded = priceText.waitForExistence(timeout: 20)
            marker(productsLoaded ? "paywall-products-LOADED" : "paywall-products-MISSING")
            shot("paywall")
            XCTAssertTrue(productsLoaded, "Paywall did not show any priced plan within 20s — StoreKit config may not be wired")

            idle(20, label: "paywall")
            shot("paywall-after-idle")

            let closeCandidates = ["Close", "xmark", "Dismiss", "Maybe Later", "Not now", "Not Now"]
            var dismissed = false
            for name in closeCandidates where app.buttons[name].firstMatch.exists {
                app.buttons[name].firstMatch.tap()
                dismissed = true
                break
            }
            if !dismissed {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
            Thread.sleep(forTimeInterval: 1.2)
            shot("after-paywall-dismiss")
        }
        assertAlive("after paywall")

        // ---------- 10. Back to Today, final state ----------
        tapElement(app.buttons["Today"], "tab-today-final")
        Thread.sleep(forTimeInterval: 1.0)
        shot("final-today")
        assertAlive("final state")
        marker("walkthrough-complete")
    }

    // MARK: - Secondary flows: Subscriptions, Budgets, paywall plan cards

    func testSubscriptionsBudgetsAndPaywallPlans() throws {
        app.launch()
        marker("launched-secondary")

        // Skip onboarding fast (fresh clone every run).
        if app.buttons["Skip"].firstMatch.waitForExistence(timeout: 8) {
            app.buttons["Skip"].firstMatch.tap()
        }
        let currencyContinue = app.buttons["Continue"].firstMatch
        if currencyContinue.waitForExistence(timeout: 6) {
            currencyContinue.tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        assertAlive("after skip onboarding")

        // ---------- You tab ----------
        tapElement(app.buttons["You"], "tab-you")
        Thread.sleep(forTimeInterval: 1.0)

        // ---------- Subscriptions ----------
        var subsRow = app.staticTexts["Subscriptions"].firstMatch
        var attempts = 0
        while !(subsRow.exists && subsRow.isHittable) && attempts < 5 {
            app.swipeUp()
            attempts += 1
            subsRow = app.staticTexts["Subscriptions"].firstMatch
        }
        if subsRow.exists && subsRow.isHittable {
            subsRow.tap()
            marker("opened-subscriptions")
            Thread.sleep(forTimeInterval: 1.5)
            shot("subscriptions-screen")
            assertAlive("Subscriptions screen")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable {
                back.tap()
            } else if app.buttons["Close"].firstMatch.exists {
                app.buttons["Close"].firstMatch.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            }
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            marker("MISS-subscriptions-row")
            shot("missing-subscriptions-row")
        }
        assertAlive("after Subscriptions")

        // ---------- Manage Budgets ----------
        var budgetsRow = app.staticTexts["Manage Budgets"].firstMatch
        attempts = 0
        while !(budgetsRow.exists && budgetsRow.isHittable) && attempts < 5 {
            app.swipeUp()
            attempts += 1
            budgetsRow = app.staticTexts["Manage Budgets"].firstMatch
        }
        if budgetsRow.exists && budgetsRow.isHittable {
            budgetsRow.tap()
            marker("opened-budgets")
            Thread.sleep(forTimeInterval: 1.5)
            shot("budget-list")
            if tapElement(app.buttons["Add budget"], "add-budget", timeout: 6) {
                Thread.sleep(forTimeInterval: 1.2)
                shot("budget-setup")
                let budgetAmount = app.textFields.firstMatch
                if budgetAmount.waitForExistence(timeout: 4) {
                    budgetAmount.tap()
                    budgetAmount.typeText("5000")
                }
                shot("budget-setup-filled")
                tapElement(app.buttons["Create Budget"], "create-budget", timeout: 6)
                Thread.sleep(forTimeInterval: 1.5)
                shot("budget-created")
                assertAlive("after creating budget")
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() }
            if app.buttons["Close"].firstMatch.exists {
                app.buttons["Close"].firstMatch.tap()
            }
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            marker("MISS-budgets-row")
            shot("missing-budgets-row")
        }
        assertAlive("after budgets")

        // ---------- Paywall plan cards ----------
        var upgrade = app.staticTexts["Upgrade to Pro"].firstMatch
        attempts = 0
        while !(upgrade.exists && upgrade.isHittable) && attempts < 5 {
            app.swipeDown()
            attempts += 1
            upgrade = app.staticTexts["Upgrade to Pro"].firstMatch
        }
        if upgrade.exists && upgrade.isHittable {
            upgrade.tap()
            marker("opened-paywall")
            Thread.sleep(forTimeInterval: 3.0) // give StoreKit time
            // Scroll to plan cards.
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.0)
            shot("paywall-plan-cards")
            // Look for real price strings ("/ year", "/ month", currency).
            let pricePredicate = NSPredicate(
                format: "label CONTAINS '₹' OR label CONTAINS '$' OR label CONTAINS '/ year' OR label CONTAINS '/ month'"
            )
            let priceCount = app.staticTexts.matching(pricePredicate).count
            marker("paywall-price-elements-\(priceCount)")
            XCTAssertGreaterThan(priceCount, 0, "No priced plan cards on paywall")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.8)
            shot("paywall-plan-cards-bottom")
        } else {
            marker("MISS-upgrade-row")
            shot("missing-upgrade-row")
        }
        assertAlive("secondary flows complete")
        marker("secondary-complete")
    }

    // MARK: - Budgets + cold-launch persistence

    func testBudgetCreationAndColdLaunchPersistence() throws {
        app.launch()
        marker("launched-tertiary")

        if app.buttons["Skip"].firstMatch.waitForExistence(timeout: 8) {
            app.buttons["Skip"].firstMatch.tap()
        }
        let currencyContinue = app.buttons["Continue"].firstMatch
        if currencyContinue.waitForExistence(timeout: 6) {
            currencyContinue.tap()
        }
        Thread.sleep(forTimeInterval: 1.5)

        // Add one expense so persistence has something to verify.
        let fab = app.buttons["Add"].firstMatch
        if fab.exists && fab.isHittable {
            fab.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.84)).tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        let amount = app.textFields.firstMatch
        if amount.waitForExistence(timeout: 5) {
            amount.tap()
            amount.typeText("777")
        }
        let titleField = app.textFields["What was it for?"].firstMatch
        if titleField.waitForExistence(timeout: 4) {
            titleField.tap()
            titleField.typeText("PersistCheck")
        }
        tapElement(app.buttons["Add Expense"], "persist-expense-save")
        Thread.sleep(forTimeInterval: 2.0)
        assertAlive("after persist expense save")

        // ---------- Manage Budgets directly (no Subscriptions detour) ----------
        tapElement(app.buttons["You"], "tab-you")
        Thread.sleep(forTimeInterval: 1.0)
        var budgetsRow = app.staticTexts["Manage Budgets"].firstMatch
        var attempts = 0
        while !(budgetsRow.exists && budgetsRow.isHittable) && attempts < 6 {
            app.swipeUp()
            attempts += 1
            budgetsRow = app.staticTexts["Manage Budgets"].firstMatch
        }
        if budgetsRow.exists && budgetsRow.isHittable {
            budgetsRow.tap()
            marker("opened-budgets")
            Thread.sleep(forTimeInterval: 1.5)
            shot("budget-list")
            if tapElement(app.buttons["Add budget"], "add-budget", timeout: 6) {
                Thread.sleep(forTimeInterval: 1.2)
                shot("budget-setup")
                let budgetAmount = app.textFields.firstMatch
                if budgetAmount.waitForExistence(timeout: 4) {
                    budgetAmount.tap()
                    budgetAmount.typeText("5000")
                }
                // Budget also requires a NAME (isValid checks both).
                let budgetName = app.textFields["e.g. Monthly Spending"].firstMatch
                if budgetName.waitForExistence(timeout: 4) {
                    budgetName.tap()
                    budgetName.typeText("Monthly Cap")
                }
                shot("budget-setup-filled")
                tapElement(app.buttons["Create Budget"], "create-budget", timeout: 6)
                Thread.sleep(forTimeInterval: 2.0)
                shot("budget-created")
                assertAlive("after creating budget")
            }
            // Budgets may be a sheet — drag it down, then also try nav back.
            if app.buttons["Close"].firstMatch.exists {
                app.buttons["Close"].firstMatch.tap()
            } else {
                let back = app.navigationBars.buttons.element(boundBy: 0)
                if back.exists && back.isHittable {
                    back.tap()
                } else {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
                        .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
                }
            }
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            marker("MISS-budgets-row")
            shot("missing-budgets-row")
        }
        assertAlive("after budgets")

        // ---------- Cold-launch persistence x3 ----------
        for i in 1...3 {
            app.terminate()
            Thread.sleep(forTimeInterval: 1.0)
            let start = Date()
            app.launch()
            let launched = app.buttons["Today"].firstMatch.waitForExistence(timeout: 15)
            let elapsed = Date().timeIntervalSince(start)
            marker(String(format: "cold-launch-%d-%.2fs-%@", i, elapsed, launched ? "ok" : "NO-TAB-BAR"))
            XCTAssertTrue(launched, "Cold launch \(i): tab bar never appeared")
            let dataThere = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '777'")
            ).firstMatch.waitForExistence(timeout: 6)
            marker("cold-launch-\(i)-data-\(dataThere ? "persisted" : "MISSING")")
            XCTAssertTrue(dataThere, "Cold launch \(i): expense data missing")
            shot("cold-launch-\(i)")
            assertAlive("cold launch \(i)")
        }
        marker("tertiary-complete")
    }

    // MARK: - Focused paywall pricing check (needs StoreKit config test plan)

    func testPaywallProductsLoad() throws {
        app.launch()
        if app.buttons["Skip"].firstMatch.waitForExistence(timeout: 8) {
            app.buttons["Skip"].firstMatch.tap()
        }
        let currencyContinue = app.buttons["Continue"].firstMatch
        if currencyContinue.waitForExistence(timeout: 6) {
            currencyContinue.tap()
        }
        Thread.sleep(forTimeInterval: 1.5)

        tapElement(app.buttons["You"], "tab-you")
        Thread.sleep(forTimeInterval: 1.0)
        // The Upgrade to Pro card is at the top of You — no scrolling.
        tapElement(app.staticTexts["Upgrade to Pro"], "upgrade-card", timeout: 6)
        Thread.sleep(forTimeInterval: 4.0) // StoreKit load time
        shot("paywall-top")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.0)
        shot("paywall-plans")

        let yearOrMonth = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '/ year' OR label CONTAINS '/ month' OR label CONTAINS 'one-time'")
        ).count
        let loadError = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Unable to load pricing'")
        ).firstMatch.exists
        marker("paywall-priced-elements-\(yearOrMonth)-loadError-\(loadError)")
        XCTAssertFalse(loadError, "Paywall shows 'Unable to load pricing' — StoreKit config not applied or products failed to load")
        XCTAssertGreaterThan(yearOrMonth, 0, "No priced plan cards found on paywall")
        assertAlive("paywall pricing check")
    }

    // MARK: - Deep link: cashlens://add-expense

    func testDeepLinkOpensAddSheet() throws {
        app.launch()
        if app.buttons["Skip"].firstMatch.waitForExistence(timeout: 8) {
            app.buttons["Skip"].firstMatch.tap()
        }
        let currencyContinue = app.buttons["Continue"].firstMatch
        if currencyContinue.waitForExistence(timeout: 6) {
            currencyContinue.tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        assertAlive("before deep link")

        // Cold path: terminate, then open the widget deep link.
        app.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        XCUIDevice.shared.system.open(URL(string: "cashlens://add-expense")!)
        Thread.sleep(forTimeInterval: 3.0)
        shot("deeplink-cold")
        let addSheetVisible = app.staticTexts["ENTER AMOUNT"].firstMatch.waitForExistence(timeout: 8)
            || app.staticTexts["Add New"].firstMatch.exists
        marker(addSheetVisible ? "deeplink-cold-add-sheet-OK" : "deeplink-cold-add-sheet-MISSING")
        XCTAssertTrue(addSheetVisible, "cashlens://add-expense (cold launch) did not open the add sheet")
        assertAlive("after cold deep link")

        // Warm path: dismiss, background stays running, deep link again.
        if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        XCUIDevice.shared.system.open(URL(string: "cashlens://add-expense")!)
        Thread.sleep(forTimeInterval: 2.5)
        shot("deeplink-warm")
        let warmVisible = app.staticTexts["ENTER AMOUNT"].firstMatch.waitForExistence(timeout: 8)
            || app.staticTexts["Add New"].firstMatch.exists
        marker(warmVisible ? "deeplink-warm-add-sheet-OK" : "deeplink-warm-add-sheet-MISSING")
        XCTAssertTrue(warmVisible, "cashlens://add-expense (warm, from background) did not open the add sheet")
        assertAlive("after warm deep link")
    }
}
