# 0001：ローカル iOS 検証基盤の設計

- 状態：採用
- 決定日：2026-09-13
- 対象：iOS 26.5のSimulator検証、ローカルMac、Ubuntu CI。製品の最低対応OSは26.0

## 目的と設計条件

ビルド、テスト、Simulator操作、画面記録を再現可能なコマンドで実行し、開発者が成否とユーザー体験を確認できる基盤を提供する。実行条件と生成物を保存し、コマンドの成功、期待結果の一致、画像・動画の目視確認をそれぞれ記録する。

補助ツールはNixで固定し、Apple SDKを必要とする処理はローカルXcodeで実行する。GitHub ActionsはUbuntu上の共通検査を担当する。macOS runnerはself-hostedや間接起動も含めて使用しない。

## 構成と責務

[scripts/ios.py](../../scripts/ios.py) を検証の入口とし、Python標準ライブラリで引数、端末選択、プロセスの実行、結果の保存を管理する。実処理は用途に応じて次のツールへ委ねる。

| 責務 | 構成 | 選定理由 |
| --- | --- | --- |
| ビルド・テスト | Apple `xcodebuild` | Xcodeのproject・shared scheme・destinationを直接指定でき、標準の結果bundleを残せる |
| Simulatorの作成・起動、アプリのインストール・起動 | Apple `xcrun simctl` | Xcodeと同じツールチェーンで端末とアプリの実行を管理できる |
| 画面読取・操作 | Nixの `sim-use` 0.14.0 | accessibility情報を観測し、要素の識別子を使ってタップや貼り付けを実行できる |
| 静止画・動画の記録 | Apple `simctl io screenshot / recordVideo` | SimulatorのPNG・H.264動画をCLIで取得できる |
| テスト結果 | Apple `xcresulttool` | テストの件数・成否・添付物をXcodeの結果bundleから取得できる |
| 動画のデコード・フレーム抽出 | Apple Swift / AVFoundation / AppKit | Apple配布のAPIで動画の読込と代表フレームの生成を行える |
| 補助ツールの固定 | Nix flake / lock | macOSとLinuxの依存を同じ宣言とlockで管理できる |
| クラウド検査 | `ubuntu-24.04`、Nix | Apple SDKを使わず、workflow方針・Nix書式・検証スクリプトのテストを実行できる |

## 検証用アプリと設定

`VerificationApp` は基盤の試験対象となるfixture（検証用アプリ）。標準UIKitの入力欄、反映・リセットボタン、結果表示で構成する。Swift Testingはホストの識別と原文の保持を検査し、sim-useは入力から結果表示までの操作を検査する。

設定は [validation/project.json](../../validation/project.json) にまとめる。projectは `validation/VerificationApp.xcodeproj`、shared schemeは `VerificationApp`、bundle IDは `dev.nibble.VerificationApp`。deployment targetは26.0、Swift language modeは6とする。

fixtureは検証処理に必要な最小の画面を持つ。製品本体のUI、保存方式、App Intentsやextensionの構成は [製品の検証計画](../../research/05-decisions-and-validation.md) で評価する。製品用の設定は `--project-config` で選択でき、操作の期待結果は製品ごとに定義する。

## 依存の固定と配布物

sim-useはupstreamのv0.14.0 release archiveをNixの非flake入力として取得する。URLを `flake.nix`、内容を `flake.lock` で固定する。アーカイブのSHA-256は `67e2ee29a7246272de8646e46664a93d9cebcace134094cfd3d07dfb82bda3e6`。Nixの `narHash` はファイル表現のhashであり、アーカイブのSHA-256とは異なる。

公開バイナリはarm64 / x86_64の両sliceを含む。Mach-O署名を保持するため、再署名やバイナリ加工を行わず、resource bundleを実行ファイルと同じディレクトリへ配置する。実行確認の対象はApple Silicon。ライセンスはApache-2.0で、同梱依存の通知もupstream配布物で管理される。

