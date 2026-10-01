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
            Image(systemName: "magnifyingglass").foregroundStyle(Color.nibbleSecondary).accessibilityHidden(true)
            TextField("タイトルや本文を検索", text: $library.query,
                      prompt: Text("タイトルや本文を検索").foregroundStyle(Color.nibbleSecondary))
                .foregroundStyle(Color.nibblePrimary)
                .focused(searchFocused)
                .submitLabel(.search)
                .frame(minHeight: 48)
                .accessibilityLabel("タイトルや本文を検索")
                .accessibilityIdentifier("search.field")
            if !model.query.isEmpty {
                Button("検索語を消去", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.nibbleSecondary)
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
                .foregroundStyle(Color.nibbleSecondary)
                .accessibilityIdentifier("search.done")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .font(.body)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .background(Color.nibbleSurface, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(searchFocused.wrappedValue ? Color.nibbleAccent : Color.nibbleBorder,
                              lineWidth: searchFocused.wrappedValue ? 2 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animationBarrier()
    }
}
