//
//  ScreenshotSuiteUITests.swift
//  CashLensUITests
//
//  Per-device screenshot walk of the core screens. Replaces the old
//  throwaway `RuntimeSmokeUITest`.
//
//  Every screenshot is attached to the test result as
//  `<screen>-<device>-<orientation>` (for example
//  `today-iphone-18-pro-landscape`). When the `CL_SCREENSHOT_DIR`
//  environment variable is set the same PNG is also written to that
//  directory, so `Scripts/screenshots.sh` can collect a flat folder of
//  images without digging through `.xcresult` bundles.
//
//  Screens covered:
//    today, activity, insights, you, add-expense, paywall, onboarding
//
//  How the run is configured (all optional, all via the test runner's
//  environment — `xcodebuild` forwards any `TEST_RUNNER_*` variable
//  with the prefix stripped):
//
//    CL_DEVICE_SLUG     e.g. "iphone-18-pro". Falls back to a slug of
//                       `UIDevice.current.name`.
//    CL_ORIENTATION     "portrait" (default) or "landscape".
//    CL_SCREENSHOT_DIR  Host directory to also write PNGs into.
//
//  Launch arguments the suite passes to the app:
//
//    -hasCompletedOnboarding YES / -hasShownCurrencyPicker YES
//        Plain `UserDefaults` argument-domain overrides; the app already
//        reads these keys, so onboarding and the first-run currency
//        picker are skipped with zero app-side code.
//    -UITestSeedDemoData YES
//        Contract for the app target: when present, seed the demo
//        dataset (`Marketing/ScreenshotSampleData/`) into the store
//        before the first frame. Until the app implements it the suite
//        falls back to logging a few expenses through the Add Expense
//        sheet so Today / Activity / Insights are never empty.
//    -UITestResetState YES
//        Contract for the app target: wipe persisted data first so the
//        run is deterministic. No fallback; without it the seeded rows
//        accumulate across runs on the same simulator (harmless for
//        screenshots, but reset the simulator if it bothers you).
//

import XCTest
import UIKit

final class ScreenshotSuiteUITests: XCTestCase {

    // MARK: - Configuration

    private enum Screen: String {
        case today, activity, insights, you
        case addExpense = "add-expense"
        case paywall
        case onboarding
    }

    private struct SeedExpense {
        let amount: String
        let title: String
        let category: String
    }

    /// Fallback rows logged through the UI when the app does not honour
    /// `-UITestSeedDemoData`. Kept short: each row costs a few seconds.
    private static let seedExpenses: [SeedExpense] = [
        SeedExpense(amount: "4.80", title: "Flat white", category: "Food & Drinks"),
        SeedExpense(amount: "62.35", title: "Weekly groceries", category: "Groceries"),
        SeedExpense(amount: "18.00", title: "Ride home", category: "Transportation"),
        SeedExpense(amount: "15.99", title: "Streaming", category: "Entertainment")
    ]

    private var app: XCUIApplication!
    private var deviceSlug: String = "unknown-device"
    private var orientationSlug: String = "portrait"
    private var screenshotDirectory: URL?

