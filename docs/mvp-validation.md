# MVPの検証結果

この文書はiPhoneアプリ`Nibble`と共有拡張`NibbleShare`で実施した確認と、その適用範囲をまとめる。採用する機能・構成は[製品設計](decisions/0002-mvp-app.md)、操作と期待結果は[MVP手順](mvp.md)で定義する。実行評価はiOS 26.5 Simulatorに限定し、実機検証はMVPの受け入れ範囲に含めない。最低対応OSは26.0。

## 対象と環境

| 条件 | 値 |
| --- | --- |
| ツールチェーン | Xcode 26.5、Apple Swift 6.3.2、Swift language mode 6、strict concurrency complete |
| iPhone 17 Pro Simulator | UDID `114E57E6-E37D-4F50-907A-8B0B6B03C92E`、402×874 pt |
| iPhone SE第3世代Simulator | UDID `A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`、375×667 pt |
| OS・署名 | iOS 26.5（23F77）、本体・共有拡張はad hoc署名、App Group `group.dev.nibble.app` |
| 操作と記録 | Nixで固定したsim-use 0.14.0。ビルド・テスト・実行管理・撮影はApple CLI。ダミーデータのみ |

検証は2026-09-13と2026-09-14に実施した。各結果は記載したソースに対応する。runは1回の検証実行を識別する名前であり、`artifacts/ios/<run>/manifest.json`にコミット、作業ツリーの状態、対象ファイルのSHA-256、端末、コマンド、終了コードを保存する。未コミット状態を含むrunはファイルのSHA-256で対象を特定する。

| ソース | 対応する評価 |
| --- | --- |
| `9686f3afea431bdb570adce9b538340bfd9caca6` | Tasking・ScopedAnimationを使う製品構成。19テスト、Debug実行、archive、基本操作、テキスト共有、通知、再起動 |
| `8473b3632f06fe2781909a30406b3a56c3af2e99` | SQLite actorの検索測定。保存層と検索SQLは`9686f3a`と同じ |
| `a498ba4462aa8b7f0835791804710616a3bf4830` | SQLite actorの検索比較用測定。2026-09-13の保存層・URLテスト13件とgeneric iOS archiveの対象 |
| `667566c2372f3f809b4a6957776a5bd28476174f` | 2026-09-13の基本操作・IME・下書きのrunに対応するソース |
| `873eda6136cb64f075e989f694aab4b7ce5fdd70` | 2026-09-13の一覧・編集・検索表示、URL共有、一覧URLの対象 |

