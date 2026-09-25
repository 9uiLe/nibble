import AppMacros
import SwiftUI

@Equatable
struct KeyboardDetailView: View {
    private enum Content {
        case body(String)
        case failure(String)
        case loading
    }

    private let inputRevision = UUID()
    let detail: KeyboardModel.Detail
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding

    private var content: Content {
        if let body = detail.body { return .body(body) }
        if let failure = detail.failure { return .failure(failure) }
        return .loading
    }

    var body: some View {
        VStack(spacing: 0) {
            KeyboardDetailHeader(detail: detail, model: model, taskOwner: taskOwner, focus: focus)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let notice = model.notice, !notice.expires {
                        KeyboardStatusMessage(notice: notice)
                            .font(.nibbleBody)
                            .foregroundStyle(.secondary)
                    }
                    switch content {
                    case .body(let body):
                        Text(verbatim: body).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("keyboard.detail.body")
                    case .failure(let failure):
                        Text(failure).font(.footnote).foregroundStyle(.secondary)
                    case .loading:
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
