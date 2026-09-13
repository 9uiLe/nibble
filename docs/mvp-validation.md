# MVPの検証結果

検証日：2026-09-13。製品の受け入れ範囲はiOS 26.5 Simulatorとし、実機検証は省略する。最低対応OSは26.0。操作手順は[MVPの操作と検証](mvp.md)、採用構成は[ADR 0002](decisions/0002-mvp-app.md)を参照する。

## 対象と環境

- 製品実装：`a498ba4462aa8b7f0835791804710616a3bf4830`。
- 操作driverの遷移待ち：`667566c`。キーボードを閉じ、一覧の配置が確定してから項目を開く。
- 検索クリアボタンの表示：`873eda6`。アイコンのみを表示し、検索入力領域を確保する。
- Xcode 26.5、Apple Swift 6.3.2、Release構成。Swift language mode 6、strict concurrency complete、deployment target 26.0。
- iPhone 17 Pro Simulator：`114E57E6-E37D-4F50-907A-8B0B6B03C92E`、402×874 pt。
- iPhone SE（第3世代）Simulator：`A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`、375×667 pt。
- 両端末ともiOS 26.5（23F77）。本体・共有拡張はad hoc署名、App Groupは`group.dev.nibble.app`。
- 操作はNixで固定したsim-use 0.14.0、ビルド・テスト・ライフサイクル・撮影はApple CLI。ダミーデータのみを使用する。

各runの`artifacts/ios/<run>/manifest.json`にコミット、作業ツリーの状態、ファイルごとのSHA-256、端末、コマンド、終了コードを保存する。画像・動画はこの変更のPRに添付し、生成物をGitへ含めない。

## ビルドと自動テスト

| 検証 | 結果 | 対象・記録 |
| --- | --- | --- |
| ReleaseのSimulatorビルド | 本体・共有拡張とも成功、App Groupを開いて利用可能 | `873eda6`、`artifacts/mvp/build-final-visual.log` |
| iOS SDKのarchive | 署名を省いたgeneric iOS archive成功。本体・共有拡張・Privacy Manifestを含む | `a498ba4`の製品ソース、`artifacts/mvp/archive-final.log`。後続の製品差分は検索クリアのlabel styleのみ |
| Swift Testing | **13件成功、失敗・skipなし** | `a498ba4`、SE、`20260913T091118Z-test-9c568f` |
| Nix共通検査 | `workflow-policy`、`nix-format`、`ios-tooling`成功。Pythonテスト13件 | `nix flake check --no-update-lock-file --print-build-logs`、`artifacts/mvp/nix-final.log` |

Swift Testingは、再オープン後の原文、1文字の日本語検索、検索記号のliteral扱い、復元と完全削除、pinとページ取得、2接続の競合、30件の並行書込、下書きの順序と遅延書込、入力エラー、未知schema、破損DB、URLの許可範囲、変更せず閉じた編集、検索時間を検査する。保存と検索は製品の`SnippetStore`を直接使用し、使い捨てのDBを作る。

## 操作と画面

