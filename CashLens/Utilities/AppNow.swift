import Foundation

/// The instant the app treats as "now".
///
/// Release builds return `Date()` and nothing else. A Debug promo
/// recording can freeze it with `-demoDate` (`PromoDemo`) so
/// "Yesterday", "this month" and the days-left count stay identical
/// between takes.
enum AppNow {
    static var date: Date {
        #if DEBUG
        if let frozen = PromoDemo.frozenNow { return frozen }
        #endif
        return Date()
    }
}
