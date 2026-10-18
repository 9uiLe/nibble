import AppMacros
import SwiftUI

@Equatable
struct MarkdownEditor: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding
    @Binding var selection: NSRange?
    @State private var mode = MarkdownEditorMode.input
    @State private var document = MarkdownDocument()

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本文（必須）").font(.nibbleTitle)
                Spacer(minLength: 8)
                Picker("本文の表示", selection: $mode) {
                    Text("入力").tag(MarkdownEditorMode.input)
                    Text("プレビュー").tag(MarkdownEditorMode.preview)
                }
                .pickerStyle(.segmented).frame(maxWidth: 240).accessibilityIdentifier("editor.mode")
            }
            ZStack(alignment: .topLeading) {
                MarkdownSourceInput(text: $editor.body, focus: focus, selection: $selection, document: document,
                                    editing: mode == .input)
                    .focused(focus, equals: .body)
                    .frame(height: mode == .preview ? 0 : nil)
                    .opacity(mode == .input ? 1 : 0)
                    .allowsHitTesting(mode == .input)
                    .accessibilityHidden(mode != .input)
                if mode == .input && model.body.isEmpty {
                    Text("保存したい文章やURLを入力。Markdownも使えます。")
                        .font(MarkdownStyle().previewFont).foregroundStyle(Color.nibbleSecondary)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                if mode == .preview {
                    switch SnippetText.hasSameBytes(document.source, model.body) {
                    case true: MarkdownPreview(document: document)
                    case false: ProgressView("プレビューを準備中").frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
            .background(Color.nibbleCanvas, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(focus.wrappedValue == .body ? Color.nibbleAccent : Color.nibbleBorder)
            }
        }
        .onChange(of: mode) { focus.wrappedValue = mode == .input ? .body : nil }
        .task(id: model.bodyRevision) {
            let requested = model.body
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            let result = await MarkdownDocument.parse(requested)
            guard !Task.isCancelled, SnippetText.hasSameBytes(requested, model.body) else { return }
            document = result
        }
    }
}
