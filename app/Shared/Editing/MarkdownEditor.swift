import AppMacros
import SwiftUI

/// Parses the current body off the UI actor and admits only matching source bytes.
@Equatable
struct MarkdownEditor: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @State private var highlighting = MarkdownHighlighting()
    @State private var showsPreview = false

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 16) {
            Picker("本文の表示", selection: $showsPreview) {
                Text("入力").tag(false)
                Text("プレビュー").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editor.mode")
            ZStack(alignment: .topLeading) {
                if model.body.isEmpty && !showsPreview {
                    Text("保存したい文章やURLを入力。Markdownも使えます。")
                        .font(.nibbleBody).foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Keep the same text view mounted so selection and undo survive previewing.
                MarkdownInput(text: $editor.body, focus: focus, highlighting: highlighting)
                    .frame(minHeight: showsPreview ? 0 : 180)
                    .frame(height: showsPreview ? 0 : nil)
                    .opacity(showsPreview ? 0 : 1)
                    .allowsHitTesting(!showsPreview)
                    .accessibilityHidden(showsPreview)
                    .focused(focus, equals: .body)
                if showsPreview {
                    if SnippetText.hasSameBytes(highlighting.source, model.body) {
                        MarkdownPreview(highlighting: highlighting)
                    } else {
                        ProgressView("プレビューを準備中")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }
        }
        .onChange(of: showsPreview) {
            focus.wrappedValue = showsPreview ? nil : .body
        }
        .task(id: model.bodyRevision) {
            let source = model.body
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let parsed = await MarkdownHighlighting.parse(source)
            if !Task.isCancelled, SnippetText.hasSameBytes(source, model.body) { highlighting = parsed }
        }
    }
}
