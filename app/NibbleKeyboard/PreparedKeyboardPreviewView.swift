import AppMacros
import SwiftUI

@Equatable
struct PreparedKeyboardPreviewView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: PreparedKeyboardModel
    @SkipEquatable let owner: PreparedKeyboardTaskOwner
    let preview: PreparedKeyboardModel.Preview

    var body: some View {
        VStack(spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: WorkspacePresentation.title(preview.summary.title, body: preview.summary.preview))
                        .font(.headline).lineLimit(2)
                    Text(PreparedKeyboardMessage.status(preview.status))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("keyboard.preview.status")
                    switch preview.card {
                    case .some(let card):
                        NativeDocumentPreview(text: card.body, identifier: "keyboard.preview.body")
                            .frame(height: 180)
                    case .none:
                        Text(verbatim: preview.summary.preview).foregroundStyle(.secondary)
                        if preview.status == .loading { ProgressView() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("keyboard.preview.scroll")
            HStack(spacing: 8) {
                Button("一覧に戻る") {
                    owner.cancelUse()
                    model.closePreview()
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("keyboard.preview.back")
                Spacer(minLength: 0)
                Button("この入力先へ挿入") { owner.startTask(.insert) }
                    .buttonStyle(WorkspacePrimaryButtonStyle())
                    .frame(minHeight: 44)
                    .disabled(!model.canInsert)
                    .accessibilityIdentifier("keyboard.preview.insert")
            }
        }
    }
}
