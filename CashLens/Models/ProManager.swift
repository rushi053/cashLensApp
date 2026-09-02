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

    /// Whether this Apple ID can still redeem the 7-day introductory
    /// offer. Intro offers are once-per-Apple-ID, so a re-subscriber
    /// would see "Start free trial" and then a purchase sheet that
    /// charges immediately — a Guideline 2.3.1 problem. Defaults to
    /// `false` so no surface ever promises a trial until StoreKit
    /// confirms eligibility.
    @Published private(set) var isEligibleForIntroOffer: Bool = false

    /// Set when a donor grandfather grant is first applied and the
    /// one-time thank-you hasn't been surfaced yet. The UI presents
    /// the thank-you and the flag is consumed by the sheet binding.
    @Published var pendingDonorThanks: DonorGrant? = nil

    /// Set on foreground when a Pro → free lapse should be answered
    /// with the one-time win-back sheet. Consumed by MainTabView.
    @Published var shouldShowWinBack: Bool = false

    /// True StoreKit entitlement (subscription or lifetime), separate
    /// from the donor grandfather grant. `isPro` is the OR of both.
    private var hasStoreEntitlement = false

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
        Task {
            await loadProducts()
            // Donor grandfathering runs after products load so launch
            // isn't blocked on the (potentially slow) full history scan.
            await scanForDonorGrant()
        }
        Task { await checkEntitlements() }
        listenForTransactions()
        listenForPurchaseIntents()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await Product.products(for: Self.allProIDs)
            proProducts = sortProducts(loaded)
            await refreshIntroOfferEligibility()
        } catch {
            print("ProManager: Failed to load products — \(error.localizedDescription)")
        }
    }

    /// Re-checks intro-offer eligibility against StoreKit. Both
    /// subscriptions live in one group, so eligibility is effectively
    /// group-wide — any eligible product flips the flag. Called after
    /// products load and again when the paywall opens (cheap, and
    /// keeps the copy honest right at the decision moment).
    func refreshIntroOfferEligibility() async {
        var eligible = false
        for product in proProducts {
            guard let subscription = product.subscription,
                  subscription.introductoryOffer != nil else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible = true
                break
            }
        }
        isEligibleForIntroOffer = eligible
    }

    private func sortProducts(_ products: [Product]) -> [Product] {
        let order: [String] = [Self.monthlyID, Self.yearlyID, Self.lifetimeID]
        return products.sorted { a, b in
            (order.firstIndex(of: a.id) ?? Int.max) < (order.firstIndex(of: b.id) ?? Int.max)
        }
    }

    // MARK: - Entitlement Check

    func checkEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if Self.allProIDs.contains(transaction.productID) {
                    entitled = true
                    break
                }
            }
        }
        hasStoreEntitlement = entitled
        recomputeIsPro()
    }

    /// Single point where `isPro` is derived: a live StoreKit
    /// entitlement OR an active donor grandfather grant (founder =
    /// permanent, year = 365 days from the grant date). Also keeps the
    /// persisted last-known-Pro state up to date and flags a lapse for
    /// the win-back flow.
    private func recomputeIsPro() {
        let newValue = hasStoreEntitlement || donorGrantIsActive
        if isPro != newValue {
            isPro = newValue
        }

        let defaults = UserDefaults.standard
        let wasPro = defaults.bool(forKey: UserDefaultsKeys.lastKnownIsPro)
        // A lapse arms the win-back unless an *active* donor grant is
        // covering the user (founders are permanent, so they're never
        // pitched). An **expired** 1-year coffee grant is a genuine
        // lapse — checking `currentDonorGrant == nil` here used to
        // block those users from ever seeing the win-back.
        if wasPro && !newValue && !donorGrantIsActive {
            defaults.set(true, forKey: UserDefaultsKeys.winBackPending)
        }
        defaults.set(newValue, forKey: UserDefaultsKeys.lastKnownIsPro)
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
                hasStoreEntitlement = true
                recomputeIsPro()
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
            // Restores are also how a past donor on a new device gets
            // their grandfather grant — re-scan the full history.
            await scanForDonorGrant()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Transaction Listener (consolidated)

    /// The app's single `Transaction.updates` iterator.
    ///
    /// ProManager and DonationManager used to each run their own
    /// iterator and each called `finish()` on *every* transaction —
    /// whichever listener won the race could finish a donation before
    /// DonationManager recorded it. This one listener routes by
    /// product ID, lets the owning manager process the transaction
    /// first, and finishes each transaction exactly once.
    private func listenForTransactions() {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    if Self.allProIDs.contains(transaction.productID) {
                        // Re-derive Pro from `Transaction.currentEntitlements`
                        // (the source of truth) instead of blindly granting.
                        // `Transaction.updates` also delivers revocations and
                        // refunds — treating those as a grant would re-enable
                        // Pro for a refunded purchase.
                        await self?.checkEntitlements()
                    } else if DonationManager.allDonationIDs.contains(transaction.productID) {
                        // Record BEFORE finishing — finishing first was
                        // the race window that could drop a donation.
                        await DonationManager.shared.recordPurchasedProductID(transaction.productID)
                        // Apply the grandfather policy right away so a
                        // tip earns its grant in-session — previously
                        // the scan only ran at launch/restore, leaving
                        // `isPro` false until the next relaunch.
                        await self?.scanForDonorGrant()
                    }
                    await transaction.finish()
                case .unverified(let transaction, _):
                    // Never grant anything on an unverified result, but
                    // finish it — otherwise StoreKit redelivers it forever
                    // and the queue can wedge.
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Promoted In-App Purchases (App Store product page / search)

    /// Completes purchases a user starts *on the App Store itself* via
    /// promoted In-App Purchases. Without this listener the App Store
    /// refuses to display our promoted products at all (per Apple's
    /// promoted-IAP requirements), so this is what makes the App Store
    /// Connect "Promote" configuration actually take effect.
    ///
    /// Scoped to Pro products only: `purchase()` grants the store
    /// entitlement on success, which would be wrong for a tip-jar
    /// product — and donations are never promoted anyway.
    private func listenForPurchaseIntents() {
        Task { [weak self] in
            for await intent in PurchaseIntent.intents {
                guard let self else { break }
                let product = intent.product
                guard Self.allProIDs.contains(product.id) else { continue }
                do {
                    try await self.purchase(product)
                } catch ProPurchaseError.userCancelled {
                    // User backed out of the sheet — not an error.
                } catch {
                    // Surfaced by the same UI that shows in-app purchase
                    // failures; the user lands in the app either way.
                    self.purchaseError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Donor Grandfathering

    /// The grandfather grant given to users who donated through the
    /// tip jar before Pro existed.
    enum DonorGrant: String, Identifiable {
        /// Any verified $4.99+ tier donation (Lunch / Fuel) →
        /// permanent local Pro.
        case founder
        /// Any smaller donation (Coffee) → 1 year of Pro from the
        /// date the grant was first detected.
        case yearOfPro = "year"

        var id: String { rawValue }
    }

    /// Donation tiers that earn the permanent Founder grant ($4.99+).
    nonisolated static let founderDonationIDs: Set<String> = [
        DonationManager.lunchID, DonationManager.fuelID
    ]

    /// The grant on record, if any (may be expired for `.yearOfPro`).
    var currentDonorGrant: DonorGrant? {
        guard let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.donorGrantType) else { return nil }
        return DonorGrant(rawValue: raw)
    }

    /// Whether the grant on record is currently in force.
    var donorGrantIsActive: Bool {
        guard let grant = currentDonorGrant else { return false }
        switch grant {
        case .founder:
            return true
        case .yearOfPro:
            guard let granted = UserDefaults.standard.object(forKey: UserDefaultsKeys.donorGrantDate) as? Date else {
                return false
            }
            return Date() < granted.addingTimeInterval(365 * 86_400)
        }
    }

    /// Scans the full transaction history for past donations and
    /// applies the grandfather policy. Runs on launch (after products
    /// load) and after restore-purchases. Idempotent: a grant is
    /// written once; an expired 1-year grant is never re-granted, but
    /// can still be upgraded to Founder if a bigger donation surfaces
    /// later (e.g. history restored on a new device).
    func scanForDonorGrant() async {
        var foundFounderTier = false
        var foundAnyDonation = false

        for await result in Transaction.all {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  DonationManager.allDonationIDs.contains(transaction.productID) else { continue }
            foundAnyDonation = true
            if Self.founderDonationIDs.contains(transaction.productID) {
                foundFounderTier = true
                break
            }
        }

        guard foundAnyDonation else { return }
        applyDonorGrant(founderTier: foundFounderTier)
    }

    private func applyDonorGrant(founderTier: Bool) {
        let defaults = UserDefaults.standard
        let existing = currentDonorGrant

        if founderTier {
            // Founder is permanent — apply on first detection, or
            // upgrade a (possibly expired) 1-year grant in place.
            guard existing != .founder else {
                recomputeIsPro()
                return
            }
            defaults.set(DonorGrant.founder.rawValue, forKey: UserDefaultsKeys.donorGrantType)
            if defaults.object(forKey: UserDefaultsKeys.donorGrantDate) == nil {
                defaults.set(Date(), forKey: UserDefaultsKeys.donorGrantDate)
            }
            queueDonorThanksIfNeeded(.founder)
        } else {
            // Coffee tier: one year from first detection. The grant
            // date is written exactly once — after expiry the record
            // stays on disk precisely so this guard refuses to
            // re-grant.
            guard existing == nil else {
                recomputeIsPro()
                return
            }
            defaults.set(DonorGrant.yearOfPro.rawValue, forKey: UserDefaultsKeys.donorGrantType)
            defaults.set(Date(), forKey: UserDefaultsKeys.donorGrantDate)
            queueDonorThanksIfNeeded(.yearOfPro)
        }

        recomputeIsPro()
    }

    /// One-time thank-you: queued until first *shown*, surfaced by
    /// MainTabView as a small sheet. The shown flag is consumed from
    /// the sheet's `onAppear` (`markDonorThanksShown`), not at queue
    /// time — if presentation is blocked (another sheet, app killed),
    /// the launch scan re-queues it until the user actually sees it.
    private func queueDonorThanksIfNeeded(_ grant: DonorGrant) {
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKeys.donorGrantThanksShown) else { return }
        pendingDonorThanks = grant
    }

    /// Called from `DonorThanksView.onAppear` — the first moment the
    /// thank-you is guaranteed visible.
    func markDonorThanksShown() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.donorGrantThanksShown)
    }

    // MARK: - Win-back

    /// Called on app foreground (after `checkEntitlements()`).
    /// Presents the win-back sheet at most once per lapse, never for
    /// users who declined it, never for grandfathered donors, and
    /// never while Pro is active.
    func evaluateWinBackPrompt() {
        // SwiftUI sheets present above the App Lock overlay — never
        // pitch while locked. The pending flag survives, so the next
        // foreground (or the post-unlock hook) re-evaluates.
        guard !AppLockManager.shared.isLocked else { return }
        let defaults = UserDefaults.standard
        guard !isPro,
              defaults.bool(forKey: UserDefaultsKeys.winBackPending),
              !defaults.bool(forKey: UserDefaultsKeys.winBackDeclined),
              !donorGrantIsActive else { return }
        // Deliberately does NOT consume `winBackPending` here: another
        // sheet may block presentation, and spending the once-per-lapse
        // shot on a sheet nobody saw would waste it. The flag is
        // cleared by `markWinBackShown()` from the sheet's onAppear,
        // once presentation is guaranteed.
        shouldShowWinBack = true
    }

    /// Called from the win-back sheet's `onAppear` — the first moment
    /// presentation is guaranteed. Consumes the pending flag so the
    /// sheet shows at most once per lapse: after this, a dismissed
    /// sheet resets `shouldShowWinBack` via its binding and every
    /// later `evaluateWinBackPrompt()` fails the pending guard.
    func markWinBackShown() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.winBackPending)
    }

    /// "No thanks" — never show the win-back sheet again.
    func declineWinBack() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.winBackDeclined)
        shouldShowWinBack = false
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
