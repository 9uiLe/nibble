import AppMacros
import SwiftUI

@Equatable
struct KeyboardDetailView: View {
    private let inputRevision = UUID()
    let detail: KeyboardModel.Detail
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            KeyboardDetailHeader(detail: detail, model: model, taskOwner: taskOwner, focus: focus)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.item.displayTitle).font(.nibbleTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let notice = model.notice, !notice.expires {
                        KeyboardStatusMessage(notice: notice)
                            .font(.nibbleBody)
                            .foregroundStyle(.secondary)
                    }
                    if let body = detail.body {
                        Text(verbatim: body).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("keyboard.detail.body")
                    } else if let failure = detail.failure {
                        Text(failure).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ProgressView().accessibilityLabel("全文を読み込み中")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .id(detail.id)
            .modifier(KeyboardPanelStyle())
            KeyboardDetailActions(detail: detail, model: model, taskOwner: taskOwner)
        }
    }
}
