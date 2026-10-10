import Foundation

extension WrappedStats {
    /// Stable October 2026 story for Xcode previews. Not used at runtime.
    static var preview: WrappedStats {
        WrappedEngine.build(
            expenses: WrappedPreviewData.expenses,
            period: .thisMonth,
            now: WrappedPreviewData.now,
            calendar: WrappedPreviewData.calendar,
            currency: .inr
        )
    }

    static var emptyPreview: WrappedStats {
        WrappedEngine.build(
            expenses: [],
            period: .thisMonth,
            now: WrappedPreviewData.now,
            calendar: WrappedPreviewData.calendar,
            currency: .inr
        )
    }
}

enum WrappedPreviewData {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        calendar.locale = Locale(identifier: "en_IN")
        return calendar
    }

    static var now: Date {
        date(2026, 10, 28, 15)
    }

    static var expenses: [Expense] {
        [
            expense("Swiggy", 800, 10, 2, .food, "UPI"),
            expense("Swiggy", 900, 10, 3, .food, "gpay"),
            expense("swiggy", 700, 10, 4, .food, "PhonePe"),
            expense("Big Bazaar", 2000, 10, 5, .groceries, "cash"),
            expense("Uber", 300, 10, 6, .transportation, "UPI"),
            expense("Amazon", 1500, 10, 10, .shopping, "debit card"),
            expense("DMart", 600, 10, 20, .groceries, nil),
            expense("Rent", 3400, 9, 4, .utilities, nil)
        ]
    }

    private static func expense(
        _ title: String,
        _ amount: Double,
        _ month: Int,
        _ day: Int,
        _ category: Expense.Category,
        _ notes: String?
    ) -> Expense {
        Expense(
            title: title,
            amount: amount,
            currency: .inr,
            date: date(2026, month, day, 12),
            category: category,
            notes: notes
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }
}
