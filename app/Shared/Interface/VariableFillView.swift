import AppMacros
import SwiftUI

@Equatable
struct VariableFillView: View {
    private static let previewCharacterLimit = 240
    private let inputRevision = UUID()
    let template: SnippetVariables
    let actionTitle: String
    let compact: Bool
    let availability: FeatureAvailability
    @SkipEquatable let cancel: () -> Void
    @SkipEquatable let valueEdited: () -> Void
    @SkipEquatable let complete: ([String: String]) -> Void
    @State private var values: [String: String] = [:]
    @State private var showsFullPreview = false

    var body: some View {
        let allValuesPresent = template.names.allSatisfy { values[$0]?.isEmpty == false }
        return VStack(spacing: 0) {
            HStack {
                Text(availability == .included ? "値を入力" : "変数を利用")
                    .font(.headline)
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
                    VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                        ForEach(template.names, id: \.self) { name in
                            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                                Text(name).font(.nibbleTitle)
                                TextField("値を入力", text: Binding(
                                    get: { values[name] ?? "" },
                                    set: {
                                        showsFullPreview = false
                                        values[name] = $0
                                        valueEdited()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body)
                                .frame(minHeight: 44)
                                .accessibilityLabel(name)
                            }
                        }
                        if allValuesPresent, let preview = template.filled(with: values) {
                            let excerpt = String(preview.prefix(Self.previewCharacterLimit))
                            let hasMore = excerpt.utf8.count < preview.utf8.count
                            Divider()
                            HStack(spacing: 8) {
                                Text("完成文")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                if hasMore {
                                    Button(showsFullPreview ? "短く表示" : "全文を確認") {
                                        showsFullPreview.toggle()
                                    }
                                    .font(.nibbleBody)
                                    .frame(minHeight: 44)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                    .accessibilityIdentifier("variables.previewToggle")
                                }
                            }
                            Text(verbatim: showsFullPreview ? preview : excerpt)
                                .font(.subheadline)
                                .lineLimit(showsFullPreview || !hasMore ? nil : 4)
                                .accessibilityIdentifier("variables.preview")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, compact ? 12 : 20)
                    .padding(.vertical, compact ? 8 : 16)
                }
                Button { complete(values) } label: {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!allValuesPresent)
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
