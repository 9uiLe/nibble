import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardFilterBar: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let focus: AccessibilityFocusState<String?>.Binding
    var body: some View {
        HStack(spacing: 4) {
            ForEach(KeyboardFilter.allCases, id: \.self) { filter in
                Button { model.select(filter) } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(model.request.filter == filter ? .semibold : .regular))
                        .frame(minWidth: 62, minHeight: 44).contentShape(.rect)
                }
                    .overlay(alignment: .bottom) { if model.request.filter == filter { Rectangle().frame(height: 2) } }
                    .accessibilityAddTraits(model.request.filter == filter ? .isSelected : [])
                    .accessibilityFocused(focus, equals: "filter.\(filter.rawValue)")
                    .accessibilityIdentifier("keyboard.filter.\(filter.rawValue)")
            }
            Spacer(minLength: 0)
            if model.loadFailure != nil || model.notice?.expires == false {
                Button { model.requestReload() } label: {
                    Label("再読み込み", systemImage: "arrow.clockwise")
                        .font(.caption).frame(minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("keyboard.refresh")
            }
        }.buttonStyle(.plain).foregroundStyle(.primary).padding(.horizontal, 10)
    }
}