Xcode、Swift、SDK、Simulator runtimeはApple配布物を利用する。`DEVELOPER_DIR` または `xcode-select` の選択先を実行記録に保存する。sim-useの開発用機能や内部frameworkは配布アプリへリンクしない。

## 代替案との比較

| 候補 | 評価 |
| --- | --- |
| 専用のビルド自動化フレームワーク | 必要な処理はApple CLIと小さなPythonスクリプトで表せる。追加の設定体系・依存・更新作業を持たない構成を採用する |
| sim-useのソースビルド | idbのXCFrameworkやXcodeGen等の構築工程が必要。固定した公開アーカイブを利用し、互換性の問題がある場合にソースビルドを比較する |
| GUIによる手動実行のみ | 操作ごとの条件・ログ・成果物を統一しにくい。CLIで実行を再現し、GUIで画像・動画や操作体験をレビューする |

## 成否判定と証跡

- SimulatorはUDIDを明示して選ぶ。検証スクリプト間では同じUDIDの操作を排他制御し、端末の消去・削除は行わない。
- 非ゼロ終了を失敗として保存する。テストは `xcresulttool` のsummaryも検査し、成功したテストが1件以上あることを要求する。0件・全skip・失敗を成功扱いしない。
- UIはsim-useの `uniqueId` で要素を特定する。原文の一致には `value` を使い、空白や改行が整形され得る表示用labelを使わない。
- 動画は開始通知を待ってから操作し、操作失敗時にもSIGINTで保存を確定する。静止画は録画確定後に撮影し、動画と静止画の取得を分離する。
- 動画のデコードと代表フレームの抽出はファイルの確認に使う。ユーザー体験は画像・動画を開いてレビューする。
- 実行ごとにコミット、未コミット状態、ファイルhash、端末・OS・ツール、コマンドと終了コードを記録する。確認結果とPR添付先は `REVIEW.md` に記入する。

生成物はGit管理対象外の `artifacts/` に保存する。公開する証跡にはダミーデータを使用し、レビュー担当者が閲覧できる形でPRへ添付する。

## 対応範囲と運用

確認環境はXcode 26.5 / Apple Swift 6.3.2 / Simulator SDK 26.5。実行検証はiOS 26.5のみを対象とし、iPhone 17 Pro Simulatorでビルド、Swift Testing、操作・記録を確認する。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで点検する。

DerivedDataはUDIDごとに再利用する。各コマンドの環境確認には実行時間がかかるが、検証条件の追跡を優先する。基盤の実行時間やSimulatorのRelease実行を、製品の実機性能の測定値として扱わない。

実機の署名・配布・性能測定、IME変換、VoiceOver・Dynamic Typeの網羅的確認、extension・保存・同期は製品ごとの検証対象とする。fixtureの成功はこれらの合格条件を満たす証拠にはならない。

## 更新と見直し

Xcode・OS・sim-useの互換性、製品のtarget構成、実機の署名・配布・性能測定の要件が変わる場合に見直す。依存更新ではURLとlockを一緒に変更し、同じ検証手順で比較する。Apple CLIの引数・ログ・成果物を保持することで、検証スクリプトや操作ツールの置き換えを可能にする。

## 根拠と操作手順

- [sim-use v0.14.0](https://github.com/lycorp-jp/sim-use/releases/tag/v0.14.0)、[upstream README](https://github.com/lycorp-jp/sim-use/tree/v0.14.0)、同梱の `sim-use init --print`。
- Xcodeの `xcrun simctl help io`、`xcresulttool help get test-results summary`、`xcresulttool get test-results summary --schema`、`xcresulttool help export attachments`。
- [ローカル iOS 検証の手順](../ios-verification.md)。個別の実行結果は各実行ディレクトリの `manifest.json` / `REVIEW.md` とPRの証跡に記録する。
