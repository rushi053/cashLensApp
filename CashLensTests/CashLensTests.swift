//
//  CashLensTests.swift
//  CashLensTests
//
//  Created by Rushiraj Jadeja on 10/03/25.
//

import Foundation
import Testing
@testable import CashLens

struct SubscriptionScheduleTests {

    private let calendar = Calendar.current

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func monthly(start: Date) -> Subscription {
        Subscription(name: "Netflix", amount: 15.99, currency: .usd, startDate: start,
                     frequency: .monthly, category: .entertainment)
    }

    @Test func startTodayBillsOneCycleLater() {
        let now = day(2026, 10, 19, hour: 15)
        let due = Subscription.firstDueDate(startDate: day(2026, 10, 19), frequency: .monthly, now: now)
        #expect(due == day(2026, 11, 19))
    }

    @Test func pastStartIsDueOnNextOccurrenceNotOverdue() {
        let now = day(2026, 10, 19, hour: 15)
        let due = Subscription.firstDueDate(startDate: day(2026, 1, 25), frequency: .monthly, now: now)
        #expect(due == day(2026, 10, 25))
    }

    @Test func pastStartFallingTodayIsDueToday() {
        let now = day(2026, 10, 19, hour: 15)
        let due = Subscription.firstDueDate(startDate: day(2026, 9, 19), frequency: .monthly, now: now)
        #expect(due == day(2026, 10, 19))
    }

    @Test func markPaidAdvancesOneCycleEvenWhenOverdue() {
        var sub = monthly(start: day(2026, 1, 5))
        sub.nextDueDate = day(2026, 8, 5)
        sub.updateNextDueDate()
        #expect(sub.nextDueDate == day(2026, 9, 5))
    }

    @Test func overduePaymentIsLoggedOnItsDueDate() {
        var sub = monthly(start: day(2026, 1, 5))
        sub.nextDueDate = day(2026, 9, 5)
        #expect(sub.toExpense(now: day(2026, 10, 19)).date == day(2026, 9, 5))
    }

    @Test func monthEndAnchorKeepsItsDayAcrossPayments() {
        var sub = monthly(start: day(2026, 1, 31))
        sub.nextDueDate = day(2026, 2, 28)
        sub.updateNextDueDate()
        #expect(sub.nextDueDate == day(2026, 3, 31))
    }

    @Test func daysUntilNextCountsCalendarDays() {
        var sub = monthly(start: day(2026, 1, 5))
        let startOfToday = calendar.startOfDay(for: Date())
        sub.nextDueDate = startOfToday.addingTimeInterval(-60)
        #expect(sub.daysUntilNext == -1)
        sub.nextDueDate = startOfToday.addingTimeInterval(23 * 3600)
        #expect(sub.daysUntilNext == 0)
    }

    @Test func overdueReminderPointsAtNextRenewal() {
        var sub = monthly(start: day(2026, 1, 5))
        sub.nextDueDate = day(2026, 9, 5)
        #expect(sub.reminderTargetDate(now: day(2026, 10, 19)) == day(2026, 11, 5))
    }

    @Test func onTimePaymentIsLoggedNow() {
        var sub = monthly(start: day(2026, 1, 5))
        sub.nextDueDate = day(2026, 10, 19, hour: 18)
        let now = day(2026, 10, 19, hour: 9)
        #expect(sub.toExpense(now: now).date == now)
    }
}

struct MoneyFormatTests {

    private func indiaRegionFormatter(currencyCode: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        MoneyFormat.configure(f, currencyCode: currencyCode)
        return f
    }

    @Test func usdOnIndiaRegionUsesThousandsGrouping() {
        let f = indiaRegionFormatter(currencyCode: "USD")
        #expect(f.string(from: 114_594.13) == "114,594.13")
        #expect(f.string(from: 12_345_678.9) == "12,345,678.90")
    }

    @Test func inrKeepsLakhGrouping() {
        let f = indiaRegionFormatter(currencyCode: "INR")
        #expect(f.string(from: 114_594.13) == "1,14,594.13")
    }

    @Test func roundsHalfAwayFromZeroDespiteBinaryNoise() {
        #expect(MoneyFormat.rounded(3614.225, fractionDigits: 2) == 3614.23)
        #expect(MoneyFormat.rounded(0.125, fractionDigits: 2) == 0.13)
        #expect(MoneyFormat.rounded(-0.125, fractionDigits: 2) == -0.13)
        #expect(MoneyFormat.rounded(1234.5, fractionDigits: 0) == 1235)
        #expect(MoneyFormat.rounded(3614.2249, fractionDigits: 2) == 3614.22)
        #expect(MoneyFormat.rounded(-1e-13, fractionDigits: 2).sign == .plus)
    }

    @Test func summationOrderCannotChangeTheCent() {
        let amounts = [0.1, 0.2, 0.3, 1000.005, 2614.1, 0.01, -0.5]
        let forward = amounts.reduce(0, +)
        let backward = amounts.reversed().reduce(0, +)
        #expect(MoneyFormat.rounded(forward, fractionDigits: 2) == MoneyFormat.rounded(backward, fractionDigits: 2))
    }
}
