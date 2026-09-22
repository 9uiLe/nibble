import AppMacros
import SwiftUI


/// Selects a retained collection within the library workspace.
@Equatable
struct LibraryFilterBar: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @Binding var selection: LibraryFilter
    var counts: LibraryCounts?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(LibrarySurface.collections, id: \.self) { filter in
                        Button { selection = filter } label: {
                            HStack(spacing: 7) {
                                Text(filter.title).font(.footnote.weight(.semibold))
                                if let count = counts?.count(for: filter) {
                                    Text(count, format: .number)
                                        .font(.caption2).monospacedDigit()
                                }
                            }
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(selection == filter ? Color.nibbleOnSelection : Color.secondary)
                            .background(selection == filter ? Color.nibbleSelection : Color.clear,
                                        in: .rect(cornerRadius: 8))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.title)
                        .accessibilityValue(counts?.count(for: filter).map { "\($0)件" } ?? "")
                        .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
                        .accessibilityIdentifier("library.filter.\(filter.rawValue)")
                        .id(filter)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(Color.nibbleCanvas)
            .overlay(alignment: .bottom) { Divider() }
            .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}
