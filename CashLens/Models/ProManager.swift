import StoreKit
import SwiftUI

@MainActor
class ProManager: ObservableObject {
    static let shared = ProManager()

    // MARK: - Published State

    @Published private(set) var isPro: Bool = false
    @Published private(set) var proProducts: [Product] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var purchaseError: String?

    // MARK: - Product IDs

    nonisolated static let monthlyID = "com.cashlens.pro.monthly"
    nonisolated static let yearlyID  = "com.cashlens.pro.yearly"
    nonisolated static let lifetimeID = "com.cashlens.pro.lifetime"

    nonisolated static let subscriptionGroupID = "D4E8F2A1"

    nonisolated static let allProIDs: Set<String> = [
        monthlyID, yearlyID, lifetimeID
    ]

    // MARK: - Init

    private init() {
        Task { await loadProducts() }
        Task { await checkEntitlements() }
        listenForTransactions()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await Product.products(for: Self.allProIDs)
            proProducts = sortProducts(loaded)
        } catch {
            print("ProManager: Failed to load products — \(error.localizedDescription)")
        }
    }

    private func sortProducts(_ products: [Product]) -> [Product] {
        let order: [String] = [Self.monthlyID, Self.yearlyID, Self.lifetimeID]
        return products.sorted { a, b in
            (order.firstIndex(of: a.id) ?? Int.max) < (order.firstIndex(of: b.id) ?? Int.max)
        }
    }

    // MARK: - Entitlement Check

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if Self.allProIDs.contains(transaction.productID) {
                    isPro = true
                    return
                }
            }
        }
        isPro = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        purchaseError = nil

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                isPro = true
            case .unverified:
                throw ProPurchaseError.failedVerification
            }
        case .userCancelled:
            throw ProPurchaseError.userCancelled
        case .pending:
            throw ProPurchaseError.pending
        @unknown default:
            throw ProPurchaseError.unknown
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if Self.allProIDs.contains(transaction.productID) {
                        await self?.markPro()
                    }
                }
            }
        }
    }

    private func markPro() {
        isPro = true
    }

    // MARK: - Helpers

    var monthlyProduct: Product? { proProducts.first { $0.id == Self.monthlyID } }
    var yearlyProduct: Product?  { proProducts.first { $0.id == Self.yearlyID } }
    var lifetimeProduct: Product? { proProducts.first { $0.id == Self.lifetimeID } }

    var yearlySavingsPercent: Int {
        guard let monthly = monthlyProduct, let yearly = yearlyProduct else { return 0 }
        let monthlyAnnual = monthly.price * 12
        guard monthlyAnnual > 0 else { return 0 }
        let savings = ((monthlyAnnual - yearly.price) / monthlyAnnual) * 100
        return NSDecimalNumber(decimal: savings).intValue
    }
}

// MARK: - Errors

enum ProPurchaseError: LocalizedError {
    case failedVerification
    case userCancelled
    case pending
    case unknown

    var errorDescription: String? {
        switch self {
        case .failedVerification: return "Purchase verification failed. Please try again."
        case .userCancelled: return nil
        case .pending: return "Purchase is pending approval."
        case .unknown: return "An unknown error occurred."
        }
    }
}
