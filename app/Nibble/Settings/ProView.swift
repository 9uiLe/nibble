import AppMacros
import StoreKit
import SwiftUI

@Equatable
struct ProView: View {
    private enum EntitlementContent {
        case checking
        case active
        case inactive
    }

    private enum ProductContent {
        case unavailable
        case loading
        case ready([Product])
        case failed
    }

    private let inputRevision = UUID()
    @SkipEquatable let subscription: ProSubscription
    @State private var showsManageSubscriptions = false
    @State private var products: [Product] = []
    @State private var loadingProducts = true
    @State private var reloadID = 0
    @State private var productRequestID: UUID?

    private var entitlementContent: EntitlementContent {
        if !subscription.checked { return .checking }
        return subscription.isActive ? .active : .inactive
    }

    private var productContent: ProductContent {
        if !FeatureAccess.subscriptionsOffered { return .unavailable }
        if loadingProducts { return .loading }
        if products.count == ProSubscription.productIDs.count { return .ready(products) }
        return .failed
    }

    var body: some View {
        VStack(spacing: 0) {
            switch entitlementContent {
            case .checking:
                ProgressView("登録状態を確認中")
                    .font(.nibbleBody).padding()
            case .active:
                Label("nibble Proを利用中です", systemImage: "checkmark.circle.fill")
                    .font(.nibbleTitle).padding()
                Button("登録を管理") { showsManageSubscriptions = true }
                    .font(.nibbleTitle)
                    .accessibilityIdentifier("pro.manage")
            case .inactive:
                Text(proDescription)
                    .font(.nibbleBody).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            switch productContent {
            case .unavailable:
                Spacer()
            case .loading:
                ProgressView("商品を読み込み中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let products):
                SubscriptionStoreView(subscriptions: products)
                    .storeButton(.visible, for: .restorePurchases)
            case .failed:
                ContentUnavailableView {
                    Label("商品を読み込めませんでした", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("しばらくしてから再読み込みしてください。保存済みの項目と下書きは引き続き利用できます。")
                } actions: {
                    Button("再読み込み") { reloadID += 1 }
                        .accessibilityIdentifier("pro.reloadProducts")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.nibbleCanvas)
        .navigationTitle("nibble Pro")
        .toolbarTitleDisplayMode(.inline)
        .task(id: reloadID) {
            guard FeatureAccess.subscriptionsOffered else { return }
            let id = UUID()
            productRequestID = id
            loadingProducts = true
            await subscription.refresh()
            guard !Task.isCancelled, productRequestID == id else { return }
            let loaded = (try? await Product.products(for: ProSubscription.productIDs)) ?? []
            guard !Task.isCancelled, productRequestID == id else { return }
            products = ProSubscription.productIDs.compactMap { id in loaded.first { $0.id == id } }
            loadingProducts = false
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
    }

    private var proDescription: String {
        switch FeatureAccess.availability(.variableReplacement, pro: false) {
        case .included:
            "保存件数の上限はありません。変数の差し替えも無料で利用できます。nibble Proの提供内容は準備中です。"
        case .requiresPro:
            "保存件数の上限はありません。変数の差し替えはnibble Proで利用できます。"
        case .unavailable:
            "保存件数の上限はありません。変数の差し替えは準備中です。"
        }
    }
}
