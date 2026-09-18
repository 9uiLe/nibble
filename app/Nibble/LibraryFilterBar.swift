import AppMacros
import SwiftUI


/// These controls change the contents of one library, while the tab bar changes screens.
@Equatable
struct LibraryFilterBar: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @Binding var selection: LibraryFilter

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([LibraryFilter.all, .pinned, .drafts], id: \.self) { filter in
                        Button { selection = filter } label: {
                            Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .foregroundStyle(selection == filter ? Color.nibbleAccent : Color.primary)
                            .background(selection == filter ? Color.nibbleAccent.opacity(0.14) : Color.clear,
                                        in: .rect(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(selection == filter ? Color.nibbleAccent : Color.secondary.opacity(0.4))
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
                        .accessibilityIdentifier("library.filter.\(filter.rawValue)")
                        .id(filter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .background(Color.nibbleCanvas)
            .overlay(alignment: .bottom) { Divider() }
            .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}
