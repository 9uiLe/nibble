import AppMacros
import SwiftUI

@MainActor @Equatable
struct KeyboardVariableEditor: View {
    private enum Pane { case characters, editing }
    private let inputRevision = UUID()
    let buffer: KeyboardValueBuffer
    let candidates: [String]
    let conversionMessage: String?
    let extendingSelection: Bool
    @SkipEquatable let action: (KeyboardValueEditAction) -> Void
    @SkipEquatable let candidateSelected: (String) -> Void
    @SkipEquatable let insert: (String) -> Void
    @State private var pane = Pane.characters

    var body: some View {
        GeometryReader { proposal in
            VStack(spacing: 0) {
                ScrollView {
                    KeyboardValueText(buffer: buffer, compact: true)
                }
                .frame(height: proposal.size.height < 152 ? 20 : 64)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                KeyboardCandidateStrip(candidates: candidates, select: candidateSelected)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Button { pane = .characters } label: {
                                Text("文字").font(.nibbleTitle).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                            }.accessibilityIdentifier("variables.pane.characters")
                            Button { pane = .editing } label: {
                                Text("位置と選択").font(.nibbleTitle).frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                            }.accessibilityIdentifier("variables.pane.editing")
                            Button { action(.delete) } label: {
                                Image(systemName: "delete.left").font(.nibbleTitle)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                            }.accessibilityLabel("1文字削除").accessibilityIdentifier("variables.value.delete")
                        }.buttonStyle(.bordered)
                        HStack(spacing: 6) {
                            Button { action(.convert) } label: {
                                Text("変換").font(.nibbleTitle)
                                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                            }.disabled(buffer.reading?.isEmpty != false).accessibilityIdentifier("variables.convert")
                            Button { action(.commit) } label: {
                                Text("文字を確定").font(.nibbleTitle)
                                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(.rect)
                            }.disabled(buffer.reading == nil).accessibilityIdentifier("variables.reading.commit")
                        }.buttonStyle(.bordered)
                        if let conversionMessage {
                            Text(verbatim: conversionMessage).font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                                .accessibilityIdentifier("variables.conversionMessage")
                        }
                        switch pane {
                        case .characters: KeyboardValueKeypad(insert: insert)
                        case .editing:
                            KeyboardValueEditControls(hasReading: buffer.reading != nil, extendingSelection: extendingSelection, action: action)
                        }
                    }
                }.frame(minHeight: 44)
            }.padding(.horizontal, 8)
        }
    }
}
