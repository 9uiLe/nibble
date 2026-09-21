import AppMacros
import SwiftUI

@Equatable
struct KeyboardView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton
    @State private var taskOwner = KeyboardTaskOwner()
    @AccessibilityFocusState private var focusedControl: String?
    @State private var detailOrigin: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                KeyboardBrowseView(model: model, taskOwner: taskOwner, focus: $focusedControl, detailOrigin: $detailOrigin)
                    .opacity(model.detail == nil ? 1 : 0)
                    .allowsHitTesting(model.detail == nil)
                    .accessibilityHidden(model.detail != nil)
                if let detail = model.detail {
                    KeyboardDetailView(detail: detail, model: model, taskOwner: taskOwner, focus: $focusedControl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            KeyboardControls(model: model, globe: globe)
        }
        .tint(Color(uiColor: .systemBlue))
        .task(id: model.loadID) { await model.refresh() }
        .task(id: model.detail?.id) { await model.loadDetail() }
        .task(id: model.notice?.id) {
            if let id = model.notice?.id { await model.expireNotice(id: id) }
        }
        .onChange(of: model.notice?.id) {
            if let message = model.message { AccessibilityNotification.Announcement(message).post() }
        }
        .onChange(of: model.detail?.id) {
            if model.detail != nil {
                focusedControl = "back"
            } else if let detailOrigin, model.page?.items.contains(where: { $0.id == detailOrigin }) == true {
                focusedControl = "more.\(detailOrigin)"
            } else {
                focusedControl = "filter.\(model.request.filter.rawValue)"
            }
        }
        .onChange(of: model.loadID) { taskOwner.endScreen() }
        .onDisappear { taskOwner.endScreen() }
    }
}
