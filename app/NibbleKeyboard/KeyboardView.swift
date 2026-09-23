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
    @State private var taskOwner = KeyboardTaskOwner()
    @AccessibilityFocusState private var focusedControl: String?
    @State private var detailOrigin: UUID?
    @State private var variableCompletion: VariableCompletion?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let pending = model.variableUse {
                    VariableFillView(template: pending.template,
                        actionTitle: pending.mode == .copy ? "完成文をコピー" : "完成文を入力",
                        compact: true, available: pending.available,
                        cancel: model.cancelVariableUse,
                        complete: { variableCompletion = VariableCompletion(values: $0) })
                        .id(pending.id)
                } else {
                    KeyboardBrowseView(model: model, taskOwner: taskOwner, focus: $focusedControl, detailOrigin: $detailOrigin)
                        .opacity(model.detail == nil ? 1 : 0)
                        .allowsHitTesting(model.detail == nil)
                        .accessibilityHidden(model.detail != nil)
                    if let detail = model.detail {
                        KeyboardDetailView(detail: detail, model: model, taskOwner: taskOwner, focus: $focusedControl)
                    }
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
        .onDisappear { taskOwner.endScreen() }
    }
}
