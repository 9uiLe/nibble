# nibble MVPの操作と検証

nibbleは、よく使うテキストを端末内に保存し、探してコピーする日本語UIのiPhoneアプリである。本体とShare Extensionで作成・編集・取り込みを行い、入力先のアプリへの復帰とペーストは利用者が行う。最低対応OSはiOS 26.0、実行検証はiOS 26.5 Simulatorに限定する。

設計の契約と採用理由は[製品設計](decisions/0002-mvp-app.md)、実施済みの確認と未検証項目は[検証結果](mvp-validation.md)を参照する。この文書は、操作手順とその期待結果を定義する。

## 日常の操作

| 操作 | 手順・結果 |
| --- | --- |
| 作成 | 一覧の＋から本文を入力して保存する。タイトルは任意。＋は新しい下書きを作る |
| 利用 | 一覧の右端のコピーボタンを押し、入力先のアプリでペーストする。タイトルを含めず本文をそのままコピーする |
| 検索 | タイトルや本文の一部を入力する。日本語1文字から検索でき、英字大小・半角/全角を同一視する。ひらがな/カタカナ、清音/濁音は区別する |
| 編集 | 項目をタップして編集・保存する。その項目の下書きがあれば再開する |
| 閉じる | 入力を下書きに残して編集画面を閉じる。空の新規入力と、変更していない保存済み項目の編集は下書きを残さない |
| 下書きの再開・破棄 | 検索語を空にし、一覧の「下書きを再開」から開く。編集画面のその他→下書きを破棄で確認して消去する |
| ピン留め | 項目の長押しメニューまたはスワイプでピン留め・解除する。ピン留めした項目は一覧の先頭に並び、専用フィルタでも表示できる |
| 削除・復元 | 長押しまたはスワイプで削除する。直後の「元に戻す」、またはその他→削除した項目から復元する。自動消去はしない |
| 完全削除 | 削除した項目の長押しメニューまたはスワイプから完全削除を選び、確認する。関連下書きも消去し、元には戻せない |
| 共有から取り込み | 他アプリのテキストまたはURLの共有先でnibbleを選び、編集して保存する。閉じた下書きは本体で再開できる |
| 本文の共有 | 編集画面のその他→本文を共有から、iOSの共有シートを開く |

本文の前後空白・改行・タブ・Unicodeは保存とコピーで保持する。空白・改行だけの本文は保存できない。保存時の上限はタイトル512 UTF-8 bytes、本文1,000,000 bytes。入力上限や保存エラーは編集画面に表示し、内容を保持する。同じ項目を別の操作で変更した場合は、競合を表示し、編集中の本文を新しい項目として保存できる。

コピーは同じ端末内で利用する。共有拡張は共有元のアプリが提供するテキストまたはURLを1件扱い、Webページの本文をダウンロードしない。アプリの同期・独自バックアップ機能はなく、アプリ削除後の保存データの復旧は提供しない。

## ショートカットから呼び出す

1. Appleの「ショートカット」で新規ショートカットを作る。
2. 「URLを開く」アクションを追加し、一覧には`nibble://library`、作成には`nibble://new`を入力する。
3. 実行し、初回にOSの確認が表示されたら内容を確認して許可する。目的の画面が開くことを確かめる。

一覧URLは検索語とフィルタを初期状態にし、作成URLは新しい下書きを開く。編集画面を開いている場合は、その編集を維持する。URLで本文を渡したり保存・削除を実行したりしない。App Shortcutsの自動登録は提供しない。作成したショートカットのホーム画面・コントロールセンターへの配置はOSの機能であり、MVPの配置操作は未検証である。

## 開発環境とビルド

