import CoreData

extension BudgetEntity {
    func toBudget() -> Budget {
        let categoryFilter: Budget.CategoryFilter
        switch categoryFilterType ?? "overall" {
        case "default":
            categoryFilter = .defaultCategory(categoryFilterDefaultRaw ?? "Food")
        case "custom":
            categoryFilter = .customCategory(categoryFilterCustomId ?? UUID())
        default:
            categoryFilter = .overall
        }

        let percentages: [Double]
        if let stored = alertAtPercentages as? [Double], !stored.isEmpty {
            percentages = stored
        } else {
            percentages = Budget.defaultAlertPercentages
        }

        return Budget(
            id: id ?? UUID(),
            name: name ?? "Budget",
            amount: amount,
            period: Budget.Period(rawValue: period ?? "Monthly") ?? .monthly,
            categoryFilter: categoryFilter,
            alertAtPercentages: percentages,
            isActive: isActive,
            createdAt: createdAt ?? Date()
        )
    }

    @discardableResult
    static func fromBudget(_ budget: Budget, context: NSManagedObjectContext) -> BudgetEntity {
        let entity = BudgetEntity(context: context)
        entity.id = budget.id
        entity.name = budget.name
        entity.amount = budget.amount
        entity.period = budget.period.rawValue
        entity.isActive = budget.isActive
        entity.createdAt = budget.createdAt
        entity.alertAtPercentages = budget.alertAtPercentages as NSArray

        switch budget.categoryFilter {
        case .overall:
            entity.categoryFilterType = "overall"
            entity.categoryFilterDefaultRaw = nil
            entity.categoryFilterCustomId = nil
        case .defaultCategory(let raw):
            entity.categoryFilterType = "default"
            entity.categoryFilterDefaultRaw = raw
            entity.categoryFilterCustomId = nil
        case .customCategory(let uuid):
            entity.categoryFilterType = "custom"
            entity.categoryFilterDefaultRaw = nil
            entity.categoryFilterCustomId = uuid
        }

        return entity
    }

    func updateFromBudget(_ budget: Budget) {
        name = budget.name
        amount = budget.amount
        period = budget.period.rawValue
        isActive = budget.isActive
        alertAtPercentages = budget.alertAtPercentages as NSArray

        switch budget.categoryFilter {
        case .overall:
            categoryFilterType = "overall"
            categoryFilterDefaultRaw = nil
            categoryFilterCustomId = nil
        case .defaultCategory(let raw):
            categoryFilterType = "default"
            categoryFilterDefaultRaw = raw
            categoryFilterCustomId = nil
        case .customCategory(let uuid):
            categoryFilterType = "custom"
            categoryFilterDefaultRaw = nil
            categoryFilterCustomId = uuid
        }
    }
}

extension Collection where Element == BudgetEntity {
    func toBudgets() -> [Budget] {
        map { $0.toBudget() }
    }
}
