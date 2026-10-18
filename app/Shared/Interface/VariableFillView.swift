import AppMacros
import SwiftUI

@MainActor @Equatable
struct VariableFillView: View {
    private let inputRevision = UUID()
    let template: SnippetVariables
    let title: String
    let actionTitle: String
    let compact: Bool
    let availability: FeatureAvailability
    @SkipEquatable let cancel: () -> Void
    @SkipEquatable let complete: ([VariableName: String]) -> Void
    @State private var values: [VariableName: String] = [:]
    @State private var expanded = false
    @State private var submitting = false
    @FocusState private var editing: VariableName?
    private var ready: Bool { template.names.allSatisfy { values[$0]?.isEmpty == false } }
    var body: some View {
        VStack(spacing: 0) {
            if compact {
                HStack {
                    Text("値を入力").font(.nibbleTitle)
                    Spacer()
                    Button(action: cancel) {
                        Text("閉じる").font(.nibbleTitle).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                    }.accessibilityIdentifier("variables.cancel")
                }.padding(.horizontal, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: SnippetTextPresentation(title: title, body: template.body).title)
                        .font(.nibbleTitle).accessibilityIdentifier("variables.itemTitle")
                    switch availability {
                    case .included:
                        Text("本文中の印を入力した値に置き換えます。同じ名前の印はまとめて変わります。")
                            .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                        ForEach(template.names, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(name.marker) に入れる値").font(.nibbleTitle)
                                TextField("値を入力", text: Binding(get: { values[name] ?? "" }, set: { value in
                                    values[name] = value
                                    expanded = false
                                }))
                                .textFieldStyle(.roundedBorder).font(.body).frame(minHeight: 44)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($editing, equals: name)
                                .accessibilityLabel("\(name.marker) に入れる値")
                            }
                        }
                        VariableTextPreview(template: template, values: values, expanded: $expanded)
                        if compact || editing == nil {
                            VariableCompleteButton(actionTitle: actionTitle, allValuesPresent: ready, isSubmitting: submitting) {
                                submitting = true
                                complete(values)
                            }
                        }
                    case .requiresPro, .unavailable:
                        Label(availability == .requiresPro ? "nibble Proで利用できます" : "変数の利用は準備中です", systemImage: "lock")
                            .font(.nibbleTitle)
                        Text("保存した本文は変更されず、コピーや入力も行っていません。nibbleの設定から利用条件を確認できます。")
                            .font(.nibbleBody)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(compact ? 12 : 20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !compact && editing != nil && availability == .included {
                    VariableCompleteButton(actionTitle: actionTitle, allValuesPresent: ready, isSubmitting: submitting) {
                        submitting = true
                        complete(values)
                    }
                    .padding(12).background(Color.nibbleCanvas)
                }
            }
        }
        .background(compact ? Color.clear : Color.nibbleCanvas).privacySensitive().disabled(submitting)
    }
}
