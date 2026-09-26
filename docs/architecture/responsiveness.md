# 画面の状態と応答性

nibbleは入力中の原文と保存済みの利用対象を分け、非同期の結果が届く時点で対象と要求を照合する。画面は表示と操作の寿命、Applicationのモデルは結果の採否、保存actorは接続とtransactionを所有する。製品上の成立条件は[製品仕様](../product-specification.md)、測定条件は[性能検証](../performance-verification.md)に定める。

## 状態の所有と更新経路

| 入口・操作 | 正本と寿命 | 結果の採否と表示 |
| --- | --- | --- |
| 本体の一覧・検索・整理 | sceneの`LibraryModel`が選択集合、検索語、通知と編集提示を所有する。`LibraryReadState`が集合別の取得上限と読取snapshotを保持する | 読取要求IDと条件を照合し、遅れた検索結果を現在の画面へ反映しない。保存や整理の結果は集合と必要な検索を再取得する |
| 編集・下書き・Markdown | 編集シートの`EditorModel`が入力、sequence、終了状態を所有する。Viewはフォーカス、本文選択、表示モード、補足シートを所有する | 自動保存は固定した下書きsnapshotを渡し、DBが同一sessionの新しいsequenceだけを適用する。Markdown解析は現在の本文のUTF-8と一致する結果だけを表示する |
| 変数の追加・利用 | 編集中の選択位置は`EditorBodyField`、名前と印の規則は`VariableName`と`SnippetVariables`、利用時の入力値とプレビューの展開状態は`VariableFillView`が所有する | 確定時に本体またはKeyboardのモデルが利用対象を再確認する。未確定の値を保存済み原文へ書き戻さない |
| Share Extension | `ShareViewController`が提示と取込Taskを、`SharedDraftLoader`がprovider入力から下書き保存までを所有する | 共有元への終了前に提示資格を確認する。保存済みの下書きはUIの離脱で取り消さない |
| Keyboard Extension | controllerが入力先、`KeyboardModel`が一覧・詳細・変数利用を所有する | 読込世代、項目revision、入力先文書IDを確定時に照合し、別の入力欄へ送らない |
| 権利・説明イラスト | sceneの`ProSubscription`がStoreKit更新を監視する。各案内画面が`IllustrationPlayback`の可視性を所有する | 権利は検証済み取引から再評価する。説明画面を離れるか非表示になれば再生を止める |

保存済み本文・下書き・使用情報はApp GroupのSQLiteが正本である。選択、フォーカス、通知、入力途中の変数値は表示の寿命に閉じる。表示用の見出し、検索要求、完成文は正本から導出する。入力値を別のモデルへ複製して同期しない。アカウントと通信同期は製品に存在しない。

## Taskの寿命と競合

`LibraryTaskOwner`は本体scene内の操作をIDで管理する。検索・更新・コピーは同じIDの先行Taskを取消し、保存や整理などの確定操作は連打を受け付けない。編集提示は画面に属し、背景移行や画面離脱で提示要求を無効にする。保存層へ受理された書込は画面離脱後も整合性を保つ。モデルは取消要求だけに依存せず、結果を反映する直前にも要求IDと現在の状態を確認する。

`SnippetEditor`の自動保存は`.task(id: snapshot.sequence)`で入力snapshotに結び、`EditorTaskOwner`が保存・保持・破棄の終了操作を一件ずつ所有する。終了中は入力を受け付けず、成功時だけ閉じる。失敗時は入力を残して編集へ戻す。Shareの取込Taskはcontroller、Keyboardの読込Taskは入力面の表示が寿命を決める。独立した操作を一つのloadingフラグへまとめない。

SwiftUIの`.task(id:)`はViewの消失やID変更に伴い取消される。取消済みTaskの完了や後始末が新しい要求を変更しないよう、結果を適用する側の照合も必要である。[Appleのtask(id:)資料](https://developer.apple.com/documentation/swiftui/view/task%28id%3Aname%3Apriority%3Afile%3Aline%3A_%3A%29)を参照する。

## 更新、UIKit、配置

Viewの値生成、`body`の評価、レイアウト、描画・合成は異なる段階である。重い処理を疑う場合は、入力と更新頻度、影響するView、処理時間を対応させる。本文の解析は原文が変わったときにまとめて実行し、一覧は保存層が順序付けた上限付きページを表示する。軽い表示文字列をStateに複製せず、キャッシュを増やす場合は入力・無効化条件・寿命・上限を定める。[AppleのSwiftUI性能資料](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)を測定の入口とする。

本文編集は選択範囲、IME、取り消し履歴が必要なため`UITextView`を`MarkdownSourceInput`から接続する。生成時にdelegateを設定し、更新時は本文・選択・フォーカスの差分だけ反映する。同じ選択範囲をBindingへ書き戻さない。提案幅で必要高さを返し、内容変更時にintrinsic sizeを無効化する。[AppleのUIViewRepresentable資料](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/updateuiview%28_%3Acontext%3A%29)と[サイズ提案資料](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits%28_%3Auiview%3Acontext%3A%29)を参照する。

通知はsceneの補助windowが保持する。位置はsafe areaに応じて更新し、同じモデルと操作所有者ならhostのroot viewを再設定しない。モデルの変更はObservationで表示へ届く。RiveはResourceと再生Sessionを分け、Viewportの生成・更新・破棄を管理する。KeyboardのOS入力切替ボタンとShareのhostも、それぞれのcontrollerの寿命に置く。

画面は内容の自然な高さとsafe areaを使い、本文と入力欄をスクロール領域へ、必要な主要操作をキーボード上のsafe areaへ配置する。文字数・変数件数・取得状態で要素が増えても、スクロール終端を操作部の下へ隠さない。固定寸法は操作領域やアイコンなど意味のある制約に限る。画面ごとの読み順と評価条件は[UI設計](../design/README.md)に定める。

## 開発時の確認

変更した所有者と寿命を上の表へ当てはめ、要求の後着、連打、画面離脱、入力先変更を再現できるテストを選ぶ。共通UIは本体・Share・Keyboardの利用先と、短文・長文・空・失敗・キーボード表示を確認する。`python3 scripts/verify.py plan --base origin/main`で工程を確認し、[iOS実行手順](../ios-verification.md)に従って専用Simulatorで実行する。性能の改善率は[同一条件の比較](../performance-verification.md#比較条件)が成立した場合だけ報告する。
