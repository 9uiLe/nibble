import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct LibrarySearchBar: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var library = model
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("タイトルや本文を検索", text: $library.query)
                .focused(searchFocused)
                .submitLabel(.search)
                .frame(minHeight: 48)
                .accessibilityLabel("タイトルや本文を検索")
                .accessibilityIdentifier("search.field")
            if !model.query.isEmpty {
                Button("検索語を消去", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("search.clear")
            }
            if searchFocused.wrappedValue {
                Button { searchFocused.wrappedValue = false } label: {
                    Label("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("search.done")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .font(.body)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animationBarrier()
    }
}
