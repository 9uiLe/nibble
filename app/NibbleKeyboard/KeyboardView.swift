import AppMacros
import SwiftUI

@Equatable
struct KeyboardView: View {
    private struct VariableCompletion {
        let id = UUID()
        let values: [String: String]
    }
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton
    @SkipEquatable let setPreferredHeight: (CGFloat) -> Void
    @State private var taskOwner = KeyboardTaskOwner()
    @AccessibilityFocusState private var focusedControl: String?
    @State private var detailOrigin: UUID?
    @State private var listPosition: UUID?
    @State private var variableCompletion: VariableCompletion?

    private var preferredHeight: CGFloat {
        if model.detail != nil || model.variableUse != nil || !model.isCurrent || model.notice?.expires == false {
            return 288
        }
        let count = model.page?.items.count ?? 0
        if count == 0 { return 196 }
        return min(288, CGFloat(44 + count * 70 + 44 + 8))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let pending = model.variableUse {
                    VariableFillView(template: pending.template, title: pending.item.title,
                        actionTitle: pending.mode == .copy ? "完成文をコピー" : "完成文を入力",
                        compact: true, availability: pending.availability,
                        cancel: model.cancelVariableUse, valueEdited: model.noteVariableValueEditing,
                        complete: { variableCompletion = VariableCompletion(values: $0) })
                        .id(pending.id)
                } else if let detail = model.detail {
                    KeyboardDetailView(detail: detail, model: model, taskOwner: taskOwner, focus: $focusedControl)
                } else {
                    KeyboardBrowseView(model: model, taskOwner: taskOwner, focus: $focusedControl,
                        detailOrigin: $detailOrigin, listPosition: $listPosition)
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
        .onChange(of: variableCompletion?.id) {
            if let completion = variableCompletion {
                taskOwner.startTask(completion.values, on: model)
                variableCompletion = nil
            }
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
        .onChange(of: preferredHeight, initial: true) { _, height in setPreferredHeight(height) }
        .onDisappear { taskOwner.endScreen() }
    }
}
