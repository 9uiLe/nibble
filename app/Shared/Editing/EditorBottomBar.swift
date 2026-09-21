import AppMacros
import SwiftUI

@Equatable
struct EditorBottomBar: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @Binding var confirmsDiscard: Bool
    let showHelp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            EditorMoreMenu(model: model, confirmsDiscard: $confirmsDiscard)
            Spacer(minLength: 12)
            if case .finishing(let operation) = model.phase {
                ProgressView {
                    Text(operation.progressTitle).font(.nibbleBody)
                }
            } else {
                Button(action: showHelp) {
                    Label("入力の上限と保存について", systemImage: "info")
                        .modifier(IconControlStyle())
                }
                .accessibilityIdentifier("editor.help")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.nibbleCanvas)
    }
}
