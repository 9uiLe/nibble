import AppMacros
import SwiftUI

@Equatable
struct EditorSharedContentHeader: View {

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("共有された内容を確認").font(.nibbleTitle)
                Text("編集してからnibbleに保存できます。")
                    .font(.nibbleBody).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.and.arrow.down")
                .foregroundStyle(Color.nibbleAccent)
        }
        .accessibilityIdentifier("editor.sharedContent")
    }
}
