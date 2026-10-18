import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardDetailView: View {
    private let inputRevision = UUID()
    let detail: KeyboardModel.Detail
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let taskOwner: KeyboardTaskOwner
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { model.closeDetail() } label: {
                    Label("一覧に戻る", systemImage: "chevron.left")
                        .font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityFocused(focus, equals: "back")
                    .accessibilityIdentifier("keyboard.back")
                Text(verbatim: detail.item.displayTitle).font(.nibbleTitle).lineLimit(1).frame(maxWidth: .infinity)
                PinButton(pinned: detail.item.pinned, style: .icon, action: { taskOwner.startTask(on: model) })
                    .disabled(model.isUsing).accessibilityIdentifier("keyboard.pin")
            }.padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if detail.item.textPresentation.hasExplicitTitle {
                        Text(verbatim: detail.item.title).font(.nibbleTitle)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("keyboard.detail.title")
                    }
                    if let notice = model.notice, !notice.expires { KeyboardStatusMessage(notice: notice) }
                    switch detail.content {
                    case .loading: ProgressView("全文を読み込み中")
                    case .ready(let body): Text(verbatim: body).font(.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("keyboard.detail.body")
                    case .failed(let message): Text(message.text).font(.nibbleBody)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .id(detail.id).background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 8)
            HStack(spacing: 8) {
                Button { taskOwner.startTask(detail.item, as: .copy, on: model) } label: {
                    Text("クリップボードへコピー").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("keyboard.copy.\(detail.item.id)")
                Button { taskOwner.startTask(detail.item, as: .insert, on: model) } label: {
                    Text("入力先へ入力").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("keyboard.detail.insert")
            }.font(.caption.weight(.medium)).frame(minHeight: 44).buttonStyle(.bordered)
                .disabled(detail.body == nil || model.isUsing).padding(.horizontal, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
