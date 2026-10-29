import Foundation
import SwiftUI

struct WorkspacePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(isEnabled ? Color(uiColor: .systemBackground) : Color(uiColor: .secondaryLabel))
            .background(isEnabled ? Color(uiColor: .label) : Color(uiColor: .systemGray5), in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

enum WorkspacePresentation {
    static func title(_ card: TextCard) -> String {
        title(card.title, body: card.body)
    }

    static func title(_ title: String, body: String) -> String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        let line = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if !line.isEmpty { return String(line.prefix(80)) }
        return "名前のない文章"
    }

    static func error(_ error: WorkspaceError) -> String {
        switch error {
        case .unavailable:
            "保存領域を開けません。端末のロックを解除して、もう一度お試しください。入力はこの画面に残っています。"
        case .readOnly:
            "この入口からは保存できません。nibble本体で文章を編集してください。"
        case .storage:
            "保存できませんでした。入力は残っています。空き容量を確認して、もう一度お試しください。"
        case .unsupportedSchema, .corruptData:
            "保存データを読み取れません。上書きは行いません。アプリを更新しても続く場合はサポートへご連絡ください。"
        case .missingCard:
            "元の文章がごみ箱に移されたか、見つかりません。作業中の内容は残っています。別の文章として保存できます。"
        case .missingDraft:
            "この作業は別の画面で終了しています。今の入力は画面に残っています。別の文章として保存するか、この画面の入力だけを破棄して閉じられます。"
        case .conflict:
            "保存済みの文章が変更されました。上書きやコピーは行っていません。今の入力を別の文章として保存できます。"
        case .staleCheckpoint:
            "同じ作業に新しい入力があります。今の入力を別の文章として保存するか、別の画面の作業を変えずに、この画面の入力だけを破棄して閉じられます。"
        case .invalidDraft:
            "この作業を更新できません。入力を別の文章として保存してください。"
        case .emptyBody:
            "本文を入力してください。作業中の内容は残っています。"
        case .emptyTitle:
            "タイトルを入力してください。入力はこの画面に残っています。"
        case .missingValues(let names):
            "「\(names.joined(separator: "」「"))」を入力して完成文を確認してください。"
        }
    }

    static func draftTitle(_ draft: WorkDraft) -> String {
        let name = title(draft.title, body: draft.body)
        switch draft.target {
        case .new: return "作成中：\(name)"
        case .edit: return "編集中：\(name)"
        case .prepare: return "差し替え中：\(name)"
        }
    }

    static func canRecoverIndependently(_ error: WorkspaceError?) -> Bool {
        switch error {
        case .conflict, .missingCard, .missingDraft, .staleCheckpoint, .invalidDraft: true
        default: false
        }
    }
}
