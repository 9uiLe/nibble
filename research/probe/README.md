# ResearchProbeの設計と実行手順

ResearchProbeは、nibbleの保存・検索・入力・コピー・復旧方式を評価する研究用アプリである。同じダミーデータを複数の保存方式で扱い、APIの利用可否、データの正しさ、画面操作をそれぞれ検証する。製品の採用構成は[製品仕様・要件](../../docs/product-specification.md)、観測結果は[iOS 26.5の検証結果](../experiments/ios-26-5-validation.md)に定義する。

比較目的を決めて`python3 scripts/verify.py run --scope research --device "$NIBBLE_SIMULATOR"`からテストとUIを実行する。通常回帰はこの実験を含めない。採用していない保存方式やAPIの成功を製品の保証に使わない。SDK・別processの実験は、以下の個別手順で選ぶ。

## 対象

設定は[research-project.json](project.json)、schemeはResearchProbe、bundle IDは`dev.nibble.ResearchProbe`。基盤fixtureと別の保存領域で、使い捨てのダミーデータだけを使う。保存方式は[Stores.swift](ResearchProbe/Stores.swift)、UIは[App.swift](ResearchProbe/App.swift)、期待値は[HostedTests.swift](ResearchProbeTests/HostedTests.swift)が定義する。

## データと操作の契約

### 保存と検索

比較用の値`ProbeValue`はID・タイトル・本文・revisionを持つ。保存・コピー・JSON出力では、前後空白、改行、タブ、結合文字、絵文字を含む原文を保持する。`ProbeStore`の共通操作は全件置換とID順の全件取得とする。

| 保存方式 | 比較用の構成 |
| --- | --- |
| SwiftData | CloudKitを無効化し、autosaveを使わず明示saveする。更新・削除・挿入を1回のsaveにまとめ、失敗時にrollbackする |
| Core Data | 永続履歴を有効化し、context内で全件を入れ替えて明示saveする。失敗時にrollbackする |
| SQLite | WALを使用し、全件置換を`BEGIN IMMEDIATE`から`COMMIT`までのtransactionにまとめる。失敗時にrollbackする |

保存処理は比較条件をそろえるためMainActorに隔離する。画面の保存・再読込にはSwiftDataを使い、3方式の比較はSwift Testingで行う。MainActorでの全件処理、contextの生成頻度、全件取得を製品の性能設計として採用するものではない。

検索用文字列はNFCと`ja_JP`のcase/width foldingで生成し、タイトルと本文の部分一致を調べる。かなとカナ、清音と濁音は区別する。本文自体は正規化しない。非同期検索の世代管理は独立した試験で評価し、画面の検索は同期的な全件検索である。

### 編集と復旧

画面は明示保存を使う。編集中のタイトルと本文をアプリ内の下書きJSONへatomicに保存し、editorを開くと対応する下書きを読み込む。保存成功時に下書きを削除し、保存失敗時には本文とエラー表示を保持する。容量不足はテストから保存直前にエラーを注入して比較する。

削除の復元対象は、現在のアプリプロセスで直前に削除した1件とする。復元情報は永続化しない。版付きJSONはversion 1、重複IDなし、4,000,000 bytes以下を読込条件とし、不正入力を保存前に拒否する。これらは研究用の比較条件であり、製品の保持期間・import時の統合方針・容量上限は別に定義する。

### 呼び出しと保護

`nibble-probe://list`、`nibble-probe://create`、`nibble-probe://item/<UUID>`を許可する。query・fragment・不正なID・削除操作を含むURLは拒否する。コピーには`localOnly: true`を指定する。

App Shortcutsには前景実行の`ProbeOpenIntent`を登録する。アプリ起動時に`updateAppShortcutParameters()`を呼ぶ。Widget・Control・Keyboard・Shareの独立したextension targetは含まないため、型検査の成功とextensionの登録・動作は別の検証になる。

scene非アクティブ時の画面coverと、下書き・snapshotの`.completeFileProtection`指定を持つ。アプリ切替画面での隠蔽と、実機のロック時の保護は実行結果で判定する。Privacy Manifestは収集・tracking・第三者SDKのない研究用アプリの宣言とし、テストbundleを配布しない。

## 実行環境

