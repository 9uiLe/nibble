# 共有データと操作境界の検証

## 対象と判断

対象は本体`Nibble`、共有拡張`NibbleShare`、キーボード`NibbleKeyboard`の共有データ経路である。採用する責務と契約は[製品設計](decisions/0002-mvp-app.md)、キーボードの状態は[キーボード設計](decisions/0005-snippet-keyboard.md)に定義する。

比較元は`634e381721be39bc0f6780a215dc770c97d02ef2`、採用する製品ソースは`359b64278c3a4c10cc76bdd273f833b16313a0b7`。検証runの開始・終了時のSHA-256を採用コミットと照合する。実行環境はXcode 26.5（17F42）、Swift 6.3.2、iPhone 17 Pro Simulator、iOS 26.5（23F77）。最低対応OSは26.0を維持する。

### 調査範囲

| 対象 | 確認と判断 |
| --- | --- |
| 本体の一覧・検索・削除一覧 | LibraryView、LibraryScreen、LibraryModel、LibraryTaskOwner、行・フィルター・通知の接続を確認。要約の件数制限、独立した画面要求、行UUID、操作所有者を維持する |
| 本体・共有の編集 | SnippetEditor、EditorModel、Draft、ShareViewControllerの作成・入力保存・終了・共有元復帰を確認。編集モデルの依存をDraftEditingへ限定する |
| キーボード | controller、View、Model、Readerのページ取得・本文取得・入力先照合・権限・非表示を確認。読取状態と実行IDをモデルで管理する |
| 共有保存 | Store、Queries、Schema、SQLiteDatabase、保存先の解決を確認。接続所有、SQL読取、変更transaction、下書きtransactionを分離する |
| 描画・資源 | 比較View、boundedなページ、AboutIllustration、RiveResource・RiveCanvasの所有、targetのリンク構成を確認。今回変更する共有保存のために画面・Rive・レンダラーを置き換える根拠はない |
| 対象外 | 説明・設定の静的文章の再設計、外部パッケージ内部、配布認証・スクリプト、UI設計ツール自体の全面調査。変更目的に関係する接続だけを確認する |

### 原因と優先度

| 優先度 | 確認した原因 | 対応 |
| --- | --- | --- |
| 高 | キーボードの同一loadID内で読込が重なると、先に開始した処理の遅い結果・失敗も採用できる | loading状態に実行IDを持たせ、世代と実行IDを両方照合する |
| 中 | 削除・復元の通知対象が画面のキャッシュから選ばれ、別接続の更新後も古いタイトルを使う | 変更と通知対象の読取を同じ書込transactionへ入れる |
| 中 | 下書き再開時に保存済み全文を読み、終了照合でも新しいsequenceに不要な旧全文をStringへ変換する | 再開の存在確認はscalar、終了の内容取得は同sequenceだけとする |
| 中 | 一覧・編集モデルが具象Store全体を参照し、必要な操作範囲が型に表れない | LibraryStorageとDraftEditingを定義し、入口で具象Storeを接続する |
| 低 | 本体・キーボードが本文利用時に編集用Snippet全体を構築する | 未削除・revisionを検査する本文専用の読取を共用する |

DBが保持する原文、schema、一覧件数、画面のidentity、独立したタブの状態、OS操作の場所は維持する。actorの分割による並列書込は採用しない。同じDBの書込はSQLiteが直列化するため、接続数や同期箇所の増加を正当化する測定結果がない。キーボードの短命な読取接続も、WALとプロセス寿命の契約に従って維持する。

## 状態・処理・副作用

- `SnippetStore`は接続を所有し、同じ接続の操作を直列化する。同期のSQL helperは接続を保持せず、TaskやOS作用を開始しない。
- 一覧と編集のモデルは操作をawaitする。受理済みの書込は完了させ、保存済みrevisionと下書きsequenceの競合をDB transaction内で判定する。
- キーボードは非表示・要求変更で世代を無効化し、読込の重複は実行IDで区別する。挿入・コピーは独立した操作IDと現在ページ内のUUID・revisionを検査する。
- クリップボード・挿入・共有元への終了通知はMainActorのOS adapterで実行する。DBの成功を確認する前にUIへ成功を通知しない。

## 検証方法

追加した回帰テストは、同一要求の後着した成功・失敗、読込取消後の再試行、ページ外項目の利用拒否、コピー中の入力先変更・取消、別接続の編集後の削除通知、完全削除失敗時のtransaction、原文のUTF-8を扱う。長文下書きでは新しいsequence・同じsequence・異なる原文・異なる対象UUIDを区別する。

Release製品テスト、本体の標準UI driver、共有保存、キーボードの利用を専用Simulatorで検証する。媒体の原本と抽出フレームを確認し、実施した範囲を記録する。性能比較は製品コードをコンパイルした補助実行ファイルで行い、UIのend-to-end遅延や描画時間とは区別する。

### Releaseテスト

