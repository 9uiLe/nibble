import AppMacros
import SwiftUI

@MainActor @Equatable
struct WorkspaceSearchField: View {
    private let inputRevision = UUID()
    @Binding var search: String
    @FocusState private var searching: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(WorkspaceStyle.secondary)
            TextField(text: $search, prompt: Text("プロンプトを検索").foregroundStyle(WorkspaceStyle.secondary)) {
                Text("プロンプトを検索")
            }
            .focused($searching)
            .submitLabel(.search)
            .onSubmit { searching = false }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("workspace.search")
            if !search.isEmpty {
                Button { search = ""; searching = false } label: {
                    Label("検索を解除", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspace.search.clear")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, search.isEmpty ? 16 : 3)
        .frame(minHeight: 50)
        .glassEffect(.regular, in: .capsule)
    }
}
