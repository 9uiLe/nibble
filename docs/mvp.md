# nibble MVPの操作と検証

nibbleは、よく使うテキストを保存して素早くコピーするiPhoneアプリ。最低対応OSはiOS 26.0、実行検証はiOS 26.5 Simulatorを使用する。MVPの実装範囲では実機検証を省略する。

## 使い方

| 操作 | 手順 |
| --- | --- |
| 作成 | 一覧の＋から本文を入力し、保存。タイトルは任意 |
| 利用 | 一覧の右端のコピーボタンを押し、入力先のアプリでペースト |
| 検索 | タイトルや本文を入力。日本語1文字、半角/全角、英字大小の比較に対応 |
| 編集 | 項目をタップして編集・保存。閉じると下書きが残る |
| 下書きの復旧 | 一覧の「下書きを再開」から開く。破棄は編集画面のその他メニュー |
| ピン留め | 項目を長押し、または横にスワイプしてピン留め。専用フィルタで表示 |
| 削除・復元 | 長押しまたはスワイプで削除。直後の「元に戻す」、またはその他→削除した項目から復元 |
| 完全削除 | 削除した項目を長押し、完全削除を選んで確認 |
| 共有から取り込み | テキストまたはURLの共有先でnibbleを選び、編集して保存 |
| 呼び出し | Shortcutsの「URLを開く」に`nibble://library`（一覧）または`nibble://new`（作成）を指定 |

コピーは本文をそのまま保持し、同じ端末のアプリへ貼り付けられる。元のアプリへの復帰とペーストは利用者が行う。共有拡張は入力元が公開するテキストまたはURLを1件扱い、Webページの内容をダウンロードしない。

## ショートカットから呼び出す

1. Appleの「ショートカット」で新規ショートカットを作る。
2. 「URLを開く」アクションを追加し、`nibble://library`または`nibble://new`を入力する。
3. 実行して目的の画面を確認し、必要ならホーム画面やコントロールセンターへ追加する。

編集画面を開いているときは、その内容を維持する。URLで本文を渡したり保存・削除を実行したりしない。

## 開発環境

[READMEのセットアップ](../README.md#セットアップ)でNix・Xcode 26.5・iOS 26.5 Simulatorを用意する。

| 設定 | 値 |
| --- | --- |
| project / shared scheme | `app/Nibble.xcodeproj` / `Nibble` |
| 共通driver設定 | `app/project.json` |
| 本体 / Share Extension | `dev.nibble.app` / `dev.nibble.app.share` |
| App Group | `group.dev.nibble.app` |
| Swift | language mode 6、strict concurrency complete、default isolation nonisolated |
| SDK・補助依存 | Apple SDK、既存Nix flake/lock。追加のパッケージ依存なし |

すべてリポジトリルートで実行する。`NIBBLE_SIMULATOR`には[専用SimulatorのUDID](ios-verification.md#simulatorの作成と選択)を指定する。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py run \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
```

Swift Testingは使い捨ての保存領域で原文保持、検索、復元、版競合、下書き順序、同時書込、無効入力、未知のschema、壊れたDB、URLの許可範囲を検査する。本体と共有拡張のソースは[ADR 0002](decisions/0002-mvp-app.md)に示した責務で分ける。

基本の操作・撮影は次のdriverで再現する。専用Simulatorを使用し、編集中の画面は閉じておく。driverはダミー項目を1件追加し、既存の項目は削除しない。

```sh
nix develop --command python3 scripts/check-mvp-ui.py --device "$NIBBLE_SIMULATOR"
```

共有とペーストの検証には、別ターミナルでローカルのフォームを配信する。

```sh
nix develop --command python3 -m http.server 8766 --bind 127.0.0.1 --directory validation
```

SimulatorのSafariで`http://127.0.0.1:8766/MVPHost.html`を開き、「テキストを共有」→nibble→保存を実行する。本体でその項目をコピーし、Safariに戻って「ペースト先」の標準編集メニューからペーストする。「本文のUTF-8を表示」で原文と照合できる。URLの共有はSafariのページメニューから行う。画面操作は`sim-use`を使い、Simulatorの共有ポップアップの読み取り座標が画像とずれる場合は、実際のスクリーンショットを根拠に操作位置を指定する。

ショートカットの初回実行では、nibbleを開く許可をシステムが求めることがある。許可後の実行と到達画面を記録する。

[MVPの検証結果](mvp-validation.md)に対象コミット、環境、実施結果、未検証範囲を記録する。

## 画面の受け入れ条件

- 空の一覧から本文を保存し、検索・編集・再起動後も同じ内容をコピーできる。
- 日本語IMEの変換・確定が本文へ反映され、改行・前後空白をコピー後も保持する。
- ピン留め・解除、検索0件、削除・復元、下書きの再開を操作できる。
- iPhone SE第3世代相当の小画面・最大Dynamic Type・キーボード併用でも本文に到達でき、保存・閉じる操作を行える。
- ライト・ダーク、縦・横で本文と主要操作を視認できる。
- Safariの共有シートから保存し、本体で読み出して同じ内容をコピーできる。
- Shortcutsの標準URLアクションから一覧・作成画面への到達を記録する。App Shortcutsの自動登録はMVPの対象外。

画面読取・入力・操作はNixのsim-use、記録はAppleの`simctl io screenshot / recordVideo`を使う。取得コマンドと確認方法は[共通手順](ios-verification.md#スクリーンショットと画面録画)に従う。ログと画像・動画を`artifacts/`へ保存し、対象コミット・OS・操作を付けてPRに添付する。

実機のロック時保護、VoiceOver等の実操作、Handoff、実機性能、署名配布・審査は未検証の範囲として記録する。
