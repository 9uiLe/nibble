import AppMacros
import SwiftUI

@MainActor @Equatable
struct VariableTextPreview: View {
    private let inputRevision = UUID()
    let template: SnippetVariables
    let values: [VariableName: String]
    @Binding var expanded: Bool
    var body: some View {
        let filled = template.filledPrefix(with: values, characterLimit: 160)
        let source = filled?.text ?? String(template.body.prefix(161))
        let lines = source.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false)
        let excerpt = lines.prefix(4).joined(separator: "\n")
        let overflow = (filled?.hasMore ?? (source.count > 160)) || lines.count > 4
        let shown = expanded ? (filled == nil ? template.body : template.filled(with: values) ?? template.body) : String(excerpt.prefix(160))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(filled == nil ? "入力前の文章" : "完成文").font(.nibbleTitle)
                Spacer()
                if overflow {
                    Button { expanded.toggle() } label: {
                        Text(expanded ? "短く表示" : "全文を確認")
                            .frame(minHeight: 44).contentShape(.rect)
                    }.accessibilityIdentifier("variables.previewToggle")
                }
            }
            Text(verbatim: shown).font(.nibbleBody).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("variables.preview")
        }
    }
}
