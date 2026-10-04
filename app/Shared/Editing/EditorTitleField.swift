import AppMacros
import SwiftUI

@Equatable
struct EditorTitleField: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: EditorModel
    @SkipEquatable let focus: FocusState<EditorField?>.Binding

    var body: some View {
        @Bindable var editor = model
        VStack(alignment: .leading, spacing: 8) {
            Text("タイトル（任意）").font(.nibbleTitle).foregroundStyle(Color.nibblePrimary)
            TextField("例：お礼のメール", text: $editor.title,
                      prompt: Text("例：お礼のメール").foregroundStyle(Color.nibbleSecondary), axis: .vertical)
                .foregroundStyle(Color.nibblePrimary)
                .font(.body)
                .focused(focus, equals: .title)
                .padding(12)
                .frame(minHeight: InterfaceMetrics.touchSize)
                .background(Color.nibbleSurface, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(focus.wrappedValue == .title ? Color.nibbleAccent : Color.nibbleBorder)
                }
                .accessibilityIdentifier("editor.title")
                .accessibilityLabel("タイトル（任意）")
            Text("一覧で見つけるための名前です。")
                .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
        }
    }
}
