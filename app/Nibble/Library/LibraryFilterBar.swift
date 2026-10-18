import AppMacros
import SwiftUI

@MainActor @Equatable
struct LibraryFilterBar: View {
    private let inputRevision = UUID()
    @Binding var selection: LibraryFilter
    var counts: LibraryCounts?
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LibrarySurface.collections, id: \.self) { filter in
                    Button { selection = filter } label: {
                        HStack(spacing: 6) {
                            Text(filter.title)
                            if let count = counts?.count(for: filter) { Text(count, format: .number).monospacedDigit() }
                        }
                        .font(.footnote.weight(.semibold)).fixedSize()
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .foregroundStyle(selection == filter ? Color.nibbleOnSelection : .nibblePrimary)
                        .background(selection == filter ? Color.nibbleSelection : .nibbleSurface, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain).accessibilityLabel(filter.title)
                    .accessibilityValue(counts?.count(for: filter).map { "\($0)件" } ?? "")
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                    .accessibilityIdentifier("library.filter.\(filter.rawValue)")
                }
            }
        }.scrollIndicators(.hidden)
    }
}
