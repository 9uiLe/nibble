import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardView: View {
    private enum Page { case browse, detail(KeyboardModel.Detail), variables(KeyboardModel.VariableUse) }
    private struct Completion { let id = UUID(); let values: [VariableName: String] }
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton
    @SkipEquatable let setPreferredHeight: (CGFloat) -> Void
    @State private var owner = KeyboardTaskOwner()
    @State private var position: UUID?
    @State private var detailOrigin: UUID?
    @State private var completion: Completion?
    @AccessibilityFocusState private var focus: String?
    private var page: Page {
        if let variables = model.variableUse { return .variables(variables) }
        if let detail = model.detail { return .detail(detail) }
        return .browse
    }
    private var height: CGFloat {
        if model.variableUse != nil { return 400 }
        guard model.detail == nil, model.variableUse == nil, model.isCurrent, model.notice?.expires != false else { return 288 }
        return min(288, CGFloat(96 + max(1, model.page?.items.count ?? 0) * 70))
    }
    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .browse:
                KeyboardBrowseView(model: model, taskOwner: owner, listPosition: $position, detailOrigin: $detailOrigin, focus: $focus)
            case .detail(let detail):
                KeyboardDetailView(detail: detail, model: model, taskOwner: owner, focus: $focus)
            case .variables(let request):
                KeyboardVariableFillView(template: request.template, title: request.item.title,
                    actionTitle: request.mode == .insert ? "完成文を入力" : "完成文をコピー",
                    availability: request.availability, cancel: model.cancelVariableUse,
                    complete: { completion = Completion(values: $0) })
                    .id(request.id)
            }
            KeyboardControls(model: model, globe: globe)
        }
        .tint(Color.nibbleKeyboardAccent).environment(\.iosDesignTokens, .nibbleKeyboard).privacySensitive()
        .task(id: model.loadID) { await model.refresh() }
        .task(id: model.detail?.id) { await model.loadDetail() }
        .task(id: model.notice?.id) { if let notice = model.notice { await model.expireNotice(id: notice.id) } }
        .onChange(of: completion?.id) {
            if let completion { owner.startTask(completion.values, on: model) }
            completion = nil
        }
        .onChange(of: model.loadID) { owner.endScreen() }
        .onChange(of: model.request) { position = nil }
        .onChange(of: model.notice?.id) { if let message = model.message { AccessibilityNotification.Announcement(message).post() } }
        .onChange(of: model.detail?.id) {
            focus = model.detail == nil ? detailOrigin.map { "more.\($0)" } : "back"
        }
        .onChange(of: height, initial: true) { setPreferredHeight(height) }
        .onDisappear { owner.endScreen() }
    }
}
