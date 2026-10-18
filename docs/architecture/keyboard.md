# スニペットキーボードの設計

キーボードは、他アプリの入力欄を離れずに保存済み本文を使うための拡張である。本体が作成・編集・管理、Keyboardが選択・全文確認・挿入を担う。挿入とコピーは別の操作であり、必要な権限と完了の意味も異なる。

## レイアウトと操作の意味

上部にコンパクトな集合選択と失敗時の再読み込み、中段に単一リストまたは全文、下部に短い成功結果・ページ・切替・終了を置く。失敗と権限案内は中段のスクロール領域の先頭へ置き、行と本文を残す。画面の読み順は[S09](../design/screens.md#s09-スニペットキーボード)、部品の責務はC45〜C48に定める。

行の主領域にはタイトルとプレビューを示し、一度のタップで挿入する。右端の「全文を見る」は挿入せず詳細を開き、詳細には戻る・ピン・コピー・挿入を置く。単一リストは個別カード/二列タイルより長いタイトルの幅を保てる。詳細をキーボード内に置くことで入力先との位置関係を維持する。

本文に差し替え印がある場合だけ、挿入・コピー前にキーボード内で名前ごとに一度ずつ値を入力し、完成文を確認する。同名の印を複数使っても値欄は一つで、完成文の全箇所を置き換える。値欄はボタンで選び、局所キーと変換候補で編集する。拡張自身に`UITextInput`やfirst responderを作らず、外部アプリの入力先を維持する。画面の読み順と編集操作は[S11](../design/screens.md#s11-キーボード内の変数値入力)に定める。利用不可なら理由を表示し、原文を送らない。確認前の編集と取消では入力先へ何も送らず、保存済み原文と利用値をDBへ書き戻さない。

OSのkeyboard背景とニュートラルな文字、主操作と挿入結果の青を使う。青い文字、主操作の塗りと文字、候補・選択の背景は[NibbleTheme](../../app/Shared/Interface/NibbleTheme.swift)のKeyboard専用色で定義し、通常文字の色対4.5:1以上をライト・ダーク双方で検査する。文字・太字・contrastは[固定表示](../design/rationale/fixed-interface.md)、hit領域は44×44pt以上を基準とする。高さはOSの必須制約を優先する。実値は[KeyboardView](../../app/NibbleKeyboard/KeyboardView.swift)と[controller](../../app/NibbleKeyboard/KeyboardViewController.swift)を正本とする。

## 操作結果と失敗

| 操作 | 完了として扱う時点 | 表示 |
| --- | --- | --- |
| 挿入 | `textDocumentProxy.insertText`の呼出しが戻った時点 | 「本文を送りました」と対象行の短いハイライト |
| コピー | フルアクセスを確認したうえで`UIPasteboard.setItems`の呼出しが戻った時点 | 「コピーしました」 |
| ピン留め／解除 | DBの書込transactionがcommitした時点 | 「ピン留めしました」または「ピン留めを解除しました」 |

成功の結果文と挿入行のハイライトは2秒で消す。挿入APIは入力先の受理・保存結果を返さないため、通知は本文の受け渡しを表す。コピーは`localOnly`で書き込み、クリップボードの読取による事後照合は行わない。

権限不足、本文の変更・削除、入力位置の変更、読込・書込失敗は理由を中段に表示し、成功のハイライトを出さない。失敗・権限案内には自動消去の期限を設けず、次の読込要求や利用操作などが通知を更新するまで表示する。権限不足ではコピー・ピン更新を実行しない。本文の変更・削除時は、一覧を更新して選び直すよう案内する。


## 構成と責務

controllerは入力先・権限・OS作用、Viewは配置と表示の寿命、`KeyboardTaskOwner`は操作の開始・重複・取消、modelは要求/操作ID・ページ・全文・通知、Reader actorは短命接続によるDB操作を所有する。UI/OSはMainActor、DBはactorで扱い、[共通保存層](../product-specification.md#保存形式と接続)の原文とtransaction契約を使う。

`KeyboardVariableFillView`は名前ごとの[KeyboardValueBuffer](../../app/Shared/Domain/KeyboardValueBuffer.swift)を所有する。bufferはUTF-8の原文、UTF-16の選択範囲と向き、未確定readingを扱い、Character境界を分断する範囲を拒否する。readingの訂正・候補選択・取消は局所値だけを変える。[KeyboardValueConversion](../../app/Packages/KeyboardValueConversion/README.md)の`JapaneseValueConverter`は通常のかな漢字候補だけを返し、host proxy・入力文脈・履歴・UIを持たない。候補要求が上限を超えても値を切り詰めず、原文のまま確定する経路を残す。辞書と変換は拡張内で利用し、通信と入力履歴の学習を行わない。

`KeyboardView`は詳細の切替・読込と通知期限のtask・アクセシビリティのフォーカスを保持する。一覧は`KeyboardBrowseView`、対象選択は`KeyboardFilterBar`、各行は`KeyboardSnippetRow`、全文は`KeyboardDetailView`、下部は`KeyboardControls`へ分割する。表示部品は個別ファイルへ置き、値だけの行要約・通知は比較可能な表示入力を受け取る。一覧と詳細を排他的に表示し、親Viewに一覧位置を保持して戻った位置を失わない。

## 共有データと読み取りの契約

正本はApp Group `group.nibble.9uiLe.com`の`Library/snippets.sqlite`、対応するschema versionは1と2とする。本体が保存領域を準備し、キーボードはDBの作成・schema移行・別保存先へのfallbackを行わない。未準備、未知schema、アクセス不能は利用者に失敗として伝える。

一覧と本文には読取専用接続を使う。一覧はピン留め優先、更新日時の降順、UUIDの昇順で最大50件を表示する。51件まで問い合わせて続きの有無を判定する。要約にはUUID、タイトル、本文の先頭180文字、ピン状態、更新番号`revision`を含む。全文は詳細を開く、または挿入・コピーする1件だけ取得し、未削除とrevision一致を照合する。

ピン操作は`SQLITE_OPEN_READWRITE`で存在するDBだけを開く。単一の書込transaction内でUUID・revision・未削除を条件に`pinned`と`revision`を更新し、更新後の要約を返す。タイトル、本文、更新日時、下書きは変更しない。commit後にUUIDごとの要約辞書を一度更新し、そこから詳細と一覧へ反映する。その後、同じフィルター・ページを再取得して並び順とページ境界を照合する。

書込接続は`SQLITE_FCNTL_PERSIST_WAL`でWAL・SHMを保持し、書込権限を持たない読取専用接続からも確定した更新を読めるようにする。

`KeyboardModel`はUUIDごとの辞書へ要約を一つずつ保持し、ページは要求に対応するID列、詳細は選択IDと本文取得の状態から導出する。revisionが変わると取得済み本文を無効にし、古いrevisionの遅延結果を拒否する。ピン解除で一覧の対象から外れても、開いている詳細の選択を維持する。使用状況は読まないため要約のusageはnilであり、0回という計測結果を作らない。`KeyboardModel.Message`は結果の意味を保持し、表示文は`KeyboardPresentation`が生成する。

## 状態と操作の寿命

一覧の要求世代`loadID`と、同じ世代の読込実行を区別する読込IDを照合する。古い読込の完了・失敗は現在のページに反映しない。再表示・更新・フィルター変更は先頭ページを要求し、詳細からの復帰は元の要求を保持する。キーボードが非表示になるとページ、全文、通知を解放する。

挿入・コピー・ピンは共通タスクID`keyboard.use`を使う。`screenBound`で画面の寿命に合わせてキャンセルし、`ignoreNew`で処理中の重複開始を防ぐ。モデルも操作ID、表示中であること、要求世代を照合してから結果を反映する。

挿入では本文の取得前後と確定時に、入力先のdocument identifierと選択位置の世代を照合する。変数のある挿入は取得開始時の文書IDを[KeyboardInputLease](../../app/Shared/Application/Contracts/KeyboardInputLease.swift)へ固定し、値入力を開く前に現在のIDと世代を再照合する。初期資格が成立しなければフォームを開かず、入力先が変わったことを示す。proxy自体を保存して配送先にしない。本文・選択のwill／did callbackはすべて世代を進め、保持した挿入資格を失効させる。IDが取得不能または別文書になった場合も失効する。外部文書AからBへ移りAへ戻っても、失効した資格は復活しない。局所の値欄切替は外部文書へ選択操作を送らない。取消、画面の非表示、要求変更、完了では資格を解放する。

値入力のフォームと挿入資格は、保存済み本文と入力先を再照合し、同期配送の判定が戻るまで維持する。終了処理は同じ確認IDのフォームだけに適用し、その後に資格を解放する。OS getterや配送中の通知で失効した資格は復活させない。

[KeyboardHostIdentity](../../app/Packages/KeyboardHostIdentity/Sources/KeyboardHostIdentity/include/KeyboardHostIdentity.h)はUIKitの公開getterをObjective-Cで読み、文書IDの取得不能をnullableとしてSwiftへ返す。SDK上のnonnull宣言を根拠にSwiftの非Optional UUIDへ変換しない。`NibbleKeyboardInsertText`は確定時に現在のproxyを取得し、その文書IDが期待値と一致することを確認してからadmissionを呼び、すべて成立した場合だけ`insertText`を一度呼ぶ。admissionは可視性、modelの有効性、世代とleaseを読むだけの同期判定とし、UIKit getterや非同期処理を挟まない。getter中の再入で資格が変わっても、この最終判定で拒否する。`insertText`の呼出し中にcallbackが来た場合は既に行った一度の配送結果だけを扱い、再配送しない。

コピーでは取得前後でフルアクセスを確認する。ピンでは権限確認後に書込を待ち、実際の共有領域へのアクセスはOSのsandbox制御に従う。commit済みの更新を後からのキャンセルで取り消さず、非表示・要求変更後には古い操作結果を表示しない。

詳細の読込は選択項目と詳細を開いたIDを照合する。同じ項目を閉じて再度開いても、前の読込結果を採用しない。期限付き通知は自身のIDを照合して消去し、古い期限処理が新しい通知を消さないようにする。

## 権限とOSの境界

拡張の`RequestsOpenAccess`はtrueとする。一覧・全文確認・挿入はフルアクセスなしで利用でき、コピーとピン更新は利用者の許可を必要とする。通信、入力履歴の保存、クリップボードの読取、入力欄の前後文脈取得は行わない。

`needsInputModeSwitchKey`がtrueの場合だけ地球儀を表示し、`handleInputModeList(from:with:)`へ接続する。閉じる操作は`dismissKeyboard()`を呼ぶ。OSが管理する音声入力、ホームインジケータ、セーフエリアを独自の部品・余白として複製しない。

secure入力、phonePad・namePhonePad、他社キーボードを禁止するアプリではOSの制御に従う。本体の利用案内で、キーボードの追加方法と利用できない入力欄を説明する。


## ビルドと評価

Keyboardは共有保存コード・Tasking・AppMacros、文書IDと最終配送の`KeyboardHostIdentity`、局所変換の`KeyboardValueConversion`を使い、編集用StoreとRiveをリンクしない。extension-safe API、最低iOS 26.0、Swift 6を要求する。nullable getter・再入・最終配送の境界は[standalone packageテスト](../ios-verification.md#keyboardの文書境界を単独で検証する)で確認し、実ホストの受理とは分ける。

1タップ1挿入、その他で0挿入、長文末尾、戻る位置、ピン変更/0件、権限不足、ページ・切替・終了を確認する。狭幅/縦横/ライト・ダーク、OS設定を変えても固定した表示、古い要求・入力先変更・書込競合を評価する。[操作手順](../ios-verification.md#キーボードの操作検証)と[条件付き測定](../performance-verification.md)に従い、未実施を完了にしない。

## 外部仕様

参照した公開仕様はAppleの[open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)、[custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)、SQLiteの[WAL](https://www.sqlite.org/walformat.html)。本契約は製品の採用範囲を定め、OS/審査の変更時は原典と実際のextensionを再確認する。
