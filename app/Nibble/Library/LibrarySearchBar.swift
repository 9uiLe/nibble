import AppMacros
import ScopedAnimation
import SwiftUI

@MainActor @Equatable
struct LibrarySearchBar: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField(model.surface == .deleted ? "削除した項目を検索" : "タイトルや本文を検索", text: Binding(get: { model.query }, set: { model.query = $0 }))
                .focused(searchFocused).submitLabel(.search)
                .accessibilityIdentifier("search.field")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Label("検索語を消去", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(.rect)
                }.accessibilityIdentifier("search.clear")
            }
            Button { searchFocused.wrappedValue = false } label: {
                Label("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down")
                    .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(.rect)
            }
                .opacity(searchFocused.wrappedValue ? 1 : 0)
                .disabled(!searchFocused.wrappedValue).accessibilityHidden(!searchFocused.wrappedValue)
                .accessibilityIdentifier("search.done")
        }
        .font(.body).foregroundStyle(Color.nibblePrimary)
        .padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 48)
        .background(Color.nibbleSurface, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(searchFocused.wrappedValue ? Color.nibbleAccent : .nibbleBorder, lineWidth: searchFocused.wrappedValue ? 2 : 1) }
        .textInputAutocapitalization(.never).autocorrectionDisabled().animationBarrier()
    }
}
