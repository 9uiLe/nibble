# 0005：スニペットキーボード

- 状態：採用。実行検証の結果は別途記録する
- 設計基準日：2026-09-18
- 対象：NibbleKeyboard、本体の利用案内、共有保存領域、配布時の構成検査
- 最低対応：iOS 26.0。実行検証：iPhone / iOS 26.5 Simulator

## 目的

他アプリで文章を入力しながら、保存済みのスニペットを呼び出して使えるようにする。キーボードの切り替え後、項目をタップすると入力先へ本文を直接挿入する。各行のコピーボタンは本文をクリップボードへ書き込み、利用者が任意の場所へ貼り付けられるようにする。

スニペットを管理する本体、他アプリから保存する共有拡張、他アプリへ入力するキーボード拡張は、それぞれ独立したプロセスである。データの正本はApp Group内のSQLiteデータベースとし、キーボード用の複製データは持たない。

## 機能要件

| 利用場面 | 振る舞い |
| --- | --- |
| 有効化 | iOS設定でnibbleキーボードを追加する。本体の設定に追加手順・権限・制約を記載する |
| 呼び出し | 他アプリの入力欄からキーボードを切り替える。Nibbleを前面へ開かずに利用する |
| 選択 | 保存済みだけを「すべて」「ピン留め」で絞る。ピン留め、更新日時、UUIDの順で安定して並べる |
| 直接挿入 | 行の主操作で本文を1回挿入する。空白・改行・Unicodeを変換せず渡す |
| コピー | 独立したコピーボタンで本文を端末内のクリップボードへ書く。入力先への挿入は伴わない |
| 大量データ | 1ページ50件。前後のページへ移動し、全件の本文を保持しない |
| 更新 | キーボードの表示時と更新ボタンで読み直す。フィルター変更・再表示・明示的更新は先頭ページへ戻す |
| 入力への復帰 | システムのキーボード切替UIを利用する。独自の切替キーが必要な環境では地球儀ボタンを表示する |
| 失敗・空 | 未準備、空、読み込み失敗、選択後の変更・削除、権限不足を区別し、再試行や必要な設定を案内する |

下書き・削除済み項目はキーボードへ表示しない。スニペットの作成・編集・ピン留め変更・削除は本体で行う。キーボード内に検索文字入力や独自IMEは設けず、フィルターとページ操作で探す。周辺の入力文から自動検索する機能も持たない。

## iOSの権限と制約

| 条件 | 設計 |
| --- | --- |
| フルアクセスなし | 共有コンテナを読み取り専用で開き、保存済み本文を直接挿入する |
| フルアクセスあり | 直接挿入に加えてコピーを使える。`hasFullAccess`は実行時にも確認する |
| コピーの許可なし | 権限が必要であることを説明し、コピー成功を表示しない。直接挿入は使える |
| 利用不可の入力欄 | パスワードなどのsecure入力、phonePad・namePhonePad、他社キーボードを禁止するアプリはiOSの制御に従う |
| 入力先の制限 | 入力先アプリは長さ・改行・文字種を制限できる。拡張が原文を渡すことと、入力先が受理することを分ける |
| キーボードの追加 | 利用者がiOS設定で行う。アプリは自動有効化や非公開の設定URLを使わない |

`RequestsOpenAccess`はコピーを利用可能にするためtrueとする。フルアクセスは利用者の選択であり、直接挿入の必須条件にはしない。ネットワーク通信、入力履歴の記録、クリップボードの読み取り、入力欄の前後の文章の取得は実装しない。

現行のApple資料は、通常のキーボードから共有コンテナを読み取り可能と説明している。古いApp Extension Programming Guideでは共有領域全体にフルアクセスが必要とされているため、保存領域の読み取り可否は対象OSで実測する。クリップボード利用の条件は同Guideを根拠とし、フルアクセスの有無を実際のキーボードで検証する。

## 構成と責務

| 構成 | 責務 |
| --- | --- |
| `NibbleKeyboard` target | `com.apple.keyboard-service`として本体に同梱する。Bundle IDは`nibble.9uiLe.com.keyboard` |
| `KeyboardViewController` | `UIInputViewController`の寿命、キーボード切替、権限、入力先の識別、挿入・コピーの副作用、タスクを所有する |
| キーボードのSwiftUI View | フィルター、一覧、読み込み・失敗・結果、ページ操作を表示し、利用者の操作を通知する |
| `KeyboardModel` | 読み込み状態、現在のページ、操作の競合、非同期結果の採用条件を管理する |
| 読み取り専用Reader | actor内でSQLiteを読み、保存済みの要約と選択した本文を返す。作成・変更APIを持たない |
| 本体・共有拡張のStore | データベースとschemaを作成・更新し、読み取り専用接続が使うWALファイルを準備する |

既存のSQLite接続処理と保存済みスニペットの問い合わせを共用する。キーボードはDBの作成、schema migration、保存、属性変更を行わない。Riveと編集画面はリンクせず、Tasking・AppMacrosと表示に必要な共有コードだけを利用する。

App Groupは`group.nibble.9uiLe.com`を3 targetで共有する。Keyboard targetはiOS 26.0、Swift 6、strict concurrency complete、default isolation nonisolated、extension-safe APIでビルドする。UIと副作用はMainActor、DB処理はReader actorで実行する。

