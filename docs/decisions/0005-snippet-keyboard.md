# 0005：スニペットキーボード

状態：採用。設計基準日：2026-09-19。最低対応OS：iOS 26.0。

## 目的と提供範囲

他アプリで入力を続けながら、タイトルから保存済みスニペットを選び、本文を直接挿入する。作成・編集・検索は本体が担当する。キーボードでは全文確認、コピー、ピン留めも提供する。HTMLモックは構成と操作の参考とし、SwiftUIとUIKitで実装する。モックの入力先、端末枠、説明、サンプルは製品へ含めない。

保存済みの「すべて／ピン留め」を50件単位で表示し、下書き・削除済みは含めない。データ複製、同期、独自IME、検索、カテゴリは追加しない。[画面構成](../design/screens.md#s09-スニペットキーボード)、[部品台帳](../design/components.md)、[利用手順](../mvp.md#キーボードから使う)へ対応付ける。実行結果は[検証記録](../keyboard-validation.md)と[今回の改修記録](../keyboard-readability-validation.md)で区別する。

## 用語と操作

| 操作 | 条件と結果 |
| --- | --- |
| 行のタイトル・本文プレビュー | 一つのButton。本文を一度だけ`textDocumentProxy.insertText`へ渡す。フルアクセス不要 |
| 行末の「…」 | 隣接する独立Button。挿入せず、同じキーボード内で全文を読む詳細へ切り替える |
| 一覧に戻る | 保持した一覧を再表示する。フィルター・ページとScrollViewの位置を維持する |
| 詳細の入力する | 本文を再取得・照合して挿入し、成功後に一覧へ戻る |
| 詳細のコピー | フルアクセスを前後で確認し、`UIPasteboard`へ`localOnly`で本文を書く |
| 詳細のピン留め／解除 | フルアクセスを確認し、選択時の更新番号が一致する保存済み項目だけ更新する |
| すべて／ピン留め | 集合を変更し先頭ページを取得する |
| 前後のページ | 同じ集合の前後50件を取得する。1ページだけなら操作を省く |
| 更新・再表示 | 選択フィルターの先頭ページを再取得する |
| キーボード切替・終了 | `needsInputModeSwitchKey`がtrueの場合に地球儀を提供。閉じるはOSへ非表示を依頼する |

未許可のコピー・ピン操作は設定案内を表示し、副作用を実行しない。本文の空白・改行・Unicodeは変換しない。挿入APIは入力先の保存・受理結果を返さないため、通知は「入力先へ本文を渡しました」とする。コピーはOSへの書込後、ピン留めはDB commit後に成功を表示する。

## レイアウトと操作の意味

| 要素 | 構成・配置理由 | 代替案と評価条件 |
| --- | --- | --- |
| C45 対象選択 | 上部にコンパクトな2択セグメントと更新。見た目の面より大きい44pt以上のタップ領域を持つ | 全幅Pickerより内容幅を優先。選択状態をVoiceOverでも伝え、狭幅・拡大文字で確認する |
| C46 一覧 | 一つの13pt角丸の面に薄いDivider。タイトルはmediumのsubheadline、本文はsecondaryのcaption・1行。小さいピンは属性を示す | 独立カードと常設「入力」は識別幅を減らすため廃止。2列タイルは長い名前を圧迫するため不採用 |
| C46 行の操作 | タイトル・プレビュー全体が入力Button、右端44pt幅が全文と操作Button。Buttonを入れ子にせず、行へtap gestureを追加しない | 親行のtapと子操作の競合を避ける。1タップ1挿入、「…」で0挿入を確認する |
| C46 詳細 | 上部に戻る・ピン、中央にタイトルとスクロール全文、下部にコピーと青い主操作「入力する」 | シートは拡張の外へ広がる制約があるため不採用。固定操作と可変本文を分け、長文末尾へ到達できることを確認する |
| C47 結果と補助操作 | 下部で控えめなnibbleと通知を入れ替える。挿入後の行背景と通知は2秒。ページ・終了を保持する | ダイアログで次の選択を遮らない。失敗・権限案内は次の操作まで残し、全文を読み上げる |
| C48 利用案内 | 本体の設定で追加方法、全文、コピー・ピンの権限、入力先の制約を説明 | 小さな入力面に設定手順を常設しない |

背景は`UIInputView.Style.keyboard`、SwiftUIホストは透明。リスト面は`tertiarySystemBackground`、主文字はprimary、補助文字はsecondaryを使う。青は詳細の入力と挿入後の短い行背景に使い、色だけに頼らず結果文を併用する。Liquid Glassの追加や独自のホームインジケータは行わない。

左右10〜12ptの余白、行高54pt以上を基準とし、行の幅は表示領域に合わせる。既存の高さ288pt、compact vertical size classでは196ptを維持し、制約優先度750でOSの必須制約を優先する。全文は固定高へ詰めずスクロールする。OSの地球儀・音声入力・セーフエリアを独自描画しない。

キーボードも本体と同じ[固定表示方針](../design/decisions/0002-fixed-interface.md)を維持し、文字サイズはlarge、太字・コントラストは標準値に固定する。ライト／ダーク外観には追従する。読み上げ名は対象と操作を示し、詳細の戻ると呼出元へフォーカスを移す。通知はannouncementで伝える。独自アニメーションを追加しない。

## 構成と責務

| 所有者 | 責務 |
| --- | --- |
| KeyboardViewController | 入力先と権限、モデル、高さ、地球儀UIButtonを所有し、表示寿命とOS操作を接続 |
| KeyboardView | 一覧を破棄せず詳細へ切替。読込・全文・通知期限はSwiftUI `.task`、操作はViewTaskStoreで所有 |
| KeyboardModel | 要求世代、ページ、詳細の1件分の本文、通知、操作IDを保持。各操作を完了までawait可能にする |
| KeyboardReader | actor内で短命の接続を使う。読取専用で一覧・本文を取得し、ピンだけ既存DBへの書込接続を使う |
| SnippetLocation / SnippetQueries / SQLiteDatabase | 既存の共有DB、要約・原文取得、接続とtransactionを共用する |

UIとOS操作はMainActor、DB処理はactorで行う。行はスニペットUUID、詳細読込は開くたびに新しいUUIDで識別する。入力先の文章・クリップボードは読まない。

## 共有データと読み取りの契約

正本はApp Group `group.nibble.9uiLe.com`の`Library/snippets.sqlite`。保存形式・schema version 1・並び順・50件の取得上限は維持する。要約はUUID、タイトル、先頭180文字、ピン状態、revisionを含み、全文は開いた／利用した1件だけ取得する。本文取得は未削除とrevision一致を照合する。

ピン留めは`SQLITE_OPEN_READWRITE`で既存ファイルだけを開き、CREATE、schema移行、別保存先へのfallbackを行わない。単一write transaction内でUUID・revision・deletedを条件にpinnedとrevisionを更新し、結果のsummaryを返す。本文、更新日時、下書きは変更しない。DB commit後に一覧を同じフィルター・ページで再取得する。並び順や集合の変化で項目が移動する場合は、現存するリスト範囲でスクロール位置を維持する。

書込接続も`SQLITE_FCNTL_PERSIST_WAL`を使い、書込不可の読取専用接続が確定更新を読めるWAL・SHMを保持する。保存領域は引き続き本体が準備する。未知schema・未準備・読取不能は明示的な失敗にする。

## 状態と操作の寿命

`loadID`は要求の世代、`readID`は同じ要求内の実行を識別する。古い読込の完了・失敗は現在のページへ反映しない。再表示・更新・フィルター変更は先頭ページ、詳細からの復帰は元の要求を保持する。非表示時はページ・全文・通知を解放する。

挿入・コピー・ピンは`keyboard.use`のscreenBound / ignoreNewとモデルの操作IDで重複を防ぐ。挿入は取得前後で入力先document identifierと選択世代を照合する。コピーは取得前後でフルアクセスを照合する。ピンは許可確認後に書込をawaitし、OSのsandboxにより権限取消時の書込も拒否される。確定済み書込をキャンセルで巻き戻さない。非表示・要求変更後に古い結果を表示しない。

全文読込は選択UUIDと開いたときのIDを照合し、閉じて同じ項目を再度開いた場合も古い結果を採用しない。開いたこと自体はOSへの挿入・コピーを伴わない。期限付き通知はIDごとに2秒待ち、新しい通知を古い待機から消さない。失敗は成功の行背景を持たない。

## 権限とOSの境界

`RequestsOpenAccess=true`と既存の権限設定を維持する。利用者がフルアクセスを選ぶとコピーと共有領域のピン更新が使える。挿入・全文確認・一覧の読取は許可不要。通信・入力履歴・クリップボード読取・入力欄の前後文脈取得は行わない。

secure入力、phonePad・namePhonePad、他社キーボードを禁止するアプリではOSの制御に従う。挿入の受け渡しと、入力先が受理・保存したことは別の結果として扱う。

## ビルドと評価

Bundle ID `nibble.9uiLe.com.keyboard`、extension point `com.apple.keyboard-service`、iOS 26.0、Swift 6、strict concurrency complete、extension-safe APIを維持する。Tasking・AppMacrosと既存の共有コードを利用し、Riveや編集用Storeはリンクしない。

Xcode 26.5 / iOS 26.5 Simulatorで、挿入回数、独立した「…」、長文、ピン追加・解除と0件、権限不足、更新・ページ・切替・終了、狭幅・縦横・ライト／ダーク・拡大文字を評価する。モデルの遅延・キャンセル・失敗はテストで照合する。VoiceOverの実操作と実機性能は実施範囲を別途記録し、静的情報の確認で代替しない。

## 外部仕様

- [Apple: Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) — 読取は許可され、共有領域の書込はフルアクセスが必要。2026-09-19確認。
- [Apple: Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) — 入力接続と切替、拡張の制約。
- [SQLite: WAL file format](https://www.sqlite.org/walformat.html) — 読取専用接続とWAL・SHM。
- [従来構成の比較資料](../../research/08-keyboard-interface.md) — 初期のキー構成と根拠。今回の採用構成は本書を正とする。
