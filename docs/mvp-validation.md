# MVPの検証結果

この文書はiPhoneアプリ`Nibble`と共有拡張`NibbleShare`の確認結果を、検証する契約ごとに案内する。機能と構成は[製品設計](decisions/0002-mvp-app.md)、再現手順と期待結果は[MVP手順](mvp.md)で定義する。最低対応OSは26.0、実行評価はiOS 26.5 Simulatorに限定し、実機検証は受け入れ範囲に含めない。

配布識別子は本体`nibble.9uiLe.com`、共有拡張`nibble.9uiLe.com.share`、App Group `group.nibble.9uiLe.com`を使用する。この構成でReleaseテスト42件と、Safariからの共有保存・本体表示・本文の完全一致を確認した。対象ソースと環境、画像・録画の確認範囲は[配布の検証記録](testflight-validation.md)を参照する。以下の既存runは、それぞれに記載した旧識別子と対象ソースに対する結果である。

## 採用している依存構成の検証状況

2026-09-16の対象ソースは`bd53d99e792241966834f0be2eb711ef0f2868e0`。依存はTasking 0.3.0、ScopedAnimation 0.2.2、AppMacros 0.3.0、swift-syntax 603.0.2である。

| 検証 | 状態 |
| --- | --- |
| パッケージ解決・ローカル共通検査 | 解決成功、Nix全5 check成功。Python回帰テスト65件・Swiftソース29件を含む |
| iOSのビルド・製品テスト | 対象マクロの承認後、Releaseビルド・42テスト成功。パラメータ展開後43実行、失敗・skipなし |
| 基本操作・Debug通知 | 標準UI driver成功。Reduce Motion無効・有効で通知表示・消去と編集開閉を確認、設定復元済み |
| 性能 | 通知のBooleanトリガー1件の解決処理を同一Simulator・Release最適化で比較。描画・操作全体の応答時間は未測定 |
| GitHub Actions | 対象PRのChecksでUbuntuの共通検査・本文検査を確認。iOS実行の結果とは区別する |

環境、対象revision、成功・失敗run、性能の実測と受け入れ条件は[Swift Package構成の検証](spm-validation.md)に記載する。以下の各記録は表記したコミットと依存構成に対する観測であり、上記構成の実行成功を示すものではない。

## 検証する契約と結果

各行は記載したソースに対する結果である。テスト件数や観測条件が異なる記録は、そのソースの評価として参照する。