採用構成のテスト・操作・診断の詳細と画像4点・動画5点は[Tasking・ScopedAnimationの検証記録](library-policy-validation.md)と[PR #7](https://github.com/9uiLe/nibble/pull/7)で確認できる。2026-09-13の表示・入力・OS連携の画像6点・動画6本は[PR #6](https://github.com/9uiLe/nibble/pull/6)に添付している。ローカルの生ログ・画像・動画はGit管理対象外であり、新しいcheckoutには含まれない。

## ビルドと自動テスト

| 検証 | 結果 | 対象・記録 |
| --- | --- | --- |
| 製品Releaseテスト | **19件成功、失敗・skipなし** | `9686f3a`、SE、`20260914T074447Z-test-716832` |
| 製品Debug実行 | 本体・共有拡張をビルドし、17 Proで実行成功 | `9686f3a`、`20260914T074415Z-run-51aa18` |
| iOS SDK archive | generic iOS archive成功。両bundleのMIT通知が原本と一致 | `9686f3a`、`artifacts/library-policy/archive-owned.log`。署名配布は検査しない |
| 研究用Releaseテスト | 14テスト、パラメータ展開後16実行が成功 | `20260914T070723Z-test-d695ae`。ResearchProbeの結果であり製品のテスト件数には含めない |
| Nix共通検査 | 4 check成功、Python 25テスト、17 Swiftファイルの規約検査成功 | [Ubuntu実行記録](https://github.com/9uiLe/nibble/actions/runs/34820368446)、`c898c40`。ローカルも同じlockと共通コマンドで成功 |

製品テストは、原文保持、1文字の日本語検索、記号のliteral扱い、pinと取得上限、復元と完全削除、2接続の競合、30件の並行書込、下書きの順序と遅延書込、入力エラー、未知schema、破損DB、URLの許可範囲、変更せず閉じた編集、検索時間を検査する。さらに、操作の寿命・重複抑止・キャンセル、30回連続入力直後の保存と閉じるを検査する。製品の保存層とmodelを直接使用し、使い捨てのDBを作る。

## 採用構成の操作と画面

以下は`9686f3a`を対象に2026-09-14に実施した。端末は17 Pro、標準文字サイズ、ライト外観。操作のassertionsと表示確認の詳細は[専用の検証記録](library-policy-validation.md#操作と表示)に記載する。

| 導線・条件 | 結果 | run（`artifacts/ios/`以下） |
| --- | --- | --- |
| 作成・コピー・日本語検索・編集を閉じる・ピン・削除・復元・下書き破棄、Release | コピーのUTF-8と復元後のUUIDが一致 | `20260914T074827Z-mvp-ui-9d04f2` |
| プロセス再起動2回、Release | 保存済みUUIDの一覧表示を確認・録画 | `20260914T074958Z-owned-cold-start-bc44e1` |
| Safariのテキスト共有→保存→共有元へ復帰→本体コピー、Debug | 前後空白・改行・結合文字・絵文字を含むUTF-8が一致 | `20260914T074729Z-tasking-share-bdbc0f` |
| Reduce Motion無効、Debug | 5回の再起動で保存済みUUIDを表示。通知の表示・自動消去、編集開閉が成功 | `20260914T074623Z-scoped-notice-disabled-aa3ca1` |
| Reduce Motion有効、Debug | 5回の再起動で保存済みUUIDを表示。通知の表示・自動消去、編集開閉が成功 | `20260914T074447Z-scoped-notice-enabled-f1664b` |

## 表示・入力・OS連携の観測

以下は2026-09-13に実施した条件の記録である。記載したソースでの観測を示し、Tasking・ScopedAnimationを含む全ソースで同じ条件を試したという意味にはしない。対象ソースを明記していないrunはmanifestのコミットとファイルSHA-256を参照する。

| 導線・条件 | 確認結果 | run（`artifacts/ios/`以下） |
| --- | --- | --- |
| 本体のコピー→Safariへ戻る→標準メニューでペースト | フォームのTextEncoderが出した全バイト列が原文と一致 | `20260913T090853Z-mvp-host-paste-1c960c` |
| SafariのページURL共有→保存→コピー | `http://127.0.0.1:8766/MVPHost.html`と一致 | `20260913T091933Z-mvp-url-share-677501`（`873eda6`） |
| ショートカットの「URLを開く」→`nibble://new` | 初回のOS許可後、作成画面へ到達 | `20260913T090324Z-mvp-shortcut-url-339150` |
| Safari前面からOSへ`nibble://library`をdispatch | OSの「開く」確認後に一覧へ到達 | `20260913T092445Z-mvp-library-url-44bc09`（`873eda6`） |
| 日本語かな入力→「カナ」を確定→閉じる→再起動→下書き再開→タイトル編集・保存・コピー | 下書きUUIDと本文を保持し、コピーが「カナ」と一致 | `20260913T091602Z-mvp-ime-draft-7231e1`（`667566c`） |
| SE・最大Dynamic Type・キーボード併用 | 本文を入力して保存・コピー可能。本文と保存操作を画像で確認 | `20260913T085832Z-mvp-compact-743c0b` |
| ダミーの返信・プロフィール・日程文、pin、編集、コピー | ライト・ダークの画面を撮影し、コピーの本文一致を確認 | `20260913T092215Z-mvp-design-07d2c4`（`873eda6`） |
| ダークの一覧・編集、検索結果0件 | 表示とアイコンのみの検索クリア操作を確認 | `20260913T092113Z-mvp-dark-fba8a3`（`873eda6`） |

画像と動画から抽出したフレームをエージェントが確認した。動画全編の人間によるリアルタイム再生、利用者試験、VoiceOverの読み上げ操作は未実施。録画にはdriverの待機・画面読取が含まれるため、長さをアプリの応答時間へ換算しない。

## 検索の測定

SE Simulator / iOS 26.5 / Releaseで、製品のSQLite actorへ検索を要求して返却されるまでを測定した。先頭100件を取得し、0・20・1,000・10,000件のダミーデータで各条件30回実行する。値は中央値 / 最大（ms）。比較する2つの測定は同じテスト・本文・保存件数を使う。

| 件数・検索語 | `a498ba4` | `8473b36` |
| --- | --- | --- |
| 0件・東 | 0.0478 / 5.3921 | 0.0305 / 2.6171 |
| 0件・該当なし | 0.0442 / 0.4370 | 0.0255 / 0.0737 |
| 20件・東 | 0.0382 / 0.0688 | 0.0441 / 0.1097 |
| 20件・該当なし | 0.0249 / 0.0379 | 0.0288 / 0.0440 |
| 1,000件・東 | 0.1169 / 0.1988 | 0.1574 / 0.3064 |
| 1,000件・該当なし | 0.3166 / 0.4478 | 0.3997 / 0.5089 |
| 10,000件・東 | 0.1211 / 0.3527 | 0.1254 / 0.2040 |
| 10,000件・該当なし | 4.5901 / 6.3731 | 4.7760 / 7.4709 |

raw値は`artifacts/mvp/search-timing-final.json`（`a498ba4`）と`artifacts/library-policy/search-timing.json`（`8473b36`）に保存した。`8473b36`の保存層・検索SQLは`9686f3a`と同じである。検索SQLと方式を共通にした測定であり、異なる実行時のホスト負荷も含む変動をライブラリによる改善・悪化と断定しない。

この値はTaskingの操作開始、IME、View更新、画面描画を含まない。UI応答・フレーム時間の定量比較は未実施であり、Simulatorの値を実機の性能予算や性能保証へ転用しない。

`xctrace record --template 'Animation Hitches' --device <UDID> --attach <PID> --time-limit 20s`は実行したが、`Hitches is not supported on this platform`で計測できなかった。記録は`artifacts/mvp/animation-pid.log`。hitchを0件と報告しない。

## 検証範囲の制約

- 実機のロック中のData Protection、起動・描画・メモリ・電力・触覚、Handoff、署名配布、App Store審査は対象外。未署名archiveは配布可否を示さない。
- VoiceOverの実操作、横向き操作、長時間利用、最大1 MB本文の入力追従は未検証。横向き切替は固定したsim-useの公開コマンドに用意されていない。
- Reduce Motionは17 Proの通知・編集開閉・再起動で確認した。小画面・最大文字・ダーク等との組み合わせや、OS部品を含む全遷移の評価を意味しない。
- 2026-09-13の表示・IME・URL・ペーストの観測は、対応するソースと条件に限る。2026-09-14の確認項目との全組み合わせを検証したものではない。
- Shortcutsの自動登録はMVPに含めない。標準URLアクションの作成とOS経由の一覧URL dispatchを観測した。ホーム画面・コントロールセンターへの配置は未検証。
- 共有の観測hostはSafari。サードパーティアプリの共有形式を網羅しない。元のアプリへの復帰とペーストは利用者が行う。
- 同期・独自バックアップは製品の提供範囲外であり、アプリ削除後の復旧は提供しない。
