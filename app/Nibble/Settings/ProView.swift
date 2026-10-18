import AppMacros
import StoreKit
import SwiftUI

@MainActor @Equatable
struct ProView: View {
    private enum Catalog { case unavailable, loading, ready([Product]), failed }
    private let inputRevision = UUID()
    @SkipEquatable let subscription: ProSubscription
    @State private var catalog = Catalog.unavailable
    @State private var reload = 0
    @State private var management = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存・検索・コピー・キーボード入力は、件数の上限なく利用できます。変数の差し替えも無料です。nibble Proの継続的な機能は準備中です。")
                .font(.nibbleBody).padding()
            if subscription.isActive {
                Label("nibble Proを利用中です", systemImage: "checkmark.circle").font(.nibbleTitle).padding(.horizontal)
                Button("登録を管理") { management = true }.frame(minHeight: 44).padding(.horizontal).accessibilityIdentifier("pro.manage")
            }
            switch catalog {
            case .unavailable: Spacer()
            case .loading: ProgressView("商品を読み込み中").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let products): SubscriptionStoreView(subscriptions: products).storeButton(.visible, for: .restorePurchases)
            case .failed:
                ContentUnavailableView {
                    Label("商品を読み込めませんでした", systemImage: "exclamationmark.triangle")
                } description: { Text("保存した項目と下書きは引き続き利用できます。") } actions: {
                    Button("再読み込み") { reload += 1 }.accessibilityIdentifier("pro.reloadProducts")
                }
            }
        }
        .navigationTitle("nibble Pro").navigationBarTitleDisplayMode(.inline).background(Color.nibbleCanvas)
        .manageSubscriptionsSheet(isPresented: $management)
        .task(id: reload) {
            guard FeatureAccess.subscriptionsOffered else { catalog = .unavailable; return }
            catalog = .loading
            do {
                let loaded = try await Product.products(for: ProSubscription.productIDs)
                try Task.checkCancellation()
                guard loaded.count == ProSubscription.productIDs.count else { catalog = .failed; return }
                catalog = .ready(loaded)
            } catch is CancellationError { }
            catch { catalog = .failed }
        }
    }
}
