import AppMacros
import SwiftUI

@Equatable
struct VariableFillView: View {
    private static let previewCharacterLimit = 160
    private static let previewLineLimit = 4
    private let inputRevision = UUID()
    let template: SnippetVariables
    let title: String
    let actionTitle: String
    let compact: Bool
    let availability: FeatureAvailability
    @SkipEquatable let cancel: () -> Void
    @SkipEquatable let valueEdited: () -> Void
    @SkipEquatable let complete: ([String: String]) -> Void
    @State private var values: [String: String] = [:]
    @State private var showsFullPreview = false
    @State private var isSubmitting = false
    @FocusState private var focusedName: String?

    var body: some View {
        let allValuesPresent = template.names.allSatisfy { values[$0]?.isEmpty == false }
        let completedPrefix = template.filledPrefix(with: values, characterLimit: Self.previewCharacterLimit)
        let prefix = completedPrefix ?? Self.prefix(template.body)
        let excerpt = Self.excerpt(prefix.text)
        let hasMore = prefix.hasMore || excerpt != prefix.text
        let preview = showsFullPreview && hasMore
            ? (completedPrefix == nil ? template.body : template.filled(with: values) ?? template.body)
            : excerpt
        let displayTitle = SnippetTextPresentation(title: title, body: template.body).title
        return VStack(spacing: 0) {
            HStack {
                Text(availability == .included ? "値を入力" : "変数を利用")
                    .font(.headline)
                Spacer(minLength: 8)
                Button("閉じる", action: cancel)
                    .font(.subheadline)
                    .accessibilityLabel("確定せず閉じる")
                    .accessibilityIdentifier("variables.cancel")
            }
            .padding(.horizontal, compact ? 12 : 20)
            .frame(minHeight: 44)
            Divider()
            if availability == .included {
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                        Text(verbatim: displayTitle)
                            .font(.nibbleTitle)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("variables.itemTitle")
                        Text("本文中の印を入力した値に置き換えます。同じ名前の印はまとめて変わります。")
                            .font(.nibbleBody)
                            .foregroundStyle(.secondary)
                        ForEach(template.names, id: \.self) { name in
                            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                                Text("{{\(name)}} に入れる値")
                                    .font(.nibbleTitle)
                                TextField("値を入力", text: Binding(
                                    get: { values[name] ?? "" },
                                    set: {
                                        showsFullPreview = false
                                        values[name] = $0
                                        valueEdited()
                                    }
                                ), prompt: Text("値を入力").foregroundStyle(.secondary))
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body)
                                .frame(minHeight: 44)
                                .focused($focusedName, equals: name)
                                .accessibilityLabel("{{\(name)}} に入れる値")
                            }
                        }
                        Divider()
                        HStack(spacing: 8) {
                            Text(allValuesPresent ? "完成文" : "入力前の文章")
                                .font(.nibbleTitle)
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
                        Text(verbatim: preview)
                            .font(.subheadline)
                            .lineLimit(showsFullPreview || !hasMore ? nil : Self.previewLineLimit)
                            .accessibilityIdentifier("variables.preview")
                        if focusedName == nil || compact {
                            VariableCompleteButton(actionTitle: actionTitle,
                                                   allValuesPresent: allValuesPresent,
                                                   isSubmitting: isSubmitting) {
                                isSubmitting = true
                                complete(values)
                            }
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, compact ? 12 : 20)
                    .padding(.vertical, compact ? 8 : 16)
                }
                .clipped()
                if focusedName != nil && !compact {
                    VariableCompleteButton(actionTitle: actionTitle,
                                           allValuesPresent: allValuesPresent,
                                           isSubmitting: isSubmitting) {
                        isSubmitting = true
                        complete(values)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: displayTitle)
                            .font(.nibbleTitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("variables.itemTitle")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(compact ? 12 : 20)
                }
            }
        }
        .background(compact ? Color(uiColor: .tertiarySystemBackground) : Color.nibbleCanvas)
        .privacySensitive()
    }

    private static func excerpt(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: previewLineLimit,
                                omittingEmptySubsequences: false)
            .prefix(previewLineLimit).joined(separator: "\n")
    }

    private static func prefix(_ text: String) -> (text: String, hasMore: Bool) {
        let leading = String(text.prefix(previewCharacterLimit + 1))
        return (String(leading.prefix(previewCharacterLimit)), leading.count > previewCharacterLimit)
    }
}