    override func setUpWithError() throws {
        // Keep walking after a soft miss so one absent element does not
        // cost the whole device run; the screenshots that did work are
        // still attached.
        continueAfterFailure = true

        let env = ProcessInfo.processInfo.environment
        deviceSlug = Self.slug(env["CL_DEVICE_SLUG"] ?? UIDevice.current.name)

        let wantsLandscape = (env["CL_ORIENTATION"] ?? "portrait").lowercased() == "landscape"
        orientationSlug = wantsLandscape ? "landscape" : "portrait"
        XCUIDevice.shared.orientation = wantsLandscape ? .landscapeLeft : .portrait

        if let dir = env["CL_SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            screenshotDirectory = url
        }

        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        // Leave the simulator the way the next destination expects it.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Tests

    /// Today → Add Expense sheet → Activity → Insights → You → Paywall.
    @MainActor
    func testCoreScreens() throws {
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-hasShownCurrencyPicker", "YES",
            "-UITestSeedDemoData", "YES",
            "-UITestResetState", "YES"
        ]
        app.launch()
        XCTAssertTrue(waitForTabBar(), "Main tab shell did not appear after launch")
        settle(1.5)

        if todayLooksEmpty() {
            seedExpensesThroughUI()
        }

        selectTab("Today")
        settle(1.2)
        shot(.today)

        if openAddExpense() {
            settle(1.2)
            shot(.addExpense)
            closeSheet()
            settle(0.8)
        } else {
            XCTFail("Could not open the Add Expense sheet on \(deviceSlug) \(orientationSlug)")
        }

        selectTab("Activity")
        settle(1.2)
        shot(.activity)

        selectTab("Insights")
        settle(1.8) // charts animate in
        shot(.insights)

        selectTab("You")
        settle(1.2)
        shot(.you)

        if openPaywall() {
            // StoreKit (configuration file or sandbox) needs a moment to
            // return prices; a paywall without prices is still a valid
            // layout screenshot, so this is a wait, not an assertion.
            _ = pricedText().waitForExistence(timeout: 12)
            settle(0.8)
            shot(.paywall)
            closeSheet()
            settle(0.8)
        } else if upgradeElement().exists {
            XCTFail("Could not open the paywall from You on \(deviceSlug) \(orientationSlug)")
        } else {
            // No paywall entry means Pro is already active on this
            // simulator (sandbox purchase persisted). Skip, don't fail.
            NSLog("ScreenshotSuite: skipping paywall — no 'Upgrade to Pro' entry on You")
        }
    }

