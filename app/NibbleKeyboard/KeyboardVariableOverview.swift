import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardVariableOverview: View {
    private let inputRevision = UUID()
    let template: SnippetVariables
    let title: String
    let actionTitle: String
    let values: [VariableName: String]
    let ready: Bool
    let submitting: Bool
    @Binding var expanded: Bool
    @SkipEquatable let select: (VariableName) -> Void
    @SkipEquatable let complete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: SnippetTextPresentation(title: title, body: template.body).title)
                    .font(.nibbleTitle).accessibilityIdentifier("variables.itemTitle")
                Text("本文中の印を入力した値に置き換えます。同じ名前の印はまとめて変わります。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                ForEach(template.names, id: \.self) { name in
                    KeyboardVariableField(name: name, value: values[name] ?? "", selected: false) { select(name) }
                }
                VariableTextPreview(template: template, values: values, expanded: $expanded)
                VariableCompleteButton(actionTitle: actionTitle, allValuesPresent: ready, isSubmitting: submitting, complete: complete)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}
