# 0001：ローカルiOS検証基盤の設計

- 状態：採用
- 決定日：2026-09-13
- 対象：ローカルMacでのiOS 26.5 Simulator検証とUbuntu CI
- 最低対応OS：iOS 26.0。API availabilityとdeployment targetで適合を確認する

## 目的と設計条件

ビルド、テスト、画面操作、撮影を再現可能なコマンドで実行し、開発者がデータの正しさとユーザー体験を評価できる基盤を提供する。判定にはコマンドの終了状態、期待結果との一致、画像・動画のレビューを使い、各検証の対象と条件を記録する。

補助ツールはNixで固定する。Apple SDKを使う処理はローカルXcode、Simulatorの画面読取・操作はsim-use、クラウドの静的検査はUbuntuが担当する。macOS runnerはself-hostedや間接起動を含めて使用しない。

## 全体構成

検証は、共通driver、基盤用fixture、研究用の比較試作で構成する。製品のtargetも同じ設定形式を使い、目的に合う操作・期待結果を定義する。

| 層 | 構成 | 責務 |
| --- | --- | --- |
| 共通driver | [scripts/ios.py](../../scripts/ios.py) | 引数、project設定、端末選択、プロセス、UDID単位の排他、結果保存を管理する |
| 基盤の試験 | `VerificationApp`と`smoke` | ツールチェーン、ホスト識別、文字列反映、画面操作・撮影の成立を検査する |
| 研究用比較 | `ResearchProbe`、Swift Testing、研究用driver | 保存3案、検索・復旧、UI、API、SQLite別プロセスを比較する |
| 製品の評価 | [V0〜V8の検証計画](../../research/05-decisions-and-validation.md) | 実際のhost・入口・権限・データ・実機で採用条件を評価する |
| クラウド検査 | `ubuntu-24.04`、Nix | workflow方針、Nix書式、共通driverのPythonテストを検査する |

Python標準ライブラリで各CLIを呼び出し、Appleのproject・scheme・結果bundleを直接扱う。

| 実処理 | 使用するツール | 選定理由 |
| --- | --- | --- |
| ビルド・テスト | Apple `xcodebuild` | project・scheme・destinationを明示でき、標準の結果bundleを保存できる |
| Simulatorとアプリの実行管理 | Apple `xcrun simctl` | Xcodeと同じツールチェーンで作成・起動・インストールを実行できる |
| 画面読取・操作 | Nixの`sim-use` 0.14.0 | accessibility情報を読み、識別子を使ってタップ・貼り付け等を実行できる |
| 静止画・動画 | Apple `simctl io screenshot / recordVideo` | PNG・H.264動画をCLIで取得できる |
| テスト結果の取得 | Apple `xcresulttool` | 件数・成否・添付物を結果bundleから取得できる |
| 動画の確認用フレーム | Apple Swift / AVFoundation / AppKit | Apple APIで動画を復号してフレームを抽出できる |
| SDKと別プロセスの比較 | Apple `swiftc` / `simctl spawn` | iOSの型検査とSimulatorのSQLite動作を、Mac版ライブラリと混同せず評価できる |

## 検証対象と設定

| 項目 | VerificationApp | ResearchProbe |
| --- | --- | --- |
| 目的 | 共通検証処理を試験するfixture | 製品技術の比較試作 |
| project | `validation/VerificationApp.xcodeproj` | `validation/ResearchProbe.xcodeproj` |
| shared scheme | `VerificationApp` | `ResearchProbe` |
| bundle ID | `dev.nibble.VerificationApp` | `dev.nibble.ResearchProbe` |
| 設定 | [project.json](../../validation/project.json) | [research-project.json](../../validation/research-project.json) |
| 画面の自動操作 | `scripts/ios.py smoke` | `validation/check-research-ui.py` |
| 設計・手順 | [共通コマンド](../ios-verification.md) | [研究用の構成と手順](../../validation/RESEARCH.md) |

両targetのdeployment targetは26.0、Swift language modeは6とする。project設定は`--project-config`で選ぶ。fixtureは標準UIKitの入力・反映・リセット・結果表示を持つ。ResearchProbeは独立した保存領域にダミーデータを置き、明示保存、下書き、削除復元、検索・コピーの比較を行う。

研究用アプリの画面・保存構成は実験条件として定義する。製品のUI、保存・共有方式、extension、同期の採用は、その目的に対応する検証結果で判断する。

## 依存と実行環境

補助ツールは`flake.nix`に宣言し、`flake.lock`の同じrevisionをmacOSとLinuxで使う。Nix開発シェルは`mkShellNoCC`を使用し、Appleのコンパイラを別のCツールチェーンで置き換えない。Xcode・Swift・SDK・Simulator runtime・署名情報はMac側で管理する。

