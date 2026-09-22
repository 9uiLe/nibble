import AppMacros
import SwiftUI

/// Parses the current body off the UI actor and admits only matching source bytes.
@Equatable
struct MarkdownEditor: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @State private var highlighting = MarkdownHighlighting()

    var body: some View {
        @Bindable var editor = model
        ZStack(alignment: .topLeading) {
            if model.body.isEmpty {
                Text("保存したい文章やURLを入力。Markdownも使えます。")
                    .font(.nibbleBody).foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            MarkdownInput(text: $editor.body, focus: focus, highlighting: highlighting)
                .frame(minHeight: 180)
                .focused(focus, equals: .body)
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
