import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardValueEditControls: View {
    private let inputRevision = UUID()
    let hasReading: Bool
    let extendingSelection: Bool
    @SkipEquatable let action: (KeyboardValueEditAction) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { action(.left) } label: {
                    Image(systemName: "arrow.left").frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityLabel("入力位置を左へ").accessibilityIdentifier("variables.cursor.left")
                Button { action(.right) } label: {
                    Image(systemName: "arrow.right").frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityLabel("入力位置を右へ").accessibilityIdentifier("variables.cursor.right")
                Button { action(.extend) } label: {
                    Text(extendingSelection ? "範囲選択中" : "範囲選択").font(.nibbleTitle)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityAddTraits(extendingSelection ? [.isSelected] : []).accessibilityIdentifier("variables.selection.extend")
            }
            HStack(spacing: 6) {
                Button { action(.start) } label: {
                    Text("先頭").font(.nibbleTitle).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("variables.cursor.start")
                Button { action(.end) } label: {
                    Text("末尾").font(.nibbleTitle).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("variables.cursor.end")
                Button { action(.all) } label: {
                    Text("全選択").font(.nibbleTitle).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("variables.selection.all")
            }
            if hasReading {
                Button { action(.cancelReading) } label: {
                    Text("未確定の文字を取り消す").font(.nibbleTitle)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("variables.reading.cancel")
            }
            Text("範囲選択をオンにして左右や先頭・末尾へ動かすと、色の付いた範囲を選べます。次に入力した文字で置き換わります。")
                .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
        }.buttonStyle(.bordered)
    }
}
