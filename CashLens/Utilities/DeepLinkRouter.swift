import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    
    @Published var route: DeepLinkRoute? = nil
    
    private init() {}
    
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let routeType = userInfo[NotificationUserInfoKeys.route] as? String else { return }
        
        switch routeType {
        case NotificationRouteTypes.allExpenses:
            let start = (userInfo[NotificationUserInfoKeys.rangeStart] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            let end = (userInfo[NotificationUserInfoKeys.rangeEnd] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            
            route = .allExpenses(
                AllExpensesInitialFilter(
                    useDateRangeFilter: start != nil && end != nil,
                    rangeStartDate: start,
                    rangeEndDate: end,
                    filterCategoryRawValue: userInfo[NotificationUserInfoKeys.categoryRaw] as? String,
                    filterCustomCategoryId: (userInfo[NotificationUserInfoKeys.customCategoryId] as? String).flatMap(UUID.init(uuidString:)),
                    showOnlySubscriptions: (userInfo[NotificationUserInfoKeys.showOnlySubscriptions] as? Bool) ?? false
                )
            )
        case NotificationRouteTypes.export:
            route = .export
        default:
            break
        }
    }
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
    
    var id: String {
        switch self {
        case .allExpenses(let f): return "allExpenses:\(f.id.uuidString)"
        case .export: return "export"
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