## 保存領域と読み取り

キーボードは`SQLITE_OPEN_READONLY`で接続し、対応するschema versionだけを読む。WALはSQLiteの未checkpointの更新を保持するファイル、SHMは接続間の索引を共有するファイルである。書き込み側は`SQLITE_FCNTL_PERSIST_WAL`を設定し、最後の書き込み接続を閉じてもWAL・SHMを保持する。これにより共有領域へ書き込めないReaderも、確定済みの更新を読める。

書き換わるデータベースに`immutable=1`は指定しない。SQLiteの読み取りtransactionで1ページを取得し、本文は選択時に読み直す。削除済みや、一覧のrevisionと異なる項目は操作を中止し、更新を案内する。タイトルとプレビューだけを50件保持し、本文は1操作につき最大1件とする。読み取り接続は各要求の終了時に閉じる。

保存領域が未作成なら本体での準備を案内する。ロック中のData Protectionなどによる読取失敗は、空データや別の保存先へ置き換えず再試行可能なエラーとする。本体・共有拡張の完全保護の方針を引き継ぐ。

## 状態・タスク・副作用

- 表示中のcontrollerが読込タスクと操作タスクを持つ。画面離脱でキャンセルし、モデルの世代も無効化する。
- 読込は最新要求を採用する。フィルター変更直後は読み込み状態とし、旧ページを新フィルターの空結果として表示しない。
- 挿入・コピーは実行中の重複要求を受け付けない。完了後の新しいタップは新しい操作として受け付ける。
- 本文取得後に、キャンセル、画面の寿命、操作ID、項目revisionを確認する。挿入では入力先のdocument identifierと選択・本文変更の世代も照合する。
- 入力先を移動したりキーボードを閉じたりした後に届いた結果から、挿入・コピー・成功表示を実行しない。
- 挿入は`textDocumentProxy.insertText`、コピーは`UIPasteboard`への書き込みに限定する。コピーは本体と同様に端末内だけへ渡す。
- 通知は次の操作まで表示する。期限用タイマー、定期polling、バックグラウンド同期は持たない。

## レイアウトと操作の意味

上部に対象選択と更新、中央にスクロールする一覧、下部にページ移動と結果を置く。主操作は内容の領域、コピーは独立した44pt以上のボタンとし、タップ範囲が重ならないようにする。フィルターは色で選択を示し、チェックマークは付けない。背景と区切り線、アクセントは本体の表示方針を使う。

キーボードの幅と基本の高さはiOSに従い、可変領域は一覧に割り当てる。短い高さでも操作が残るよう、上部・下部を固定し、一覧を縮めてスクロールさせる。大量の全文、説明アニメーション、シートの重ね表示は持たない。案内の長文は本体の設定画面で読む。

読み上げ名に「挿入」「コピー」「前のページ」「次のページ」を明示する。文字サイズ・太字・コントラストの製品方針は既存の`NibbleInterface`に従い、iOSが提供するキーボード切替・権限・入力欄の挙動を尊重する。

## 配布と初回設定

Apple Developerに`nibble.9uiLe.com.keyboard`を登録し、App Groupsを有効にして`group.nibble.9uiLe.com`を関連付ける。配布profileはキーボードtargetにも必要となる。識別子はGitで管理し、認証設定・秘密鍵・profileは既存の秘密情報規約に従って扱う。

配布スクリプトは本体・共有拡張・キーボードの3 bundleについて、識別子、version、最低OS、SDK、privacy manifest、輸出申告、extension pointを検査する。未知の拡張や欠落を許可しない。Simulatorの成功を実際の署名・TestFlight配信成功とは扱わない。

## 実装と受け入れの順序

1. 読み取り専用DB接続と最小のKeyboard targetを実装し、フルアクセスなしの読込と他アプリへの挿入を確認する。
2. モデルの競合・キャンセル、一覧・フィルター・ページ・コピー、本体の案内、配布構成を実装する。
3. 原文、削除・変更後の拒否、遅い読込、入力先変更、画面離脱、連打、再試行をテストする。
4. iOS 26.5の別アプリで、権限なしの挿入、権限ありのコピー、再表示時の更新、システムキーボードへの復帰、狭い幅・縦横・ライト/ダークを画像と録画で確認する。
5. Releaseビルド、全製品テスト、Nix共通検査、設計照合、拡張サイズと表示・操作の実行条件を記録する。

未実施の条件は検証記録へ残す。Apple側の登録、実機のメモリ上限、すべての入力先アプリでの文字受理は、Simulator試験で保証しない。

## 根拠

- [Apple：Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) — extension構成、有効化、切替キー、メモリと寿命。
- [Apple：Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface) — 入力欄の制約、可変サイズ、システムのレイアウト。
- [Apple：Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) — 共有領域の読み取りとフルアクセスの境界。
- [Apple：Handling text interactions](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards) — proxyによる挿入と入力・選択変更の通知。
- [Apple：Custom Keyboard（archive）](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) — pasteboard利用条件。共有領域の記述は現行資料と区別する。
- [SQLite：Write-Ahead Logging](https://www.sqlite.org/wal.html)・[WAL file format](https://www.sqlite.org/walformat.html) — 読み取り専用接続とWAL・SHMの寿命。
