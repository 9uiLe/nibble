enum PreparedKeyboardMessage {
    static func status(_ status: PreparedKeyboardModel.PreviewStatus) -> String {
        switch status {
        case .loading: "保存済みの全文を確認しています。"
        case .ready: "全文を確認し、下のボタンでこの入力先へ挿入します。"
        case .checking: "保存済みの内容と入力先を確認しています。"
        case .sent: "挿入を一度実行しました。反映された内容は入力先で確認してください。"
        case .refused(let reason): refusal(reason)
        }
    }

    static func readFailure(_ error: WorkspaceError) -> String {
        switch error {
        case .conflict, .missingCard:
            "文章が変更・削除されました。一覧に戻り、再読み込みして選び直してください。"
        case .unsupportedSchema, .corruptData:
            "保存済みの文章を読み取れません。本体で確認してください。保存データは変更していません。"
        default:
            "文章を読み取れません。nibble本体で文章を保存してから再読み込みしてください。"
        }
    }

    private static func refusal(_ reason: PreparedKeyboardModel.Refusal) -> String {
        switch reason {
        case .inputChanged, .unavailableInput, .deliveryRefused:
            "入力先が変わったか確認できないため、挿入していません。一覧から文章を選び直してください。"
        case .sourceChanged:
            "文章の内容またはピン留めが変わりました。一覧を再読み込みして選び直してください。"
        case .unsupportedContent:
            "この文章はここから挿入できません。nibble本体で完成文を確認してコピーしてください。"
        case .cancelled:
            "操作を中止しました。挿入していません。一覧から選び直せます。"
        case .departed:
            "キーボードを離れたため挿入できません。一覧から文章を選び直してください。"
        case .storage(let error): readFailure(error)
        }
    }
}
