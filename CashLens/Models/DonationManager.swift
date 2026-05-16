import StoreKit
import SwiftUI

@MainActor
class DonationManager: ObservableObject {
    static let shared = DonationManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    
    private let productIdentifiers = [
        "com.cashlens.donation.coffee",
        "com.cashlens.donation.lunch",
        "com.cashlens.donation.fuel"
    ]
    
    private init() {
        Task {
            await loadProducts()
        }
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.recordPurchasedProductID(transaction.productID)
                }
            }
        }
    }

    private func recordPurchasedProductID(_ productID: String) {
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
                await transaction.finish()
                recordPurchasedProductID(transaction.productID)
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
