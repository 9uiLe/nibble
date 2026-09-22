import AppMacros
import SwiftUI

@Equatable
struct EditorBodyField: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @State private var highlighting = MarkdownHighlighting()

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本文").font(.nibbleTitle).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("末尾にペースト").font(.caption).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { texts in
                        if let text = texts.first { model.body += text }
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.large)
                    .buttonBorderShape(.circle)
                    .frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
                    .frame(minWidth: InterfaceMetrics.touchSize, minHeight: InterfaceMetrics.touchSize)
                    .accessibilityLabel("本文の末尾にペースト")
                    .accessibilityIdentifier("editor.paste")
                }
            }
            Text("ペーストは、テキストをコピーすると使えます。")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("editor.pasteGuidance")
            if !model.hasBody {
                Text("本文を入力すると保存できます。空白や改行だけでは保存できません。")
                    .font(.nibbleBody).foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.bodyRequirement")
            }
            ZStack(alignment: .topLeading) {
                if model.body.isEmpty {
                    Text("保存したい文章やURLを入力。Markdownも使えます。")
                        .font(.nibbleBody).foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                MarkdownTextField(text: $editor.body, focus: focus, highlighting: highlighting)
                    .frame(minHeight: 180)
                    .focused(focus, equals: .body)
            }
        }
        .task(id: model.draft.sequence) {
            let source = model.body
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let parsed = await MarkdownHighlighting.parse(source)
            if !Task.isCancelled, SnippetText.hasSameBytes(source, model.body) { highlighting = parsed }
        }
    }
}