[READMEのセットアップ](../README.md#セットアップ)でNix・Xcode 26.5・iOS 26.5 Simulatorを用意する。

| 設定 | 値 |
| --- | --- |
| project / shared scheme | `app/Nibble.xcodeproj` / `Nibble` |
| 共通driver設定 | `app/project.json` |
| 本体 / Share Extension | `dev.nibble.app` / `dev.nibble.app.share` |
| App Group | `group.dev.nibble.app` |
| Swift | language mode 6、strict concurrency complete、default isolation nonisolated |
| アプリ依存 | Apple SDK、swift-tasking 0.3.0、swift-scoped-animation 0.2.1（[実装規約](library-policy.md)） |
| 補助ツール | `flake.nix`で宣言し、`flake.lock`で固定 |
| Simulator署名 | `simulator_signing: "ad-hoc"`。App Groupのentitlementを渡すローカル署名。Developer Team・証明書は不要 |

すべてリポジトリルートで実行する。`NIBBLE_SIMULATOR`には[専用SimulatorのUDID](ios-verification.md#simulatorの作成と選択)を指定する。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py run \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
```

Swift Testingは使い捨てのDBで、原文保持、検索、復元、競合、下書き順序、同時書込、入力エラー、未知schema、破損DB、URLの許可範囲、操作の重複・キャンセル、入力直後の保存・閉じる操作を検査する。操作テストはモデルのasync APIを直接awaitして完了・結果を検査し、重複・寿命の試験では専用所有者を使用する。入力setterがDBを書き換えないこと、明示的なsnapshot保存、通知の独立した期限、保存・破棄後の遅延書込も検査する。使い捨てのDBを使用し、利用者の保存データを使わない。

## 基本操作の自動検証

専用Simulatorで編集中の画面を閉じ、次のdriverを実行する。

```sh
nix develop --command python3 scripts/check-mvp-ui.py --device "$NIBBLE_SIMULATOR"
```

driverはダミー項目を作成し、コピー・日本語検索・編集画面・ピン留め・削除・復元・下書き破棄を操作する。実行ごとに一意な日本語タイトルを使い、検索で対象行を特定してコピーのUTF-8と復元後のUUIDを照合する。既存の項目は削除しない。行を開く前にキーボードを閉じ、一覧の配置が確定してから操作する。

## 共有とペーストの検証

別ターミナルでローカルフォームを配信する。

```sh
nix develop --command python3 -m http.server 8766 --bind 127.0.0.1 --directory validation
```

1. SimulatorのSafariで`http://127.0.0.1:8766/MVPHost.html`を開く。
2. 「テキストを共有」→nibbleを選び、本文を保存する。
3. 本体でその項目をコピーし、Safariに戻る。
4. 「ペースト先」の標準編集メニューからペーストする。「本文のUTF-8を表示」で原文の全バイト列と照合する。
5. SafariのページメニューからURLも共有し、保存・コピーした文字列がページURLと一致することを確認する。
6. 配信したターミナルでCtrl+Cを押してサーバーを終了する。

画面読取と操作はNixのsim-useを使う。共有ポップアップの要素座標が画像とずれる場合は、実際のスクリーンショットを根拠に操作位置を指定する。SafariへのペーストではOSの標準メニューを使い、pasteboardを上書きする`sim-use paste`を使わない。

## 画面・入力の確認条件

以下を製品UIの確認項目とする。条件の定義は実施済みを意味せず、成否は[検証結果](mvp-validation.md)に記録する。

| 観点 | 期待結果 |
| --- | --- |
| 基本操作 | 空の一覧から保存・検索・編集ができ、再起動後も同じ本文をコピーできる |
| 日本語入力 | かな入力・変換候補の確定が本文へ反映される。下書きの再開とコピー後も本文を保持する |
| 状態と回復 | 検索0件、ピン留め、削除・復元、下書きの再開と破棄を操作できる。保存エラーを成功と表示しない |
| 画面と文字 | iPhone SE第3世代相当の小画面・最大Dynamic Type・キーボード併用でも本文と保存・閉じる操作に到達できる |
| 外観・向き・支援技術 | ライト・ダーク、縦・横で本文と主要操作を視認でき、VoiceOver・Reduce Motionでも操作を完了できる |
| 共有 | Safariからテキスト・URLを取り込み、本体でコピーして入力先へペーストできる |
| 呼び出し | 標準URLアクションから一覧・作成画面を開き、編集中の内容を置き換えない |

### タスクの寿命とアニメーション

一覧・編集・共有の所有者と重複方針は[製品設計](decisions/0002-mvp-app.md#操作の寿命と整合性)、禁止APIと診断の使い方は[実装規約](library-policy.md)に従う。以下の手順ではTaskingとScopedAnimationを使う製品の境界を確認する。

1. 保存済み項目のある状態で本体プロセスを終了・再起動し、同じUUIDの項目が一覧に出ることを確認する。シートの開閉とbackgroundからの復帰でも一覧を確認する。
2. 同じ操作の連打と別項目への連続操作を行い、重複する編集画面や下書きができず、別項目の操作は受理されることを確認する。入力直後に保存・閉じる操作を行い、最新本文と下書きを照合する。
3. Settingsの「視差効果を減らす」を無効・有効にしてselected状態を確認する。それぞれでコピー通知の表示と消去、編集の開閉を撮影する。最後のコピーから2秒で通知が消える設計に対し、自動操作では2.3秒後の表示状態を照合する。通知の遷移指定は通常0.16秒、有効時0秒とする。
4. Debug実行では、内部の`detectAnimationLeaks`・入力barrierと、Taskingの未処理エラーの診断を確認する。OSのシートtransactionは画面外側のbarrierで遮断する。診断が届く位置と実行した導線を記録する。
5. 検証終了後に表示設定を実行前の状態へ戻す。操作・画像・録画・診断の実施範囲を[検証結果](library-policy-validation.md)と同じ形式で記録する。

## 証跡と検証範囲

画面読取・入力・操作はNixのsim-use、撮影はAppleの`simctl io screenshot / recordVideo`を使う。[共通手順](ios-verification.md#スクリーンショットと画面録画)に従い、ログ・画像・動画をGit管理対象外の`artifacts/`へ保存する。`REVIEW.md`へ実際の確認範囲を記入し、対象コミット・端末・OS・手順を付けてPRへ添付する。

MVPの実行評価はiOS 26.5 Simulatorを対象とし、実機検証は含めない。実機のロック時保護・性能・触覚・Handoff・署名配布は個別の評価が必要である。VoiceOver、横向き、長時間利用、1 MB本文の入力追従の未検証条件と、Reduce Motionの確認済み範囲は[検証結果の制約](mvp-validation.md#検証範囲の制約)を参照する。
