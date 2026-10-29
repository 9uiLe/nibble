import AppMacros
import SwiftUI

@MainActor @Equatable
struct PromptDetailMenu: View {
    private let inputRevision = UUID()
    let rename: @MainActor () -> Void
    let delete: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: rename) {
                HStack(spacing: 12) {
                    Image(systemName: "textformat").font(.system(size: 18)).frame(width: 22)
                    Text("タイトルを変更")
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("prompt.rename")
            Rectangle().fill(WorkspaceStyle.divider).frame(height: 1)
            Button(role: .destructive, action: delete) {
                HStack(spacing: 12) {
                    Image(systemName: "trash").font(.system(size: 18)).frame(width: 22)
                    Text("削除")
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("prompt.delete")
        }
        .font(.body)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(width: 248)
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
    }
}