| 契約 | 確認結果 | 対象と詳細 |
| --- | --- | --- |
| 一覧取得・下書き・編集終了 | 製品Releaseテスト42件成功、標準UI driver成功、Nix全5 check成功 | 製品ソース`054b09d`・driver `9e19e41`、専用17 Pro。ソース照合、性能測定、証跡と制約は[一覧と編集の検証結果](library-validation.md) |
| 操作・保存・比較View | 製品Releaseテスト28件成功、失敗・skipなし | `ba35eca`。SEでは`81d9144`の28件、専用17 Proでは外観・文字サイズを含む28件。[比較・表示更新の検証](app-macros-validation.md) |
| モデル操作の完了とUI所有者 | 操作を直接awaitした時点の状態、snapshot保存、即時保存・閉じる、通知期限、所有者の寿命・重複を確認 | `16868e6`の26件に対応する[非同期APIの検証](async-policy-validation.md)。同じ契約を製品の28件のテストにも含む |
| 基本操作と表示反映 | 作成・編集・コピー・日本語検索・ピン・削除・復元・下書き破棄。コピー本文のUTF-8と復元UUIDが一致 | `81d9144`、17 Pro、Release、標準文字・ライト。[操作と画像・動画](app-macros-validation.md#基本操作と表示) |
| 入力直後の終了・共有 | 閉じた下書きの再開・保存、Safari共有からの保存と共有元への復帰を確認 | `16868e6`、17 Pro、標準文字・ライト。[操作記録](async-policy-validation.md) |
| 通知とタスクの寿命 | Reduce Motion有効・無効で通知更新・消去・編集開閉、各5回のDebug再起動と2回のRelease再起動を確認 | `16868e6`。[非同期APIの検証](async-policy-validation.md) |
| 外観・文字サイズの追従 | 入力が等しい行でtraitを変更すると画像が変わり、戻すと初期画像に一致 | `ba35eca`。OS設定画面からの製品全体の目視評価は含めない。[比較Viewの自動検査](app-macros-validation.md#自動検査) |
| 共通Lint | ローカルMacのNix 4 check、Python 41件、Swift 18ソースが成功 | `ba35eca`のコード。[比較境界の機械検査](app-macros-validation.md#自動検査) |
| 入力・外観・OS連携 | 日本語変換、小画面・最大文字、ライト・ダーク、Safariペースト・URL共有、標準URLアクション | [記録したソースと条件](#画面とos連携)を参照 |

## 対象と環境

| 条件 | 値 |
| --- | --- |
| 実施日 | 2026-09-13〜16（JST） |
| ツールチェーン | Xcode 26.5、Apple Swift 6.3.2、Swift language mode 6、strict concurrency complete |
| iPhone 17 Pro Simulator | UDID `114E57E6-E37D-4F50-907A-8B0B6B03C92E`、402×874 pt |
| 専用iPhone 17 Pro Simulator | UDID `853E861F-6244-4F97-8072-A959309107BD`。AppMacrosの基本操作とtraitテスト |
| iPhone SE第3世代Simulator | UDID `A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`、375×667 pt |
| OS・署名 | iOS 26.5（23F77）、本体・共有拡張はad hoc署名、App Group `group.dev.nibble.app` |
| 操作と記録 | Nixで固定したsim-use 0.14.0。ビルド・テスト・実行管理・撮影はApple CLI。ダミーデータのみ |

runは1回の検証実行を識別する名前である。`artifacts/ios/<run>/manifest.json`にコミット、作業ツリーの状態、対象ファイルのSHA-256、端末、コマンド、終了コードを保存する。作業ツリーから実行したrunはファイルのSHA-256で対象を特定する。

| ソース | 対応する評価 |
| --- | --- |
| `054b09d`・`9e19e41` | 前者は一覧・下書き・編集終了・原文比較の製品ソース、後者は検証driver。42テストと標準UI driver、性能測定の条件・端末・記録は[一覧と編集の検証結果](library-validation.md) |
| `ba35eca` | 製品実装は`81d9144`と同じ。外観・文字サイズの追従を含む28テストと日本語編集メニュー用driver。詳細は[AppMacrosの検証](app-macros-validation.md) |
| `81d9144` | AppMacrosを使う一覧行の比較境界。28テスト、Debugビルド・本体起動、Releaseの作成・編集・コピー・検索・ピン・削除・復元を確認。詳細は[AppMacrosの検証](app-macros-validation.md) |
| `16868e6` | 待機可能な操作APIとUI側の明示的なTasking開始。26テスト、基本操作、即時closeからの再開・保存、共有、通知、再起動を2026-09-15に確認 |
| `9686f3afea431bdb570adce9b538340bfd9caca6` | Tasking・ScopedAnimationを使う製品構成。19テスト、Debug実行、archive、基本操作、テキスト共有、通知、再起動 |
| `8473b3632f06fe2781909a30406b3a56c3af2e99` | SQLite actorの検索測定。保存層と検索SQLは`9686f3a`と同じ |
| `a498ba4462aa8b7f0835791804710616a3bf4830` | SQLite actorの検索比較用測定。2026-09-13の保存層・URLテスト13件とgeneric iOS archiveの対象 |
| `667566c2372f3f809b4a6957776a5bd28476174f` | 2026-09-13の基本操作・IME・下書きのrunに対応するソース |
| `873eda6136cb64f075e989f694aab4b7ce5fdd70` | 2026-09-13の一覧・編集・検索表示、URL共有、一覧URLの対象 |

## ビルドと実行基盤

| 対象 | 結果と範囲 | 記録 |
| --- | --- | --- |
| 製品Debugビルド・本体実行 | `81d9144`、本体・共有拡張をビルドしSEで一覧を確認 | `20260915T144039Z-run-877130` |
| 製品Releaseビルド・テスト | `ba35eca`、専用17 Proで28件成功 | `20260915T151429Z-app-macros-traits-test-d6c4b2` |
| iOS SDK archive | `9686f3a`、generic iOS archive成功。両bundleのMIT通知が原本と一致。AppMacrosを含む構成のarchive・署名配布はこの結果に含めない | `artifacts/library-policy/archive-owned.log` |
| 研究用Releaseテスト | 14テスト、パラメータ展開後16実行が成功。製品のテスト件数には含めない | `20260914T070723Z-test-d695ae` |
| Ubuntu共通検査 | `08ce0f7`で4 check成功。Python 33件・Swift 17ソースを対象とした構成 | [実行記録](https://github.com/9uiLe/nibble/actions/runs/34965595988) |
| Ubuntu共通検査の比較記録 | `c898c40`で4 check成功。Python 25件・Swift 17ソースを対象とした構成 | [実行記録](https://github.com/9uiLe/nibble/actions/runs/34820368446) |

製品テストは使い捨てのDBと製品のモデル・保存層を使用する。原文保持、日本語・記号の検索、pinと取得上限、復元と完全削除、2接続の競合、30件の並行書込、下書き順序・遅延書込、入力エラー、未知schema、破損DB、URLの許可範囲、連続入力直後の保存・閉じるを検査する。操作完了はモデルのAPIを直接awaitし、寿命・重複・キャンセルはUI所有者で検査する。

## 画面とOS連携

以下の表示・入力・OS連携は2026-09-13のソースに対する観測である。現在の製品で同じ条件を再確認する際の比較資料として使う。表にソースのないrunはmanifestのコミットとファイルSHA-256で対象を特定する。

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

## 証跡の参照方法

| 評価領域 | 詳細記録 | 閲覧可能な添付先 |
| --- | --- | --- |
| Swift Package構成 | [依存構成の検証](spm-validation.md)。`bd53d99` | Release基本操作・Debug通知2条件の画像と録画を取得。共有先は対象PRの証跡欄 |
| 一覧・下書き・編集終了 | [一覧と編集の検証](library-validation.md)。製品ソース`054b09d`・driver `9e19e41` | [PR #10](https://github.com/9uiLe/nibble/pull/10) |
| 一覧行の比較・表示反映 | [比較Viewの検証](app-macros-validation.md)。`81d9144`・`ba35eca` | [PR #8](https://github.com/9uiLe/nibble/pull/8)の画像5点・録画2本 |
| 操作API・UI所有者・通知・共有 | [非同期APIの検証](async-policy-validation.md)。製品は`16868e6`、Lintと回帰テストは`89cf8ff` | [PR #7](https://github.com/9uiLe/nibble/pull/7)の画像5点・動画6本 |
| タスク所有・アニメーションの比較資料 | [Tasking・ScopedAnimationの検証](library-policy-validation.md)。`9686f3a`の19テスト、操作と撮影 | [PR #7](https://github.com/9uiLe/nibble/pull/7)の画像4点・動画5点 |
| 表示・日本語入力・OS連携 | この文書の入力・外観・OS連携の表。2026-09-13の各ソース | [PR #6](https://github.com/9uiLe/nibble/pull/6)の画像6点・動画6本 |

生ログ・画像・動画はGit管理対象外で、新しいcheckoutには含まれない。添付済みの証跡も対象ソースと条件を照合して使う。失敗した実行と成功した実行は別のrunとして保持し、失敗条件と再現手順は領域ごとの詳細記録に記載する。

## 検証範囲の制約

- 実機のロック中のData Protection、起動・描画・メモリ・電力・触覚、Handoff、署名配布、App Store審査は対象外。未署名archiveは配布可否を示さない。
- VoiceOverの実操作、横向き操作、長時間利用、最大1 MB本文の入力追従は未検証。横向き切替は固定したsim-useの公開コマンドに用意されていない。
- Reduce Motionは17 Proの通知・編集開閉・再起動で確認した。小画面・最大文字・ダーク等との組み合わせや、OS部品を含む全遷移の評価を意味しない。
- 表示・IME・URL・ペースト、タスク所有、通知、View比較の結果は、それぞれ記載したソースと条件に限る。異なるソースの結果を合成して、同じ構成で全条件を確認済みとは判断しない。
- AppMacrosの外観・文字サイズの追従はマウント済みの行の画像で確認した。OS設定画面を操作して製品画面全体を評価した結果とは区別する。
- Shortcutsの自動登録はMVPに含めない。標準URLアクションの作成とOS経由の一覧URL dispatchを観測した。ホーム画面・コントロールセンターへの配置は未検証。
- 共有の観測hostはSafari。サードパーティアプリの共有形式を網羅しない。元のアプリへの復帰とペーストは利用者が行う。
- 同期・独自バックアップは製品の提供範囲外であり、アプリ削除後の復旧は提供しない。
