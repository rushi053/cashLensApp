//
//  PolishWalkUITests.swift
//  CashLensUITests
//
//  Deeper screenshot walk than `ScreenshotSuiteUITests`: every tab at
//  the top and scrolled, the inline / sheet expense editor, calendar and
//  selection modes in Activity, the budget flow, and each settings
//  sub-screen. Meant for visual QA across devices and iPhone Duo poses,
//  not for the App Store set.
//
//  Runs on Debug builds only in practice: it relies on the
//  `-CLSeedExpenses <n>` launch argument (`DebugExpenseSeeder`) to fill
//  the store so lists, charts and grids render with realistic data.
//  Seeded rows are marked and can be removed from Diagnostics.
//
//  Environment (forwarded by `xcodebuild` from `TEST_RUNNER_*`):
//    CL_DEVICE_SLUG, CL_SCREENSHOT_DIR — as in ScreenshotSuiteUITests.
//    CL_POSE_SLUG — optional label appended to every file name
//                   (e.g. "half") so Duo poses don't overwrite each other.
//    CL_SEED_COUNT — number of seeded expenses (default 300); use a few
//                    thousand to profile scrolling and tab switches.
//
//  Every step is best-effort: a missing element logs and moves on, so one
//  renamed button never costs the rest of the walk.
//

import XCTest
import UIKit

final class PolishWalkUITests: XCTestCase {

