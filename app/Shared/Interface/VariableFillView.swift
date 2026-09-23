import AppMacros
import SwiftUI

@Equatable
struct VariableFillView: View {
    private let inputRevision = UUID()
    let template: SnippetVariables
    let actionTitle: String
    let compact: Bool
    let available: Bool
    @SkipEquatable let cancel: () -> Void
    @SkipEquatable let complete: ([String: String]) -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("差し替えて使う")
                .font(.nibbleTitle)
                .accessibilityAddTraits(.isHeader)
            if available {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(template.names, id: \.self) { name in
                            TextField(name, text: Binding(
                                get: { values[name] ?? "" },
                                set: { values[name] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(name)
                        }
                        if let preview = template.filled(with: values) {
                            Text("完成文").font(.caption.weight(.semibold))
                            Text(verbatim: preview).font(.nibbleBody)
                                .accessibilityIdentifier("variables.preview")
                        }
                    }
                }
                Button(actionTitle) { complete(values) }
                    .buttonStyle(.borderedProminent)
                    .disabled(template.filled(with: values) == nil)
                    .accessibilityIdentifier("variables.complete")
            } else {
                Text("この機能はnibble Proで利用できます。保存した本文は変更されていません。")
                    .font(.nibbleBody)
            }
            Button("キャンセル", action: cancel)
                .accessibilityIdentifier("variables.cancel")
        }
        .padding(compact ? 10 : 20)
        .privacySensitive()
    }
}
