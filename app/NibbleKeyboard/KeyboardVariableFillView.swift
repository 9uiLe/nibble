import AppMacros
import KeyboardValueConversion
import SwiftUI

@MainActor @Equatable
struct KeyboardVariableFillView: View {
    private let inputRevision = UUID()
    let template: SnippetVariables
    let title: String
    let actionTitle: String
    let availability: FeatureAvailability
    @SkipEquatable let cancel: () -> Void
    @SkipEquatable let complete: ([VariableName: String]) -> Void
    @State private var buffers: [VariableName: KeyboardValueBuffer] = [:]
    @State private var selected: VariableName?
    @State private var editing = false
    @State private var extendingSelection = false
    @State private var candidates: [String] = []
    @State private var conversionMessage: String?
    @State private var expanded = false
    @State private var submitting = false
    @State private var converter = JapaneseValueConverter()

    private var selectedName: VariableName? { selected ?? template.names.first }
    private var buffer: KeyboardValueBuffer { selectedName.flatMap { buffers[$0] } ?? KeyboardValueBuffer() }
    private var values: [VariableName: String] {
        Dictionary(uniqueKeysWithValues: template.names.map { name in
            var value = buffers[name] ?? KeyboardValueBuffer()
            if value.reading != nil { value.commitReading() }
            return (name, value.text)
        })
    }
    private var ready: Bool {
        let current = values
        return template.names.allSatisfy { current[$0]?.isEmpty == false }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if editing {
                    Button {
                        commitReading()
                        editing = false
                    } label: {
                        Label("戻る", systemImage: "chevron.backward").font(.nibbleTitle)
                            .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                    }.accessibilityIdentifier("variables.editor.back")
                }
                Text(editing ? (selectedName?.marker ?? "値を入力") : "値を入力")
                    .font(.nibbleTitle).lineLimit(1)
                Spacer()
                Button {
                    buffers = [:]
                    converter.release()
                    cancel()
                } label: {
                    Text("閉じる").font(.nibbleTitle)
                        .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityIdentifier("variables.cancel")
            }.padding(.horizontal, 12)
            switch availability {
            case .included:
                switch editing {
                case true:
                    KeyboardVariableEditor(buffer: buffer, candidates: candidates, conversionMessage: conversionMessage,
                                           extendingSelection: extendingSelection, action: edit, candidateSelected: { candidate in
                                               update { $0.commitReading(candidate: candidate) }
                                               clearConversion()
                                           }, insert: { text in
                                               update { value in
                                                   if value.reading == nil { value.beginReading() }
                                                   value.appendReading(text)
                                               }
                                               clearConversion()
                                           })
                case false:
                    KeyboardVariableOverview(template: template, title: title, actionTitle: actionTitle, values: values,
                                             ready: ready, submitting: submitting, expanded: $expanded, select: { name in
                                                 selected = name
                                                 extendingSelection = false
                                                 editing = true
                                             }, complete: {
                                                 guard !submitting, ready else { return }
                                                 submitting = true
                                                 let output = values
                                                 converter.release()
                                                 complete(output)
                                             })
                }
            case .requiresPro, .unavailable:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: SnippetTextPresentation(title: title, body: template.body).title)
                            .font(.nibbleTitle).accessibilityIdentifier("variables.itemTitle")
                        Label(availability == .requiresPro ? "nibble Proで利用できます" : "変数の利用は準備中です", systemImage: "lock")
                            .font(.nibbleTitle)
                        Text("保存した本文は変更されず、コピーや入力も行っていません。nibbleの設定から利用条件を確認できます。")
                            .font(.nibbleBody)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
            }
        }
        .privacySensitive().disabled(submitting)
        .onDisappear { converter.release() }
    }

    private func update(_ operation: (inout KeyboardValueBuffer) -> Void) {
        guard let name = selectedName else { return }
        var value = buffers[name] ?? KeyboardValueBuffer()
        operation(&value)
        buffers[name] = value
        expanded = false
    }

    private func clearConversion() {
        candidates = []
        conversionMessage = nil
        converter.reset()
    }

    private func commitReading() {
        update { value in
            if value.reading != nil { value.commitReading() }
        }
        clearConversion()
    }

    private func edit(_ action: KeyboardValueEditAction) {
        switch action {
        case .convert:
            guard let reading = buffer.reading, !reading.isEmpty else { return }
            switch converter.candidates(reading: reading) {
            case .candidates(let items):
                var seen = Set<String>()
                candidates = items.filter { seen.insert($0).inserted }
                conversionMessage = nil
            case .inputTooLong(let limits):
                candidates = []
                conversionMessage = "変換できるのは\(limits.maximumCharacters)文字・UTF-8で\(limits.maximumUTF8Bytes)バイトまでです。入力した値はそのまま残り、「文字を確定」で使えます。"
            case .noCandidates:
                candidates = []
                conversionMessage = "変換候補がありません。「文字を確定」で入力した値をそのまま使えます。"
            }
        case .commit: commitReading()
        case .cancelReading:
            update { $0.cancelReading() }
            clearConversion()
        case .delete:
            update { value in
                switch value.reading {
                case .some: value.deleteReadingBackward()
                case .none: value.deleteBackward()
                }
            }
            clearConversion()
        case .extend: extendingSelection.toggle()
        case .left, .right, .start, .end, .all:
            commitReading()
            update { value in
                switch action {
                case .left: value.moveLeft(extendingSelection: extendingSelection)
                case .right: value.moveRight(extendingSelection: extendingSelection)
                case .start: value.moveToStart(extendingSelection: extendingSelection)
                case .end: value.moveToEnd(extendingSelection: extendingSelection)
                case .all: value.selectAll()
                default: break
                }
            }
        }
    }
}
