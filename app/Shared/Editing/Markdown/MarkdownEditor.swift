import AppMacros
import SwiftUI

/// Parses the current body off the UI actor and admits only matching source bytes.
@Equatable
struct MarkdownEditor: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @State private var document = MarkdownDocument()
    @State private var mode = MarkdownEditorMode.input

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 16) {
            Picker("本文の表示", selection: $mode) {
                Text("入力").tag(MarkdownEditorMode.input)
                Text("プレビュー").tag(MarkdownEditorMode.preview)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editor.mode")
            ZStack(alignment: .topLeading) {
                if model.body.isEmpty && mode == .input {
                    Text("保存したい文章やURLを入力。Markdownも使えます。")
                        .font(MarkdownStyle().previewFont).foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Keep the same text view mounted so selection and undo survive previewing.
                MarkdownSourceInput(text: $editor.body, focus: focus, document: document)
                    .frame(height: mode == .preview ? 0 : nil)
                    .opacity(mode == .preview ? 0 : 1)
                    .allowsHitTesting(mode == .input)
                    .accessibilityHidden(mode == .preview)
                    .focused(focus, equals: .body)
                if mode == .preview {
                    if SnippetText.hasSameBytes(document.source, model.body) {
                        MarkdownPreview(document: document)
                    } else {
                        ProgressView("プレビューを準備中")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }
        }
        .onChange(of: mode) {
            focus.wrappedValue = mode == .preview ? nil : .body
        }
        .task(id: model.bodyRevision) {
            let source = model.body
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let parsed = await MarkdownDocument.parse(source)
            if !Task.isCancelled, SnippetText.hasSameBytes(source, model.body) { document = parsed }
        }
    }
}
