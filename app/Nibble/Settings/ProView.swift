import AppMacros
import StoreKit
import SwiftUI

@Equatable
struct ProView: View {
    private let inputRevision = UUID()
    @SkipEquatable let subscription: ProSubscription
    @State private var showsManageSubscriptions = false
    @State private var products: [Product] = []
    @State private var loadingProducts = true
    @State private var reloadID = 0

    var body: some View {
        VStack(spacing: 0) {
            if !subscription.checked {
                ProgressView("登録状態を確認中")
                    .font(.nibbleBody).padding()
            } else if subscription.isActive {
                Label("nibble Proを利用中です", systemImage: "checkmark.circle.fill")
                    .font(.nibbleTitle).padding()
                Button("登録を管理") { showsManageSubscriptions = true }
                    .font(.nibbleTitle)
                    .accessibilityIdentifier("pro.manage")
            } else {
                Text(proDescription)
                    .font(.nibbleBody).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            if !FeatureAccess.subscriptionsOffered {
                Spacer()
            } else if loadingProducts {
                ProgressView("商品を読み込み中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if products.count == ProSubscription.productIDs.count {
                SubscriptionStoreView(subscriptions: products)
                    .storeButton(.visible, for: .restorePurchases)
            } else {
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
            loadingProducts = true
            await subscription.refresh()
            do {
                let loaded = try await Product.products(for: ProSubscription.productIDs)
                products = ProSubscription.productIDs.compactMap { id in loaded.first { $0.id == id } }
            } catch {
                products = []
            }
            loadingProducts = false
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
    }

    private var proDescription: String {
        switch FeatureAccess.availability(.variableReplacement, pro: false) {
        case .included:
            "保存件数の上限はありません。差し替える項目を含む本文も、現在は無料で利用できます。nibble Proの新しい提供内容は準備中です。"
        case .requiresPro:
            "保存件数の上限はありません。変数の差し替えはnibble Proで利用できます。"
        case .unavailable:
            "保存件数の上限はありません。変数の差し替えは準備中です。"
        }
    }
}