sim-useはupstreamのv0.14.0 release archiveを非flake入力として取得する。URLと内容をflake/lockで固定し、アーカイブのSHA-256は`67e2ee29a7246272de8646e46664a93d9cebcace134094cfd3d07dfb82bda3e6`とする。Nixの`narHash`はファイル表現のhashであり、アーカイブのSHA-256とは別の値である。

公開バイナリはarm64 / x86_64の両sliceを含む。Mach-O署名を保持し、resource bundleを実行ファイルと同じディレクトリへ配置する。ライセンスはApache-2.0で、依存の通知はupstream配布物で管理される。sim-useの内部frameworkを配布アプリへリンクしない。

実行確認環境はApple Silicon Mac、Xcode 26.5、Apple Swift 6.3.2、Simulator SDK 26.5とする。研究用のSQLite workerとSDK driverはarm64を指定する。iPhone 17 Proと小画面用iPhone SE第3世代のiOS 26.5 Simulatorを評価に使う。`DEVELOPER_DIR`または`xcode-select`の選択先、実際のruntime version・buildを記録する。

## 操作と成否の契約

共通driverは明示したUDIDを操作する。同じUDIDへの共通driverの実行は排他制御し、端末の消去・削除は行わない。直接のsim-use操作、Xcode、研究用SQLite driverは排他に参加しないため、同じ端末の検証を直列に実行する。DerivedDataは`artifacts/ios/DerivedData/<UDID>/`で再利用する。

テストは`xcodebuild`の終了コードと`xcresulttool`のsummaryで判定する。成功したテストが1件以上必要で、0件・全skip・失敗を成功扱いしない。研究用の観測項目は期待条件と実測を結果JSONに記録し、driverの正常終了だけで全条件を合格にしない。

画面要素はsim-useの`uniqueId`で特定する。fixtureの文字列反映はAXの`value`で照合する。ResearchProbeの`UITextView`ではAX値が外側空白を省く条件があるため、コピー本文の完全一致はpasteboardのUTF-8 bytesで検査する。貼り付けによる入力と、システムIMEの変換操作は異なる試験とする。

録画は開始通知を待って操作し、失敗時にもSIGINTで保存を確定する。静止画は録画確定後に撮影する。動画の抽出フレームには実際の時刻を記録し、既定の許容幅や静止区間によって同じフレームが選ばれ得ることを考慮する。復号成功とフレーム抽出はファイルの確認であり、全編の視聴や応答・描画性能の測定を代替しない。

## 証跡と研究結果

生成物はGit管理対象外の`artifacts/`へ保存する。共通driverはコミット、未コミット状態、対象ファイルのSHA-256、端末・OS・ツール、コマンドと終了コードをmanifestへ記録する。画像・動画の確認範囲、観測した問題、PR添付先を`REVIEW.md`に記載する。

研究結果は問い・条件・観測・適用限界を[実行結果](../../research/experiments/ios-26-5-validation.md)へ記録する。画面やデータの挙動が異なる比較構成は、証跡が対応するソースを個別に示す。レビュー担当者が閲覧できる画像・動画をPRへ添付し、ローカルパスだけで証跡の提出を完了にしない。

## 代替案と保守方針

| 候補 | 評価と採用方針 |
| --- | --- |
| 専用のビルド自動化フレームワーク | 必要な処理はApple CLIとPythonで表せる。独立した設定体系や依存の保守負担を増やす便益が小さい |
| sim-useのソースビルド | idbのXCFrameworkやXcodeGen等の構築工程を必要とする。固定した公開アーカイブを使い、互換性の問題がある場合にソースビルドを比較する |
| GUI操作だけによる検証 | 条件・ログ・生成物を統一しにくい。CLIで再現性を確保し、画面・動画と操作体験をレビューする |

Xcode・OS・sim-useの互換性、target構成、署名・配布・性能測定の要件を見直し条件とする。依存更新ではURLとlockを合わせて変更し、同じデータと手順で比較する。Apple CLIの引数・ログ・結果bundleを保持し、driverや操作ツールを置き換えられる構成とする。

## 保証範囲

基盤の合格は、指定したSimulatorで検証処理と期待結果の照合が成立することを示す。実機の署名・性能・ロック時の保護、支援技術、全host・extension、同期・配布は製品ごとに評価する。SimulatorのRelease測定や自動化の所要時間を、製品の性能予算や人間の操作時間として扱わない。

根拠は[sim-use v0.14.0](https://github.com/lycorp-jp/sim-use/releases/tag/v0.14.0)、[upstream README](https://github.com/lycorp-jp/sim-use/tree/v0.14.0)、同梱の`sim-use init --print`、Apple CLIの`simctl help io`、`xcresulttool help get test-results summary`とそのschema、`xcresulttool help export attachments`とする。実行手順は[ローカルiOS検証](../ios-verification.md)を参照する。