`20260918T191050Z-test-45e637`は90テスト（パラメーター展開後107件）、10 suiteが成功し、失敗・skipは0件だった。比較元は82テスト（展開後94件）。追加8テストは上記の具体的な競合・整合性を検査する。本体・共有拡張・キーボードを同じschemeでコンパイルした。

先行する`20260918T190402Z-test-0ea20f`も90件成功した。最終コードでは、通知を出さないピン操作から余分なタイトル読取を除き、上記の別runで再検証した。初回cache移設による古い絶対パスへの警告、署名済み依存のstrip省略、AppIntents未使用の警告を記録した。製品ソースのコンパイルエラーはなかった。

### 保存処理の比較

`artifacts/refactor-baseline/`に、比較元ソースのbyte単位のコピーとhash、`Benchmark.swift`、コンパイル引数、seed、全sampleを保存した。変更後ソースもbyte単位で固定して比較した。補助実行ファイルはApple Swiftで`-Osize -whole-module-optimization -swift-version 6 -strict-concurrency=complete`、`arm64-apple-ios26.0-simulator`向けにコンパイルし、専用iOS 26.5 Simulator上で実行した。

各操作は5回warm-up後に100回計測。baseline / final / final / baseline / baseline / finalの順に、同一seedのコピーを使って交互に3プロセスずつ実行した。集計は各版300回の中央値とp95（昇順285番目）。製品ビルド・テスト・UI driverを同時実行しなかった。

データは保存済み10,000件、ピン200件、長文1件620,000 UTF-8 byte。各反復の下書き準備は時間計測外とし、測定する操作のawait開始から結果取得までを測る。自動保存後に同じsequenceを閉じる操作と、未永続の新しいsequenceを閉じる操作を分ける。

| 操作 | 比較元 中央値 / p95 ms | 変更後 中央値 / p95 ms |
| --- | --- | --- |
| 検索・要約50件 | 0.169 / 0.264 | 0.139 / 0.227 |
| キーボードのページ | 0.428 / 0.609 | 0.370 / 0.480 |
| 長文のコピー用取得 | 0.621 / 0.742 | 0.631 / 0.714 |
| 既存の長文下書き再開 | 1.191 / 1.388 | 0.591 / 0.651 |
| 新しいsequenceの保持 | 1.022 / 1.241 | 0.473 / 0.699 |
| 同じsequenceの保持 | 0.809 / 0.943 | 0.863 / 0.978 |
| ピン変更 | 0.337 / 0.456 | 0.382 / 0.520 |

不要な本文取得を除いた長文下書きの再開・新入力保持は、この条件の中央値で約50%・54%短縮した。同じsequenceの照合とピン変更では小さな増加があり、すべての処理を高速化したとは評価しない。変更していない検索やページ取得にも差があるため、短時間の差を一般的な改善率へ外挿しない。本文コピーはほぼ同程度だった。

補助プロセス終了時のphysical footprintは比較元10,228,864〜10,294,400 byte、変更後10,261,632〜10,278,016 byte。peak RSSは比較元41,648,128〜41,680,896 byte、変更後41,631,744〜41,648,128 byte。メモリ削減を示す結果とは判断しない。これは保存処理の補助プロセスであり、SwiftUI・Rive・キーボード拡張全体のメモリではない。

### 容量

同じXcode・Release設定のSimulator向け実行ファイル（arm64とx86_64）を比較した。テストbundle、ビルドcache、dSYMを含めず、3つの製品実行ファイルを測る。比較元は上記のbaseと入力が一致するUI runの成果物である。

| 実行ファイル | 比較元 byte | 変更後 byte |
| --- | --- | --- |
| Nibble | 5,050,080 | 5,076,480 |
| NibbleShare | 1,997,120 | 1,998,016 |
| NibbleKeyboard | 1,608,816 | 1,607,440 |
| 合計 | 8,656,016 | 8,681,936 |

合計は25,920 byte、約0.30%増加した。arm64の`__TEXT`区画は3 targetとも同じサイズだったが、区画にはalignmentがあるため命令数の一致は意味しない。依存、Riveアセット、リンクするtargetは変更していない。この数値はSimulatorの実行ファイルであり、App Storeの圧縮・thinning後の配布容量ではない。責務と競合制御の明確化を、この小さな容量増加とともに評価する。

### 共通検査

ローカルApple Silicon Macで`nix flake check --no-update-lock-file --print-build-logs`の全7 checkが成功した。Swift規約57 source、UI設計照合、文書リンク、Rive契約、Python回帰、Nix・workflow規約を含む。Linux CIとiOS実行を同じ結果として扱わない。

### 本体と共有拡張の実操作

