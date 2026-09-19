# 保存・検索方式の比較根拠

ResearchProbeは製品から独立した比較用アプリである。SQLite採用、日本語の短い検索、狭い画面の設計を判断するため、次の条件の観測を保持する。現在の製品の合格や性能値を表すものではない。[実行手順](../../validation/RESEARCH.md)で同条件を定義して再測定する。

## 実験条件

| 項目 | 条件 |
| --- | --- |
| 実施日 | 2026-09-13 |
| 対象 | `validation/ResearchProbe.xcodeproj` / shared scheme `ResearchProbe` |
| ソース | [85955db0c22c7403d82efcd34f1436b2bf32b802](https://github.com/9uiLe/nibble/commit/85955db0c22c7403d82efcd34f1436b2bf32b802)の研究用実装。画面比較の構成差は「適用範囲」に定義 |
| Mac / Xcode | macOS 26.2 / Apple Silicon、Xcode 26.5 (17F42)、Apple Swift 6.3.2 |
| コンパイラ | Swift language mode 6、strict concurrency complete、default isolation nonisolated、Release `-O`・testability有効 |
| OS | iOS 26.5 (23F77)のみ。deployment targetは26.0 |
| 主端末 | iPhone 17 Pro Simulator、402×874 pt、UDID `114E57E6-E37D-4F50-907A-8B0B6B03C92E` |
| 小画面 | iPhone SE第3世代Simulator、375×667 pt、UDID `A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`、同じ26.5 runtime |
| データ | 日本語、結合濁点、半角カナ、空白・改行・タブ、絵文字、記号を含むダミーテキスト |
| 操作と撮影 | Apple CLIでビルド・実行管理・記録、Nixのsim-useで画面読取・操作 |
| 実機・署名・同期 | 測定対象外。実機・実extension・署名配布や同期の成立を保証しない |


## 判断に使う結果

E番号は再現条件を識別するための実験IDである。

| 実験 | 条件 | 観測 | 限界 |
| --- | --- | --- | --- |
| E01 | SwiftData・Core Data・SQLiteで同じ本文を作成、取得、更新、削除、再open | 3方式で一致。日本語・結合濁点・半角カナ・改行・タブ・絵文字・記号・前後空白を保持 | 本体内の独立接続。extensionのsandboxを試していない |
| E02 | 作成済みストアをread-onlyで読み、writeを拒否 | 3方式でread成功・write拒否、再open後の保存済み値を保持 | 親ディレクトリが書込可能な条件。Full AccessなしKeyboardの権限とは別 |
| E03 | 別プロセスのwriter競合、コミット前の強制終了 | 2番目のwriterは`database is locked`。未コミットwriterをSIGKILL後も`original`、integrity checkは`ok` | SQLiteの制御された1回の実験。SwiftData/Core Dataの終了・全障害パターンを網羅しない |
| E04 | readerのtransaction中に別プロセスで更新 | transaction中は`original`、終了後のreadは`committed` | 明示再読込が必要。通知配送やframeworkの画面更新時間は未測定 |
| E05 | checkpoint後のSQLiteを書込不可のディレクトリから開く | read-only open・取得成功 | POSIX権限の試験。live WALの全sidecar条件やApp Group権限を保証しない |
| E06 | 稼働中DBをOnline Backup APIで複製、DB本体だけのcopyとも比較 | Backup APIは本文一致・`integrity_check=ok`。WALを欠く本体だけのcopyはread失敗 | 直接SQLiteのみ。SwiftData/Core Data内部DBへこのbackup方法を適用していない |
| E10 | FTS5 unicode61/trigram、1・2・3文字の日本語 | 作成成功。trigram `MATCH`は「東」「東京」0件、「東京都」1件。`LIKE '%東京%'`は1件 | LIKEの成功は短文index効率を保証しない。unicode61は単語単位で任意部分一致ではない |
| E11 | 検索用NFC+case/width foldingと期待集合 | 結合濁点／合成済、半角／全角カナ、全角／半角英字大小は一致。かな／カナ、清音／濁音は区別 | 試験で選んだ比較仕様。製品の仕様は製品設計で定める |
| E14 | 保存失敗後の本文保持・下書き再open | 保存失敗を表示し、別editorが同じ下書きを取得 | save直前に容量不足エラーを注入。実際の容量枯渇や保存中のOS終了を代替しない |
| E24 | iPhone SE第3世代・375×667 pt、最大Dynamic Typeとキーボード併用 | **不合格**。本文viewportが36 ptまで縮み、文字の上下が切れる。タイトルも省略される。copyの本文は保持 | 縦stackに全操作を置くこの試作を製品へ採用しない。入力と操作の配置、ページ全体のスクロールを比較する必要がある |
| E25 | Shortcuts一覧への登録とアクション実行 | 一覧への表示は成功。実行は失敗し、OSログは`LNActionForAutoShortcutPhraseFetchError Code=1 / Couldn’t find AppShortcutsProvider` | 明示的な`updateAppShortcutParameters()`、アプリ/Shortcutsの再起動、ad hoc署名でも同じ画面エラー。metadataにはproviderとactionが存在する。原因は未特定で、26.5実機・署名構成での比較が必要 |

## 計測条件と観測値

同じ短いダミー本文で0・20・1,000・10,000件を試した。各ストアの新規作成後の保存・全件取得は各1回、全件正規化を含む検索は30回。SimulatorのRelease（`-O`、テスト可能設定）であり、cold launch、実機のCPU・メモリ・電源条件をそろえた性能比較ではない。保存には各frameworkの管理処理と履歴の差も含まれる。

| 件数 | SwiftData 保存/取得 ms | Core Data 保存/取得 ms | SQLite 保存/取得 ms | 全件検索 中央値/最大 ms（30回） |
| --- | --- | --- | --- | --- |
| 0 | 0.124 / 0.099 | 0.780 / 0.083 | 0.048 / 0.017 | 0.000 / 0.002 |
| 20 | 4.945 / 0.449 | 3.348 / 0.302 | 0.066 / 0.037 | 0.088 / 0.163 |
| 1000 | 72.733 / 15.840 | 12.552 / 3.764 | 1.228 / 0.912 | 4.432 / 4.563 |
| 10000 | 700.163 / 173.106 | 88.247 / 31.531 | 11.662 / 8.260 | 43.920 / 47.120 |

個々のraw値はテストアプリの`Documents/results/simulator-timing.json`。この試作はMainActor上で全件を処理するため、観測値を製品の性能予算として採用しない。取得範囲を限定する必要性の判断に使う。製品保存層の性能は[製品の比較](../../docs/product-architecture-validation.md)で評価する。


## 適用範囲

標準構成の対象コードは`85955db`。画面比較構成はeditor callbackの強参照と起動時のShortcuts登録更新なしという差を持ち、ソースhashは`artifacts/ios/20260913T052747Z-research-ui-109e07/manifest.json`で識別する。現在のcheckoutへ結果を使う場合は入力ファイルを照合する。raw値・失敗runはGit管理外で、新しいcheckoutには含まれない。

本体内の複数接続、POSIXのread-only、SDKコンパイルは、それぞれ実extensionの権限、別プロセス、機能登録の試験とは異なる。製品Keyboardの契約は[Keyboard設計](../../docs/decisions/0005-snippet-keyboard.md)、現在の未確認条件は[製品の検証範囲](../../docs/mvp-validation.md)を参照する。