    /// Fresh-install onboarding, first page only.
    @MainActor
    func testOnboardingFirstPage() throws {
        app.launchArguments += [
            "-hasCompletedOnboarding", "NO",
            "-hasShownCurrencyPicker", "NO"
        ]
        app.launch()

        let continueButton = app.buttons["Continue"].firstMatch
        let skipButton = app.buttons["Skip"].firstMatch
        let appeared = continueButton.waitForExistence(timeout: 10) || skipButton.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "Onboarding did not appear with -hasCompletedOnboarding NO")
        settle(1.5) // intro animation
        shot(.onboarding)
    }

    // MARK: - Screenshots

    private func shot(_ screen: Screen) {
        let name = "\(screen.rawValue)-\(deviceSlug)-\(orientationSlug)"
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let dir = screenshotDirectory {
            let url = dir.appendingPathComponent("\(name).png")
            do {
                try screenshot.pngRepresentation.write(to: url, options: .atomic)
            } catch {
                // Attachment already captured; a host-path write failure
                // should not fail the run.
                NSLog("ScreenshotSuite: could not write \(url.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Navigation helpers

    private func waitForTabBar(timeout: TimeInterval = 20) -> Bool {
        // iOS 26 `TabView` on compact width exposes a tab bar; with
        // `.sidebarAdaptable` on regular width the same tabs live in a
        // sidebar. Either way the labels are the same four words, so poll
        // every candidate element type until one shows up.
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if tabElement("Today").exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }

    private func tabElement(_ name: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[name]
        if inTabBar.exists { return inTabBar }
        let asButton = app.buttons[name]
        if asButton.exists { return asButton.firstMatch }
        let asCell = app.cells[name]
        if asCell.exists { return asCell.firstMatch }
        // Sidebar rows sometimes expose only their label.
        let asText = app.staticTexts[name]
        if asText.exists { return asText.firstMatch }
        return inTabBar
    }

    private func selectTab(_ name: String) {
        let element = tabElement(name)
        guard element.waitForExistence(timeout: 8) else {
            XCTFail("Tab '\(name)' not found on \(deviceSlug) \(orientationSlug)")
            return
        }
        tap(element)
    }

    /// Opens the Add Expense sheet via the floating button (compact
    /// width), a toolbar item (regular width after the adaptive shell),
    /// or Today's empty-state CTA. Returns false when none is available.
    @discardableResult
    private func openAddExpense() -> Bool {
        let candidates: [XCUIElement] = [
            app.buttons["Add expense"].firstMatch,
            app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Add expense")).firstMatch,
            app.buttons["Log your first expense"].firstMatch
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: 3) {
            tap(candidate)
            // The sheet header reads "Add New"; the amount field is the
            // first text field on the sheet.
            if app.staticTexts["Add New"].firstMatch.waitForExistence(timeout: 6)
                || app.textFields.firstMatch.waitForExistence(timeout: 2) {
                return true
            }
        }
        return false
    }

    /// Opens the paywall from the You tab. Free users see an "Upgrade to
    /// Pro" card near the top; Pro users have no paywall entry there, in
    /// which case the screenshot is skipped rather than failed.
    @discardableResult
    private func openPaywall() -> Bool {
        var upgrade = upgradeElement()
        var swipes = 0
        while !(upgrade.exists && upgrade.isHittable) && swipes < 4 {
            app.swipeUp()
            swipes += 1
            upgrade = upgradeElement()
        }
        guard upgrade.exists else {
            NSLog("ScreenshotSuite: no 'Upgrade to Pro' entry on You — Pro already active?")
            return false
        }
        tap(upgrade)
        // Paywall is a hero sheet with a lone circular Close button.
        return app.buttons["Close"].firstMatch.waitForExistence(timeout: 8)
    }

    private func upgradeElement() -> XCUIElement {
        let asButton = app.buttons["Upgrade to Pro"].firstMatch
        if asButton.exists { return asButton }
        let containing = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Upgrade to Pro")
        ).firstMatch
        if containing.exists { return containing }
        return app.staticTexts["Upgrade to Pro"].firstMatch
    }

    private func pricedText() -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '/ year' OR label CONTAINS '/ month' OR label CONTAINS 'one-time' OR label CONTAINS '$' OR label CONTAINS '₹' OR label CONTAINS '€' OR label CONTAINS '£'")
        ).firstMatch
    }

    private func closeSheet() {
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 4) {
            tap(close)
            return
        }
        // Last resort: drag the sheet down.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    // MARK: - Demo data fallback

    private func todayLooksEmpty() -> Bool {
        app.buttons["Log your first expense"].firstMatch.waitForExistence(timeout: 3)
    }

    /// Logs `seedExpenses` through the real Add Expense sheet. Slow but
    /// needs no app-side hook; skipped automatically once the app honours
    /// `-UITestSeedDemoData`.
    private func seedExpensesThroughUI() {
        for seed in Self.seedExpenses {
            guard openAddExpense() else {
                NSLog("ScreenshotSuite: seeding stopped — could not open Add Expense")
                return
            }
            settle(0.8)

            let amountField = app.textFields.firstMatch
            if amountField.waitForExistence(timeout: 5) {
                tap(amountField)
                amountField.typeText(seed.amount)
            }

            let titleField = app.textFields["What was it for?"].firstMatch
            if titleField.waitForExistence(timeout: 4) {
                tap(titleField)
                titleField.typeText(seed.title)
            }

            let chip = app.buttons[seed.category].firstMatch
            if chip.exists && chip.isHittable {
                tap(chip)
            }

            let save = app.buttons["Add Expense"].firstMatch
            if save.waitForExistence(timeout: 4) {
                tap(save)
            } else {
                closeSheet()
            }
            settle(1.2)

            // If validation kept the sheet open, close it and move on.
            if app.buttons["Add Expense"].firstMatch.exists {
                closeSheet()
                settle(0.8)
            }
        }
    }

    // MARK: - Low-level helpers

    private func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Fixed pause for animations to finish before a screenshot. Waiting
    /// on element existence is not enough here — the element exists
    /// while it is still sliding in.
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// "iPad Pro 13-inch (M5)" → "ipad-pro-13-inch-m5".
    private static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            let isAlnum = CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
            if isAlnum {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "unknown-device" : out
    }
}