[READMEのセットアップ](../../README.md#セットアップ)に従ってNix、Xcode 26.5、iOS 26.5 Simulatorを用意する。実行OSは**26.5のみ**、deployment targetは**26.0**、Swift language modeは6、strict concurrencyはcomplete、default isolationはnonisolatedとする。

研究用driverはarm64のSimulatorを前提とするため、Apple Silicon Macで実行する。Releaseは`-O`を使い、Swift Testingから内部実装を呼べるよう`ENABLE_TESTABILITY=YES`とする。Simulator検証とunsigned archiveにはDeveloper Teamを必要としない。実機、App Group、CloudKit、配布には対象に合う署名・権限設定を用意する。

すべてのコマンドはリポジトリルートで実行する。[専用Simulatorの作成・選択](../../docs/ios-verification.md#simulatorの作成と選択)で得たUDIDを指定する。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
nix develop --command python3 scripts/ios.py boot --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py doctor \
  --project-config research/probe/project.json
```

同じ端末で検証を同時に実行しない。テストとUI driverは共通driverのUDID単位のロックを使う。SDK検査・SQLite別プロセス検査・手動操作にはこのロックがない。

## 自動検証

```sh
# 保存・検索・移行・復旧のSwift Testing
nix develop --command python3 scripts/ios.py test \
  --project-config research/probe/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"

# Simulator / device SDK × app / extensionの4条件の型検査
nix develop --command python3 research/probe/check-sdk.py

# 起動済み26.5 Simulator内のSQLite別プロセス検査
nix develop --command python3 research/probe/check-processes.py \
  --device "$NIBBLE_SIMULATOR"

# 作成→検索→再読込→コピー→削除→復元、録画と静止画の取得
nix develop --command python3 research/probe/check-ui.py \
  --device "$NIBBLE_SIMULATOR"
```

UI driverは準備時に`Documents/draft-new.json`を削除し、保存済み項目を保持したまま1件のダミー項目を作成する。削除したIDが一覧から消え、復元後に同じIDが現れることと、コピーした全UTF-8 bytesの一致を検査する。AX値が本文の外側空白を省く条件では、画面値とコピー結果を別々に照合する。`sim-use paste`はIMEを経由しない。

SQLite別プロセス検査は自分で起動したworkerのPIDだけを停止する。writer競合と終了前後の値を検査し、読取専用ディレクトリの成否は`results.json`へ観測値として記録する。POSIX権限の結果をextensionのsandbox権限へ一般化しない。

## 画面操作の比較

### Safariへのペーストと本体復帰

ローカルのダミーフォームを配信する。

```sh
nix develop --command python3 -m http.server 8765 \
  --bind 127.0.0.1 --directory research/probe
```

別のターミナルでSafariを開く。

```sh
xcrun simctl openurl "$NIBBLE_SIMULATOR" http://127.0.0.1:8765/HostForm.html
```

本体で本文をコピーし、Safariの「ペースト先」をsim-useで長押ししてOSの「ペースト」を選ぶ。「本文のUTF-8を表示」の配列を原文のbytesと照合し、「研究用アプリへ戻る」リンクとOSの確認ダイアログを経て一覧へ戻る。Safari側で`sim-use paste`を使うとpasteboardを書き換えるため、この比較では使わない。サーバーは確認後にCtrl+Cで終了する。

### 日本語入力、表示条件、Shortcuts

システムの日本語かなキーボードを選び、sim-useで「か」「な」を入力して候補「カナ」を選ぶ。変換中の下線・候補、確定後の本文、コピー結果を記録する。本文編集、検索変換中の更新、programmaticな`setMarkedText`は独立した条件として扱う。

外観と文字サイズは次のコマンドで切り替える。開始時の設定を記録し、検証後に元へ戻す。

```sh
xcrun simctl ui "$NIBBLE_SIMULATOR" appearance dark
xcrun simctl ui "$NIBBLE_SIMULATOR" content_size accessibility-extra-extra-extra-large
# light / largeを基準とする専用端末の復帰例
xcrun simctl ui "$NIBBLE_SIMULATOR" appearance light
xcrun simctl ui "$NIBBLE_SIMULATOR" content_size large
```

iPhone SE第3世代の26.5 Simulatorでは、最大文字サイズとキーボードの併用時に本文の表示領域・文字の切れ・ボタンへの到達を確認する。Shortcutsでは「nibble Research」欄の「研究用一覧」を実行し、一覧への登録と前景アクションの実行を別々に判定する。

操作前に[共通の録画コマンド](../../docs/ios-verification.md#スクリーンショットと画面録画)を開始し、操作終了後に録画を確定して静止画を取得する。ファイルの復号確認と、表示・遷移・応答のレビューをそれぞれ記録する。

## archiveの点検

```sh
xcodebuild -project research/probe/ResearchProbe.xcodeproj \
  -scheme ResearchProbe -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath artifacts/research/ArchiveDerivedData \
  -archivePath artifacts/research/ResearchProbe.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive

plutil -lint artifacts/research/ResearchProbe.xcarchive/Products/Applications/ResearchProbe.app/PrivacyInfo.xcprivacy
```

unsigned archiveで確認する対象はビルドとmanifestの配置・構文である。署名検証、export、TestFlight更新、App Store Connectへの提出は配布構成を用意して別に実施する。

## 証跡と判定

| 保存先 | 内容 |
| --- | --- |
| `artifacts/ios/<実行ID>/` | 共通driverのmanifest・ログ・xcresult・UI JSON・画像・動画・レビュー記録 |
| `artifacts/research/sdk/<UUID>/` | 4構成の型検査ログと結果。各実行を独立して保持する |
| `artifacts/research/processes/<UUID>/` | SQLite workerと操作ごとの終了コード・結果 |
| テストアプリの`Documents/results/` | 文字列、移行、履歴、snapshot、SQLite環境、計測値のJSON。再実行で同名ファイルが更新される |

テストアプリの保存領域は次のコマンドで取得する。詳細JSONは実行直後に対応する証跡ディレクトリへコピーして保管する。

```sh
xcrun simctl get_app_container "$NIBBLE_SIMULATOR" dev.nibble.ResearchProbe data
```

生成物は`artifacts/`に置き、Gitへ追加しない。SDK型検査は実行ごとの`artifacts/research/sdk/<UUID>/`へログと`results.json`を保存し、stdoutに結果のパスと成否を返す。失敗した実験の記録を再実行で上書きしない。共通driverのrunは[証跡とPRの検査](../../docs/review-evidence.md)に従い、開始・終了・対象コミットの入力と媒体を照合する。画像・動画の観測、確認範囲、添付先と閲覧条件は`review.json`へ記載し、検査後に`REVIEW.md`を生成する。

検証結果は期待条件ごとに成功・失敗・未実施を判定し、対象ソース・端末・OS・操作とともに[実行結果](../experiments/ios-26-5-validation.md)へ対応付ける。共通driverを使わない測定やSDK検査も、固有の結果ファイルとログを残す。公開APIや原著の根拠は[研究資料](../README.md)を参照する。