    private var app: XCUIApplication!
    private var deviceSlug = "unknown-device"
    private var poseSlug = ""
    private var screenshotDirectory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        deviceSlug = Self.slug(env["CL_DEVICE_SLUG"] ?? UIDevice.current.name)
        poseSlug = Self.slug(env["CL_POSE_SLUG"] ?? "")
        if let dir = env["CL_SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            screenshotDirectory = url
        }
        app = XCUIApplication()
        let seedCount = Int(env["CL_SEED_COUNT"] ?? "") ?? 300
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            // Also mark the install as launched: on a never-launched
            // install `ExpenseViewModel.checkFirstLaunch` resets the
            // in-memory `hasShownCurrencyPicker` flag regardless of the
            // argument-domain override, and the Currency sheet then
            // covers every screenshot of the walk.
            "-hasLaunchedBefore", "YES",
            "-hasShownCurrencyPicker", "YES",
            "-hasAutoShownPaywall", "YES",
            "-CLSeedExpenses", String(seedCount)
        ]
    }

    // MARK: - Walk

    /// Activity calendar mode on its own: month, the default day, a
    /// tapped row (inline editor on regular width, sheet on compact) and
    /// the return to the day. Fast enough to repeat per Duo pose.
    @MainActor
    func testCalendarMode() throws {
        app.launch()
        guard tab("Activity").waitForExistence(timeout: 20) else {
            XCTFail("Tab shell did not appear"); return
        }
        settle(2.0)
        selectTab("Activity"); settle(1.5)
        guard tapFirst(["Calendar view"], timeout: 3) else {
            XCTFail("Calendar toggle not found"); return
        }
        settle(1.5); shot("calendar-day")
        // Pick a day that has spending: cells carry their compact total
        // ("₹12.0k" / "$494"); expense rows always show decimals.
        let dayCell = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'transaction'"))
            .allElementsBoundByIndex
            .filter { $0.isHittable }
            .first // not .last: that is usually today, preselected, so a tap deselects it
        guard let dayCell else { XCTFail("No day with expenses"); return }
        dayCell.tap(); settle(1.2)
        shot("calendar-day-picked")
        // Then a row of that day — on regular width it sits in the
        // trailing pane, on compact it is stacked below the grid.
        func dayRow() -> XCUIElement? {
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS '.' AND (label CONTAINS '₹' OR label CONTAINS '$')"))
                .allElementsBoundByIndex
                .filter { $0.isHittable && !$0.label.lowercased().contains("transaction") }
                .first
        }
        var row = dayRow()
        if row == nil { app.swipeUp(); settle(1.0); row = dayRow() }
        guard let row else { XCTFail("No expense row for the picked day"); return }
        let rowLabel = row.label
        row.tap(); settle(1.5)
        shot("calendar-editor")
        // Edit the title and save: the day list must show the new value
        // (it once rendered the pre-save snapshot).
        let rowTitle = String(rowLabel.split(separator: ",").first ?? "")
        let titleField = app.textFields.allElementsBoundByIndex.first {
            $0.isHittable && ($0.value as? String) == rowTitle
        }
        guard let titleField else { XCTFail("Editor title field not found"); return }
        titleField.tap()
        titleField.typeText(" Edited\n")
        settle(0.6)
        guard tapFirst(["Update Expense"], timeout: 2) else {
            XCTFail("Update Expense not found"); return
        }
        settle(1.5)
        let edited = app.buttons
            .matching(NSPredicate(format: "label CONTAINS ' Edited'"))
            .firstMatch
        if !edited.exists { app.swipeUp(); settle(1.0) }
        XCTAssertTrue(edited.waitForExistence(timeout: 3), "Day list did not refresh after save")
        shot("calendar-after-save")
    }

    @MainActor
    func testPolishWalk() throws {
        app.launch()
        guard tab("Today").waitForExistence(timeout: 20) else {
            XCTFail("Tab shell did not appear"); return
        }
        settle(2.0)

        // Today
        selectTab("Today"); settle(1.5)
        shot("today-top")
        pageUp(); settle(0.8)
        shot("today-scrolled")
        pageUp(); settle(0.8)
        shot("today-bottom")
        scrollToTop()
        if tapFirst(["Set Budget", "Set a budget", "Budget"]) {
            settle(1.2); shot("budget-setup")
            if tapFirst(["Create Your First Budget", "Add Budget", "New Budget"]) {
                settle(1.2); shot("budget-form"); dismiss()
            }
            dismiss()
        }

        // Activity
        selectTab("Activity"); settle(1.5)
        shot("activity-top")
        if tapFirstExpenseRow() {
            settle(1.5); shot("expense-editor"); dismiss()
        }
        if tapFirst(["Calendar view", "Calendar", "Show calendar"]) {
            settle(1.5); shot("activity-calendar")
            _ = tapFirst(["List view", "List", "Show list"]); settle(0.8)
        }
        if tapFirst(["Select expenses", "Select"]) {
            settle(0.8); shot("activity-select-mode")
            _ = tapFirst(["Exit select mode", "Done", "Cancel"]); settle(0.5)
        }
        if tapFirst(["Search expenses"]) {
            settle(1.0); shot("activity-search"); dismiss()
        }
        pageUp(); settle(0.8)
        shot("activity-scrolled")
        scrollToTop()

        // Insights
        selectTab("Insights"); settle(2.0)
        shot("insights-top")
        if tapFirst(["This Year"]) { settle(1.5); shot("insights-year"); _ = tapFirst(["This Month"]) }
        pageUp(); settle(0.8)
        shot("insights-scrolled")
        pageUp(); settle(0.8)
        shot("insights-bottom")
        pageUp(); settle(0.8)
        shot("insights-bottom-2")
        pageUp(); settle(0.8)
        shot("insights-bottom-3")
        scrollToTop()
        if tapFirst(["By weekday"], scrollPages: 6) { settle(1.2); shot("insights-weekday") }
        if tapFirst(["Top days"]) { settle(1.2); shot("insights-topdays") }
        scrollToTop()

        // Add expense
        if tapFirst(["Add expense", "Log expense"]) {
            settle(1.2); shot("add-expense")
            typeAmount("1250")
            settle(0.6); shot("add-expense-amount")
            if tapFirst(["Manage"]) { settle(1.0); shot("manage-categories"); dismiss() }
            dismiss()
        }

        // You and its sub-screens
        selectTab("You"); settle(1.2)
        shot("you-top")
        pageUp(); settle(0.8)
        shot("you-scrolled")
        pageUp(); settle(0.8)
        shot("you-bottom")
        scrollToTop()

        let subScreens: [(String, [String])] = [
            ("manage-budgets", ["Manage Budgets"]),
            ("categories", ["Categories"]),
            ("subscriptions", ["Subscriptions"]),
            ("default-currency", ["Default Currency"]),
            ("siri-shortcuts", ["Siri & Shortcuts"]),
            ("privacy", ["Privacy"]),
            ("theme", ["Theme & Appearance"]),
            ("app-icon", ["App Icon"]),
            ("export", ["Export Data"]),
            ("import", ["Import Data"]),
            ("notifications", ["Reminders & Insights"]),
            ("support", ["Support the App"]),
            ("about", ["About CashLens"]),
            ("profile-edit", ["Edit name"]),
            ("upgrade", ["Upgrade to Pro"])
        ]
        for (name, labels) in subScreens {
            selectTab("You"); settle(0.6)
            guard scrollAndTap(labels) else {
                log("no entry for \(name)")
                continue
            }
            settle(1.4)
            shot(name)
            pageUp(); settle(0.6)
            shot("\(name)-scrolled")
            dismiss()
            settle(0.6)
        }
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        log("shot \(name)")
        var base = "\(name)-\(deviceSlug)"
        if !poseSlug.isEmpty { base += "-\(poseSlug)" }
        for (index, xcScreen) in XCUIScreen.screens.enumerated() {
            let fileName = xcScreen == XCUIScreen.main ? base : "\(base)-screen\(index)"
            let screenshot = xcScreen.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = fileName
            attachment.lifetime = .keepAlways
            add(attachment)
            if let dir = screenshotDirectory {
                try? screenshot.pngRepresentation.write(
                    to: dir.appendingPathComponent("\(fileName).png"), options: .atomic
                )
            }
        }
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tab(_ name: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[name]
        if inTabBar.exists { return inTabBar }
        let asButton = app.buttons[name]
        if asButton.exists { return asButton.firstMatch }
        let asText = app.staticTexts[name]
        if asText.exists { return asText.firstMatch }
        return inTabBar
    }

    private func selectTab(_ name: String) {
        let element = tab(name)
        guard element.waitForExistence(timeout: 8) else { return }
        element.tap()
    }

    /// Taps the first element whose label matches one of `labels`:
    /// exact match first (buttons, cells, texts), then prefix match on
    /// buttons/cells only — a `CONTAINS` on static texts kept hitting
    /// section eyebrows ("Privacy & Security") and marketing copy
    /// ("PDF reports & more") instead of the row. If the element exists
    /// but is off screen, scrolls up to `scrollPages` pages to reach it.
    @discardableResult
    private func tapFirst(_ labels: [String], timeout: TimeInterval = 1, scrollPages: Int = 0) -> Bool {
        for label in labels {
            let exact = NSPredicate(format: "label ==[c] %@", label)
            let prefix = NSPredicate(format: "label BEGINSWITH[c] %@", label)
            let queries: [XCUIElementQuery] = [
                app.buttons.matching(exact), app.cells.matching(exact), app.staticTexts.matching(exact),
                app.buttons.matching(prefix), app.cells.matching(prefix)
            ]
            for query in queries {
                let element = query.firstMatch
                guard element.waitForExistence(timeout: timeout) else { continue }
                var pages = 0
                while !element.isHittable && pages < scrollPages {
                    pageUp(); settle(0.4); pages += 1
                }
                if element.isHittable {
                    element.tap()
                    return true
                }
            }
        }
        log("tapFirst miss: \(labels.joined(separator: " | "))")
        return false
    }

    /// `tapFirst` with scrolling enabled; resets to the top on failure.
    private func scrollAndTap(_ labels: [String]) -> Bool {
        if tapFirst(labels, timeout: 1, scrollPages: 6) { return true }
        scrollToTop()
        return false
    }

    /// Taps the first expense row in Activity: the top-most hittable
    /// element carrying a currency amount that is not a day-group
    /// header ("8 expenses · ₹3,265.26") or the ledger total.
    private func tapFirstExpenseRow() -> Bool {
        let amount = NSPredicate(
            format: "(label CONTAINS '₹' OR label CONTAINS '$' OR label CONTAINS '€' OR label CONTAINS '£') AND NOT (label CONTAINS[c] 'expense') AND NOT (label CONTAINS[c] 'spent') AND NOT (label CONTAINS '·')"
        )
        let candidates = (app.buttons.matching(amount).allElementsBoundByIndex
            + app.cells.matching(amount).allElementsBoundByIndex
            + app.staticTexts.matching(amount).allElementsBoundByIndex)
            .filter { $0.isHittable }
            .sorted { $0.frame.minY < $1.frame.minY }
        let threshold = app.frame.height * 0.3
        if let row = candidates.first(where: { $0.frame.minY > threshold }) {
            row.tap()
            return true
        }
        return false
    }

    /// Types into the amount field. The simulator usually has the
    /// hardware keyboard attached (no software keys), so this focuses
    /// the field and uses `typeText`, falling back to key taps.
    private func typeAmount(_ digits: String) {
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 1.5) {
            field.tap(); settle(0.4)
            field.typeText(digits)
            return
        }
        for digit in digits {
            let key = app.keys[String(digit)]
            guard key.waitForExistence(timeout: 1) else { return }
            key.tap()
        }
    }

    /// Leaves whatever was just opened. Tries, in order, the frontmost
    /// hittable Close / Done / Cancel / Back button (a stacked sheet
    /// can expose two "Close" buttons — the one later in the hierarchy
    /// belongs to the top sheet), a nav-bar back button, then a
    /// sheet-style drag down. Each attempt is verified: if the tapped
    /// control is still on screen afterwards, the next strategy runs.
    private func dismiss() {
        for label in ["Close", "Done", "Cancel", "Back"] {
            let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
                .allElementsBoundByIndex
                .filter { $0.isHittable }
            guard let button = matches.last else { continue }
            button.tap()
            settle(0.7)
            if !(button.exists && button.isHittable) {
                log("dismiss via \(label)")
                return
            }
        }
        let navBack = app.navigationBars.buttons.element(boundBy: 0)
        if navBack.exists && navBack.isHittable {
            navBack.tap()
            settle(0.6)
            log("dismiss via nav back")
            return
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.1, thenDragTo: end)
        settle(0.7)
        log("dismiss via drag")
    }

    private func log(_ line: String) {
        NSLog("PolishWalk: \(line)")
        guard let dir = screenshotDirectory else { return }
        let url = dir.appendingPathComponent("walk-\(deviceSlug)\(poseSlug.isEmpty ? "" : "-\(poseSlug)").log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func scrollToTop() {
        for _ in 0..<3 { pageDown() }
        settle(0.5)
    }

    /// Page scrolls as explicit drags on the page's scroll element.
    /// `app.swipeUp()` did nothing on the iPhone Duo inner display (book
    /// pose) — see `pageScrollTarget`. x = 0.3 keeps the drag inside the
    /// leading (list) column of the split layouts.
    /// Coordinates derived from `app` resolve on the main (outer) screen,
    /// which is dark while the inner display is active, so drags built
    /// from them never reach the interface. Anchoring the drag to the
    /// largest scrollable element puts it on the screen that element is
    /// actually on.
    private var pageScrollTarget: XCUIElement {
        // Single-screen devices: one root ScrollView per tab, so take it
        // directly. Index-bound queries re-resolve on every read and
        // raise an uncatchable "No matches found for Element at index N"
        // when a slow, data-heavy hierarchy changes between the query
        // and the snapshot (5k-row profiling runs hit this).
        if XCUIScreen.screens.count <= 1 {
            let first = app.scrollViews.firstMatch
            return first.exists ? first : app
        }
        var best: XCUIElement?
        var bestArea: CGFloat = 0
        for query in [app.scrollViews, app.collectionViews, app.tables] {
            for element in query.allElementsBoundByIndex.prefix(8) {
                // `snapshot()` throws (instead of recording a failure)
                // when the element has gone between the query and this
                // read — e.g. iOS 18's legacy tab bar re-laying out —
                // so a stale element is skipped, not fatal.
                guard let snapshot = try? element.snapshot() else { continue }
                let area = snapshot.frame.width * snapshot.frame.height
                if area > bestArea { bestArea = area; best = element }
            }
        }
        return best ?? app
    }

    private func pageUp() {
        let target = pageScrollTarget
        let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15))
        flick(from: start, to: end)
    }

    private func pageDown() {
        let target = pageScrollTarget
        let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85))
        flick(from: start, to: end)
    }

    /// A fast flick, not a press-and-drag: the trend chart's scrubber
    /// claims slow drags that start on it, which froze the Insights walk
    /// at the Trend card.
    private func flick(from start: XCUICoordinate, to end: XCUICoordinate) {
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var out = ""
        var lastDash = false
        for ch in lowered {
            if allowed.contains(ch) { out.append(ch); lastDash = false }
            else if !lastDash && !out.isEmpty { out.append("-"); lastDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }
}
