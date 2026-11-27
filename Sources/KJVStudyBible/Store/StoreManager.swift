import Foundation
import StoreKit
import SwiftUI

// MARK: - StoreKit 2 Monetization & Support Engine (Classroom Pro + Optional Support Tip Jar)

public enum StoreProductID {
    /// Non-consumable one-time lifetime unlock for Teacher / Classroom Sharing tools.
    public static let classroomPro = "com.swordandquillbible.pro.classroom"

    /// Consumable optional supporter tips (independent developer — not a 501(c)(3) donation).
    public static let tipCoffee = "com.swordandquillbible.tip.coffee"
    public static let tipFuel = "com.swordandquillbible.tip.fuel"
    public static let tipSupporter = "com.swordandquillbible.tip.supporter"

    public static let all: [String] = [classroomPro, tipCoffee, tipFuel, tipSupporter]
}

public enum SupportTipTier: String, CaseIterable, Identifiable, Sendable {
    case coffee
    case fuel
    case supporter

    public var id: String { rawValue }

    public var productID: String {
        switch self {
        case .coffee: return StoreProductID.tipCoffee
        case .fuel: return StoreProductID.tipFuel
        case .supporter: return StoreProductID.tipSupporter
        }
    }

    public var title: String {
        switch self {
        case .coffee: return "Buy a Coffee"
        case .fuel: return "Fuel Development"
        case .supporter: return "Generous Supporter"
        }
    }

    public var subtitle: String {
        switch self {
        case .coffee: return "A warm thank-you for keeping Scripture free & ad-free"
        case .fuel: return "Helps cover Apple Developer fees & ongoing iPad updates"
        case .supporter: return "Champions independent, 100% offline Bible study software"
        }
    }

    public var fallbackPrice: String {
        switch self {
        case .coffee: return "$2.99"
        case .fuel: return "$9.99"
        case .supporter: return "$24.99"
        }
    }

    public var systemImage: String {
        switch self {
        case .coffee: return "cup.and.saucer.fill"
        case .fuel: return "hammer.fill"
        case .supporter: return "heart.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .coffee: return .brown
        case .fuel: return .blue
        case .supporter: return .orange
        }
    }
}

@MainActor
public final class StoreManager: ObservableObject {
    @Published public private(set) var productsByID: [String: Product] = [:]
    @Published public private(set) var hasLiveProEntitlement: Bool = false
    @Published public private(set) var isPurchasing: Bool = false
    @Published public var statusMessage: String? = nil
    @Published public var lastThankYouMessage: String? = nil

    #if DEBUG
    /// Allows testing both locked Paywall and unlocked Pro flows on-device before App Store Connect is configured.
    /// Automatically stripped in Release / App Store builds.
    @Published public var debugSimulateProUnlocked: Bool = UserDefaults.standard.bool(forKey: "sq_debug_pro_unlocked") {
        didSet {
            UserDefaults.standard.set(debugSimulateProUnlocked, forKey: "sq_debug_pro_unlocked")
        }
    }
    #endif

    private var updatesTask: Task<Void, Never>? = nil

    public var isProUnlocked: Bool {
        #if DEBUG
        return hasLiveProEntitlement || debugSimulateProUnlocked
        #else
        return hasLiveProEntitlement
        #endif
    }

    public var classroomProDisplayPrice: String {
        productsByID[StoreProductID.classroomPro]?.displayPrice ?? "$9.99"
    }

    public func displayPrice(for tip: SupportTipTier) -> String {
        productsByID[tip.productID]?.displayPrice ?? tip.fallbackPrice
    }

    public init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func loadProducts() async {
        do {
            let fetched = try await Product.products(for: StoreProductID.all)
            var map: [String: Product] = [:]
            for p in fetched {
                map[p.id] = p
            }
            self.productsByID = map
        } catch {
            // Expected in local dev builds prior to App Store Connect setup; fallback prices remain active.
        }
    }

    public func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == StoreProductID.classroomPro,
               tx.revocationDate == nil {
                unlocked = true
            }
        }
        self.hasLiveProEntitlement = unlocked
    }

    public func purchaseClassroomPro() async {
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }

        if let product = productsByID[StoreProductID.classroomPro] {
            await executeStoreKitPurchase(product)
            return
        }

        #if DEBUG
        // Local dev preview simulation when App Store Connect products aren't live yet
        debugSimulateProUnlocked = true
        lastThankYouMessage = "Classroom Pro unlocked (Dev Preview)! All sharing tools are now active."
        #else
        statusMessage = "Unable to reach the App Store right now. Please check your connection and try again."
        #endif
    }

    public func purchaseTip(_ tier: SupportTipTier) async {
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }

        if let product = productsByID[tier.productID] {
            await executeStoreKitPurchase(product, tipTier: tier)
            return
        }

        #if DEBUG
        lastThankYouMessage = "Thank you for your \(tier.title) (\(tier.fallbackPrice)) support! (Dev Preview)"
        #else
        statusMessage = "Unable to reach the App Store right now. Please check your connection and try again."
        #endif
    }

    public func restorePurchases() async {
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isProUnlocked {
                lastThankYouMessage = "Purchases restored — Classroom Pro is active!"
            } else {
                statusMessage = "No previous Classroom Pro purchase was found for this Apple Account."
            }
        } catch {
            statusMessage = "Could not restore purchases: \(error.localizedDescription)"
        }
    }

    private func executeStoreKitPurchase(_ product: Product, tipTier: SupportTipTier? = nil) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    await refreshEntitlements()
                    if let tipTier {
                        lastThankYouMessage = "Thank you so much for your \(tipTier.title) support! May God bless your study."
                    } else if tx.productID == StoreProductID.classroomPro {
                        lastThankYouMessage = "Classroom Pro unlocked! Thank you for supporting Sword & Quill."
                    }
                case .unverified(_, let error):
                    statusMessage = "Purchase could not be verified: \(error.localizedDescription)"
                }
            case .userCancelled:
                break
            case .pending:
                statusMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            statusMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }
}
