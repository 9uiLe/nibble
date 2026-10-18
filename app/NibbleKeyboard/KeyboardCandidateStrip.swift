import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardCandidateStrip: View {
    private let inputRevision = UUID()
    let candidates: [String]
    @SkipEquatable let select: (String) -> Void

    var body: some View {
        if !candidates.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(candidates, id: \.self) { candidate in
                        Button { select(candidate) } label: {
                            Text(verbatim: candidate).font(.nibbleTitle)
                                .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                                .padding(.horizontal, 8)
                                .foregroundStyle(Color.nibbleKeyboardAccent)
                                .background(Color.nibbleKeyboardHighlight, in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("variables.candidate.\(candidate)")
                    }
                }
            }
            .frame(height: 44)
            .accessibilityLabel("変換候補")
        }
    }
}