| 導線・条件 | 確認結果 | run（`artifacts/ios/`以下） |
| --- | --- | --- |
| 作成→コピー→日本語検索→編集画面→pin→削除→取り消し→下書き破棄 | 成功。コピーしたUTF-8、削除後の非表示、復元後の同一UUIDを照合 | `20260913T091147Z-mvp-ui-75f7e5`（`667566c`） |
| Safariのテキスト共有→nibble共有拡張→保存→本体でコピー | 成功。前後空白、改行、結合文字、絵文字を含むUTF-8が一致 | `20260913T090734Z-mvp-share-d9079f` |
| 本体のコピー→Safariへ戻る→標準メニューでペースト | 成功。フォームのTextEncoderが出した全バイト列が原文と一致 | `20260913T090853Z-mvp-host-paste-1c960c` |
| SafariのページURL共有→保存→コピー | 成功。`http://127.0.0.1:8766/MVPHost.html`と一致 | `20260913T091933Z-mvp-url-share-677501`（`873eda6`） |
| ショートカットの「URLを開く」→`nibble://new` | 初回のOS許可後、製品の作成画面へ到達 | `20260913T090324Z-mvp-shortcut-url-339150` |
| Safariを前面にした状態からOSへ`nibble://library`をdispatch | OSの「開く」確認後に一覧へ到達 | `20260913T092445Z-mvp-library-url-44bc09`（`873eda6`） |
| 日本語かなキー→「カナ」候補を確定→閉じる→プロセス再起動→下書き再開→タイトル編集・保存・コピー | 成功。下書きUUIDと本文を保持し、コピーが「カナ」と一致 | `20260913T091602Z-mvp-ime-draft-7231e1`（`667566c`） |
| SE・最大Dynamic Type・キーボード併用 | 本文を入力して保存・コピー可能。本文領域と保存操作を画像で確認 | `20260913T085832Z-mvp-compact-743c0b` |
| ダミーの返信・プロフィール・日程文、pin、編集画面、コピー | ライト・ダークの製品画面を撮影。コピーの本文一致を確認 | `20260913T092215Z-mvp-design-07d2c4`（`873eda6`） |
| ダークの一覧・編集、検索結果0件 | 表示を確認。最終のアイコンのみの検索クリア操作も確認 | `20260913T092113Z-mvp-dark-fba8a3`（`873eda6`） |

コミット前のrunはmanifestのファイルhashで対応する実装を特定する。テキスト共有とペーストの確認後、同じ共有拡張の最終ソースでURL共有も検査している。最大文字サイズ・Shortcuts・IMEの確認以降、それぞれの入力領域・URL受信処理・下書き処理に動作変更はない。

画像と動画から抽出したフレームをエージェントが確認した。動画全編のリアルタイム再生、人間の利用者試験、VoiceOverの読み上げ操作を実施済みとは扱わない。録画にはUI状態を確認するための待ち時間も含むため、動画の長さをアプリの応答時間として使わない。

## 検索の測定

SE Simulator、Release、製品のSQLite actor、最初の100件の取得。0・20・1,000・10,000件のダミーデータを使い、各条件で30回測定した。raw値は`artifacts/mvp/search-timing-final.json`に保存する。

| 保存件数 | 「東」一致：中央値 / 最大（ms） | 該当なし：中央値 / 最大（ms） |
| --- | --- | --- |
| 0 | 0.0478 / 5.3921 | 0.0442 / 0.4370 |
| 20 | 0.0382 / 0.0688 | 0.0249 / 0.0379 |
| 1,000 | 0.1169 / 0.1988 | 0.3166 / 0.4478 |
| 10,000 | 0.1211 / 0.3527 | 4.5901 / 6.3731 |

検索要求から保存層の返却までの測定であり、IME、Viewの更新、画面表示を含む遅延ではない。新規製品のため変更前の製品値はない。SimulatorとホストMacの負荷に依存する基準値として保存し、実機の性能予算や性能保証に転用しない。

`xctrace record --template 'Animation Hitches' --device <UDID> --attach <PID> --time-limit 20s`は実行したが、`Hitches is not supported on this platform`で計測できなかった。記録は`artifacts/mvp/animation-pid.log`。hitchを0件と報告しない。

## 検証範囲の制約

- 実機のロック中のData Protection、起動・描画・メモリ・電力・触覚、署名配布、App Store審査は対象外。署名を省いたarchiveは配布可能な成果物ではない。
- VoiceOverの実操作、横向きでの操作、Reduce Motion、長時間利用、最大1 MB本文の入力追従は未検証。横向きの切替は固定したsim-useの公開コマンドに用意されていない。
- Shortcutsの自動登録はMVPに含めない。標準「URLを開く」での作成を操作確認し、一覧URLはOS経由のdispatchを確認する。ホーム画面・コントロールセンターへの配置は未検証。
- 共有はSafariのテキスト・URLで確認した。各サードパーティアプリが公開する共有形式を網羅したものではない。
- スニペットを他アプリへ自動挿入しない。元のアプリへの復帰とペーストは利用者が行う。同期・バックアップの独自機能はなく、アプリ削除後の復旧は提供しない。
