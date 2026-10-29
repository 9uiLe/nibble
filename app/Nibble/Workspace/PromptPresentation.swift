import Foundation

enum PromptPresentation {
    static func error(_ error: WorkspaceError) -> String {
        switch error {
        case .conflict, .missingCard:
            "保存済みのプロンプトが変更されたか、削除されました。上書きやコピーは行っていません。入力はこの画面に残っています。"
        case .missingDraft, .staleCheckpoint, .invalidDraft:
            "この入力は別の画面で変更されたか、終了しています。現在の入力はこの画面に残っています。"
        case .emptyBody: "本文を入力してください。"
        case .emptyTitle: "タイトルを入力してください。"
        default: WorkspacePresentation.error(error)
        }
    }
}
