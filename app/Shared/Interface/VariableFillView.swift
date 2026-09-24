import AppMacros
import SwiftUI

@Equatable
struct VariableFillView: View {
    private let inputRevision = UUID()
    let template: SnippetVariables
    let actionTitle: String
    let compact: Bool
    let availability: FeatureAvailability
    @SkipEquatable let cancel: () -> Void
    @SkipEquatable let valueEdited: () -> Void
    @SkipEquatable let complete: ([String: String]) -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(availability == .included ? "値を入力" : "変数を利用")
                    .font(.nibbleTitle)
                Spacer(minLength: 8)
                Button("戻る", action: cancel)
                    .font(.subheadline)
                    .accessibilityIdentifier("variables.cancel")
            }
            .padding(.horizontal, compact ? 12 : 20)
            .frame(minHeight: 44)
            Divider()
            if availability == .included {
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                        ForEach(template.names, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.subheadline.weight(.semibold))
                                TextField("値を入力", text: Binding(
                                    get: { values[name] ?? "" },
                                    set: { values[name] = $0; valueEdited() }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(name)
                            }
                        }
                        if let preview = template.filled(with: values) {
                            Divider()
                            Text("完成文").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(verbatim: preview).font(.nibbleBody)
                                .accessibilityIdentifier("variables.preview")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, compact ? 12 : 20)
                    .padding(.vertical, compact ? 8 : 16)
                }
                Button(actionTitle) { complete(values) }
                    .buttonStyle(.borderedProminent)
                    .disabled(template.filled(with: values) == nil)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("variables.complete")
                    .padding(.horizontal, compact ? 12 : 20)
                    .padding(.bottom, compact ? 4 : 12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(availability == .requiresPro ? "nibble Proで利用できます" : "変数の利用は準備中です",
                          systemImage: "lock")
                        .font(.nibbleTitle)
                    Text(availability == .requiresPro
                         ? "この項目の変数を差し替えるにはProが必要です。nibbleの設定から確認できます。"
                         : "この項目の変数は現在差し替えられません。")
                        .font(.nibbleBody).foregroundStyle(.secondary)
                    Text("保存した本文は変更されず、コピーや入力も行っていません。")
                        .font(.nibbleBody).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(compact ? 12 : 20)
            }
        }
        .background(compact ? Color(uiColor: .tertiarySystemBackground) : Color.nibbleCanvas)
        .privacySensitive()
    }
}