本体run `20260918T192333Z-mvp-ui-bb92c0`は標準driverが成功した。作成、下書きの閉じる・再開・保存、検索、編集、原文コピー、ピンと独立したフィルター、削除・Undo・削除一覧からの復元、破棄、設定・About、左右配置と再起動後の保持、背景復帰を確認した。対象UUIDは`BBEE4AA1-BF71-40CD-BF50-C2B2CE275CBC`。編集後コピーと復元後の本文はUTF-8、復元は同じUUIDで照合した。

共有run `20260918T194628Z-shared-data-native-share-7d1742`は、縦向きの検証用UIKitアプリから同じschemeでビルドした製品の共有拡張を開き、タイトル入力・保存・共有元復帰・本体検索・コピーまで成功した。実行中の拡張プロセスのパスを、インストールした`Nibble.app/PlugIns/NibbleShare.appex`と照合した。対象UUIDは`9076D3CF-4921-496F-9A73-D243EA67346B`。空白・改行・結合文字・絵文字を含む元テキストとコピー結果のUTF-8が完全一致した。fixtureのソース・コンパイル条件・hashはrunに保存した。

原本画像として、本体の`resumed-draft.png`、`edited.png`、`pinned-filter.png`、共有の`share-editor.png`、`shared-in-library.png`を開いた。本文・対象行・フィルター・編集操作が表示されることを確認した。録画は本体225.13秒の10.5017 / 113.72 / 202.47秒、共有78.22秒の1.0217 / 45.3433 / 70.6883秒を抽出画像で確認した。本体では背景のSpringBoard・検索入力・削除一覧、共有では共有シート・復帰後の一覧・検索結果を観察した。全編再生・公開先への添付は未実施。

失敗runも保持する。本体`20260918T191336Z-mvp-ui-384148`はnibbleキーボードが選択された状態で本文ペースト用の編集メニューを開けず終了した。標準の日本語キーボードに切り替え、製品・driverを変更せず成功runを取得した。共有`20260918T192808Z-shared-data-share-21ff6e`は横向きSafariの共有シート操作が成立せず、デスクトップ側のSimulator操作もタイムアウトした。縦向きの専用fixtureへ切り替えた。共有`20260918T193829Z-shared-data-native-share-ce967e`と`20260918T194407Z-shared-data-native-share-3322df`は対話コマンドの引数誤りで終了した。これらは製品の保存失敗として扱わず、上記の成功runで一連操作を再実行した。

### キーボードの実操作

`20260918T194840Z-keyboard-ui-9dfa05`は同じRelease製品ビルドで成功した。専用SimulatorのDBをSQLite backupで退避し、0件と53件のダミーデータを使った。0件表示、更新ボタンによる53件の再読込、50件単位の次・前ページ、ピン留め0件、閉じる・再入場を確認した。2ページ目のUUID`00000000-0000-0000-0000-000000000003`をタップし、ホストの入力欄に本文が入ることをAX値で照合した。

フルアクセスOFFではコピーキーに鍵と案内が表示され、既存クリップボードのsentinel文字列を維持した。SettingsでONにしてホストへ戻り、同じ項目のコピー結果41 UTF-8 byteがDB原文と完全一致し、ホストへ重複挿入しないことを確認した。直接挿入の照合はAXが返す前後空白を除いた文字列であり、その結果だけで挿入先の完全なbyte一致を主張しない。終了時にフルアクセスOFF、標準日本語キーボード、元DBへ復元した。

原本の`keyboard-empty.png`、`keyboard-page-one.png`、`keyboard-page-two.png`、`keyboard-copy-denied.png`、`keyboard-pinned-empty.png`、`keyboard-copy-permitted.png`を開き、件数別表示、ページ番号、入力結果、権限別アイコンと通知を確認した。録画62.7783秒の2.6633 / 31.5517 / 57.6517秒の抽出フレームは、1ページ目・2ページ目・挿入済みのピン留め空表示を示す。許可ありコピーは録画終了後の操作ログ・原本画像・byte照合で確認した。全編再生、今回の変更での横向き・小画面・ダーク・VoiceOver音声・実機は未実施。画面レイアウトを変更していないため、既存の条件別レイアウト評価は[前回の対象ソース付き記録](keyboard-validation.md)と区別する。

## 一次資料と保証の範囲

2026-09-19に確認した資料：

- [SQLiteの分離](https://www.sqlite.org/isolation.html)：接続間の確定更新とWAL snapshot。プロセス間の排他はSwift actorだけでは保証しない。
- [SQLiteのCASE](https://www.sqlite.org/lang_expr.html#the_case_expression)：条件に対応する式だけを評価する。旧本文の取得を同じsequenceの場合へ限定する根拠とする。DBの物理ページI/Oがゼロになるという保証ではない。
- [Swift Concurrency](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/)：actor隔離とawaitによる中断。モデルのawait前後で有効性を検査する。

Instrumentsの既知の制約は[診断記録](instruments-diagnosis.md)にある。SimulatorのAnimation Hitches非対応とTime Profilerの計測サービス失敗を、製品の描画性能の証明に使わない。実機のfps・電力・配布容量は別途評価を要する。
