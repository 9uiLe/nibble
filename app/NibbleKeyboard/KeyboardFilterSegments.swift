import AppMacros
import SwiftUI

@Equatable
struct KeyboardFilterSegments: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding

    var body: some View {
        HStack(spacing: 0) {
            ForEach(KeyboardFilter.allCases, id: \.self) { filter in
                Button { model.select(filter) } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(model.request.filter == filter ? .primary : .secondary)
                        .overlay(alignment: .bottom) {
                            if model.request.filter == filter {
                                Rectangle().fill(Color(uiColor: .systemBlue)).frame(height: 2)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.request.filter == filter ? .isSelected : [])
                .accessibilityIdentifier("keyboard.filter.\(filter.rawValue)")
                .accessibilityFocused(focus, equals: "filter.\(filter.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("保存した項目の絞り込み")
    }
}
