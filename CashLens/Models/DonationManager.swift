import StoreKit
import SwiftUI

@MainActor
class DonationManager: ObservableObject {
    static let shared = DonationManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()

    // MARK: - Product IDs

    nonisolated static let coffeeID = "com.cashlens.donation.coffee"
    nonisolated static let lunchID  = "com.cashlens.donation.lunch"
    nonisolated static let fuelID   = "com.cashlens.donation.fuel"

    nonisolated static let allDonationIDs: Set<String> = [
        coffeeID, lunchID, fuelID
    ]

    private let productIdentifiers = [
        DonationManager.coffeeID,
        DonationManager.lunchID,
        DonationManager.fuelID
    ]

    private init() {
        Task {
            await loadProducts()
        }
        // NOTE: No `Transaction.updates` iterator here. The app runs a
        // single consolidated listener in `ProManager` which routes
        // donation transactions to `recordPurchasedProductID(_:)` and
        // calls `finish()` exactly once per transaction. Two parallel
        // iterators each finishing everything raced each other — a
        // donation could be finished before it was recorded.
    }

    /// Records a purchased donation product. Called from the direct
    /// purchase path below and from ProManager's consolidated
    /// transaction listener. Idempotent (set insert).
    func recordPurchasedProductID(_ productID: String) {
        purchasedProductIDs.insert(productID)
    }

    func loadProducts() async {
        do {
            let loadedProducts = try await Product.products(for: productIdentifiers)
            products = productIdentifiers.compactMap { id in
                loadedProducts.first(where: { $0.id == id })
            }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                recordPurchasedProductID(transaction.productID)
                await transaction.finish()
                // Apply the donor grandfather policy immediately so the
                // tip earns its Pro grant in this session — previously
                // the scan only ran at launch/restore, so the donor
                // stayed on the free tier until relaunch.
                await ProManager.shared.scanForDonorGrant()
            case .unverified:
                throw StoreError.failedVerification
            }
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }
}

enum StoreError: Error {
    case failedVerification
    case userCancelled
    case pending
    case unknown
} 
