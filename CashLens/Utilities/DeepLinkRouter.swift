import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    
    @Published var route: DeepLinkRoute? = nil

    /// SECURITY: SwiftUI sheets present at the window level — *above*
    /// the App Lock overlay ZStack. Assigning `route` while locked
    /// would therefore surface expense data (All Expenses, Export)
    /// without authentication. Routes arriving while locked are
    /// parked here and flushed by `flushPendingRoute()` when
    /// `AppLockManager` posts `.appDidUnlock`.
    private var pendingRouteWhileLocked: DeepLinkRoute? = nil

    private init() {}

    /// Single choke point for every route assignment so the App Lock
    /// deferral can't be bypassed by a future entry point.
    private func setRoute(_ newRoute: DeepLinkRoute) {
        if AppLockManager.shared.isLocked {
            pendingRouteWhileLocked = newRoute
        } else {
            route = newRoute
        }
    }

    /// Called (via `.appDidUnlock`) right after a successful unlock.
    func flushPendingRoute() {
        guard let pending = pendingRouteWhileLocked else { return }
        pendingRouteWhileLocked = nil
        route = pending
    }
    
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let routeType = userInfo[NotificationUserInfoKeys.route] as? String else { return }
        
        switch routeType {
        case NotificationRouteTypes.allExpenses:
            let start = (userInfo[NotificationUserInfoKeys.rangeStart] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            let end = (userInfo[NotificationUserInfoKeys.rangeEnd] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            
            setRoute(.allExpenses(
                AllExpensesInitialFilter(
                    useDateRangeFilter: start != nil && end != nil,
                    rangeStartDate: start,
                    rangeEndDate: end,
                    filterCategoryRawValue: userInfo[NotificationUserInfoKeys.categoryRaw] as? String,
                    filterCustomCategoryId: (userInfo[NotificationUserInfoKeys.customCategoryId] as? String).flatMap(UUID.init(uuidString:)),
                    showOnlySubscriptions: (userInfo[NotificationUserInfoKeys.showOnlySubscriptions] as? Bool) ?? false
                )
            ))
        case NotificationRouteTypes.export:
            setRoute(.export)
        default:
            break
        }
    }

    /// Handle a `cashlens://` URL (currently only the Quick Log
    /// widget's "+" button → add-expense sheet). Unknown hosts are
    /// ignored so a stale widget from a future app version can't
    /// crash the router.
    func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == DeepLinkURLs.scheme else { return }
        switch url.host?.lowercased() {
        case DeepLinkURLs.addExpenseHost:
            setRoute(.addExpense)
        default:
            break
        }
    }
}

/// URL-scheme vocabulary shared by the router and the widget's Link
/// destinations. The scheme is registered in `CashLens-Info.plist`
/// (CFBundleURLTypes).
enum DeepLinkURLs {
    static let scheme = "cashlens"
    static let addExpenseHost = "add-expense"
    static var addExpense: URL { URL(string: "\(scheme)://\(addExpenseHost)")! }
}

enum NotificationUserInfoKeys {
    static let route = "route"
    static let rangeStart = "rangeStart"
    static let rangeEnd = "rangeEnd"
    static let categoryRaw = "categoryRaw"
    static let customCategoryId = "customCategoryId"
    static let showOnlySubscriptions = "showOnlySubscriptions"
}

enum NotificationRouteTypes {
    static let allExpenses = "allExpenses"
    static let export = "export"
}

enum DeepLinkRoute: Identifiable, Equatable {
    case allExpenses(AllExpensesInitialFilter)
    case export
    case addExpense
    
    var id: String {
        switch self {
        case .allExpenses(let f): return "allExpenses:\(f.id.uuidString)"
        case .export: return "export"
        case .addExpense: return "addExpense"
        }
    }
}

struct AllExpensesInitialFilter: Identifiable, Equatable {
    let id = UUID()
    let useDateRangeFilter: Bool
    let rangeStartDate: Date?
    let rangeEndDate: Date?
    let filterCategoryRawValue: String?
    let filterCustomCategoryId: UUID?
    let showOnlySubscriptions: Bool
}


