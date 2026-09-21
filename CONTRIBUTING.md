# 開発ガイド

nibbleは、必要なテキストを探して利用し、入力を失わずに作成・編集・削除できるiOSアプリである。変更は利用者の操作、原文保持、応答、保守負担から判断する。技術の新しさや文書量を目的にしない。

## 文書の責務

| 知りたいこと | 正本 |
| --- | --- |
| 起動までの準備 | [README](README.md) |
| ソース配置・依存・責務 | [アプリケーションの構成](docs/architecture/README.md) |
| 製品のデータ・処理・失敗回復 | [製品仕様・要件](docs/product-specification.md) |
| Swiftの宣言・非同期・比較・アニメーション | [実装規約](docs/library-policy.md) |
| 画面・部品と配置理由 | [UI設計](docs/design/README.md) |
| テストの責務、削除・統合、回帰と測定の選択 | [テスト設計](docs/testing.md) |
| 検証の実行管理、画面の観測、保証範囲 | [検証基盤](docs/architecture/verification.md) |
| 検証計画・実行・画面情報の取得と要約 | [ローカルiOS検証](docs/ios-verification.md) |
| 画面確認CLIの仕様・サンプル・開発 | [観測データの確認](docs/simulator-inspection.md) |
| 製品と検証工程の測定 | [性能手順](docs/performance-verification.md)、[検証時間の測定](docs/ios-verification.md#検証時間を比較する) |
| 画像・録画の確認、ソース・媒体・PRの照合 | [証跡手順](docs/review-evidence.md) |
| CLIの入出力とhamioによる表示 | [スクリプト設計](docs/script-tooling.md) |
| 配布操作と秘密情報 | [TestFlight手順](docs/testflight.md) |
| エージェントの作業選択 | [AGENTS](AGENTS.md)、[検証Skill](.agents/skills/nibble-verification/SKILL.md) |

設計文書は目的・構成・責務・契約・制約・選択理由を、新規参加者が読める言葉で説明する。採用仕様は一箇所で定義し、他の文書は用途を添えて参照する。コードや設定の実値を転記する場合は、操作・判断に必要な理由を持たせる。

具体的な不足は設計監査、対象ソースに依存する実測・失敗・未実施は検証記録に置く。検証記録を現在の仕様や最新headの保証として使わない。完了した作業の日誌・成功件数・重複するrun一覧は恒久文書にしない。再利用する結論・制約・比較条件だけを適切な正本へ残す。

ファイル・見出しを変えるときは参照元も修正する。エージェント用の入口は作業別の参照と権限境界、Skillは工程選択、実行手順はコマンドと期待結果を所有する。

## 対応 OS

製品の本体・拡張・所有するSwift Packageの最低対応はiOS 26.0、Swift language modeは6。実行検証はiOS 26.5 Simulatorのみとし、最低OSへの適合はdeployment targetとAPI availabilityで確認する。26.0以後のAPIにはavailabilityと主要機能の代替を用意する。最低OSの変更は独立した製品判断として記録する。

| 対象 | 設定 | 手順 |
| --- | --- | --- |
| Nibble / NibbleShare / NibbleKeyboard | `app/project.json` | [製品検証](docs/ios-verification.md) |
| VerificationApp | `validation/project.json` | [実行基盤のfixture](docs/ios-verification.md) |
| Rive性能 | `app/performance-project.json` | [性能手順](docs/performance-verification.md#riveの補助指標) |

製品のSimulatorビルドはApp Groupのためad hoc署名を使い、Developer Teamを指定しない。製品の受入に実機検証は含めない。配布担当者が行うTestFlightの実機確認は別の工程である。

## 開発ツールの管理

補助ツールは[flake.nix](flake.nix)と[flake.lock](flake.lock)、アプリの依存はexact versionと[共有Package.resolved](app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)で固定する。ローカルとCIは同じlockを使い、Homebrew・pip・別の仮想環境を開発手順の前提にしない。flakeの入力はGit追跡対象とする。

Xcode・Apple Swift・SDK・Simulator・署名情報はローカルMacで管理する。Nixは`mkShellNoCC`でAppleのcompilerを置き換えない。対応CPUとセットアップはREADME、Swift依存とmacroの条件は実装規約を参照する。

依存更新は用途、互換性、保守、ライセンス、lock差分を確認する単一目的の変更とする。Nixは`nix flake update <入力名>`と`nix fmt flake.nix`を使う。通常の検査ではlockを更新しない。

## 実行と検査

リポジトリルートのNix環境で実行する。エージェントとCIは`NIBBLE_UI_FORMAT=json`を指定する。

```sh
nix develop
export NIBBLE_UI_FORMAT=json
nix flake check --no-update-lock-file --print-build-logs
```

| 共通検査 | 保証する範囲 |
| --- | --- |
| workflow-policy / nix-format | Ubuntu runner方針、workflow・shell構文、Nix書式 |
| swift-library-policy | 禁止API、タスク開始、View比較、View型・ファイル構成の構文 |
| documentation | 文書リンク、Skill、Swift例、shell例のコマンドと設定パスの実在、設計IDと未確認入力 |
| ui-design / ios-tooling | 共通設計ツールと製品Adapter、実行・証跡・PR検査の回帰 |
| rive-assets | 制作ソース・生成物・Data Binding契約 |

共通検査はApple SDK・Simulator・GitHub認証を必要としない。初回の依存取得にはネットワークが必要となる。通常の検証は[検証計画と実行](docs/ios-verification.md#変更から検証を実行する)を入口とし、共通検査と変更に対応する追加検査を実行する。以下の表で自動計画の範囲と手動確認の必要性を判断する。合格後は追加差分を再計画し、失敗や未解決の懸念がある範囲を確認する。

| 変更 | 追加で確認すること |
| --- | --- |
| 文書・指示 | 差分、参照、適用条件、正本との整合。実行挙動を変えなければiOS実行・撮影は不要 |
| Swift・依存・ビルド設定 | 対象targetのビルドと影響する契約のテスト。実装規約に従いawait直後の結果・永続化、所有者、表示入力を確認 |
| UI・操作・性能 | 内部変更も含め対象導線を実行。見た目は画像、操作・遷移・応答は録画、性能は同条件の測定 |
| 検証基盤・CI | 変更した動作の回帰。iOS実行・撮影の成立へ影響する場合は対象targetでも確認 |
| 保存済み画面の解析・加工 | [画面確認CLIの検証](docs/simulator-inspection.md#構成と開発)。画像加工とCLIはローカルMacの`preview-native`も実行 |

テストは[保証の置き場所と選択基準](docs/testing.md)に従い、削除すると見逃す現実的な不具合を根拠に置く。通常回帰と性能測定を目的に応じて選択する。統合時は固有のassertionを残し、件数やカバレッジ率を維持目標にしない。

## 作業の分離と継続

Apple Silicon MacのNix環境には[wts](https://github.com/9uiLe/wts)が入る。[設定](.wts.json)は`main`を基準に、メインチェックアウトと同じ親の`nibble-worktrees/`へセッションを作る。命名にAIや外部スクリプトを使わず、作業ごとにブランチとディレクトリを明示する。

```sh
nix develop
export NIBBLE_UI_FORMAT=json
wts --format json config check
wts --format json start --branch feature/example --worktree example
wts --format json list
```

結果の`Path`を各端末・エージェントの作業ディレクトリにし、そのルートで`nix develop`を実行する。別の作業には別名で`start`する。wtsはGitのworktreeとブランチを管理し、エージェント起動、Orcaのタブ登録、検証の実行は行わない。CLIのNDJSONは各行の`blocks`全体を解析する。オプションは`wts --format json start --help`、全手順は`wts --format json skills get wts-cli`から取得する。

`artifacts/`、DerivedData、端末のデータは共有・コピーせず、各worktreeで生成する。管理外ファイルの自動コピー設定は置かない。並列iOS実行には別々の専用UDIDを明示し、同じ端末への直接操作を重ねない。既存のdriverがworktreeをまたぐUDIDの排他を担う。性能比較は負荷条件をそろえて直列に行う。

検証中はそのworktreeのソースを固定する。編集を継続する場合は先にコミットし、別名の`start`へ`--base-branch`でそのローカルブランチを指定する。これにより文書編集でも実行中のソース照合を壊さず、結果を特定コミットへ対応付けられる。成果物が異なるソースで使えるかは既存の証跡検査で確認する。`cleanup`・`discard`は無視対象の成果物も削除し得るため、保存すべき内容を確認し、依頼された削除範囲だけを扱う。

コンテキストを引き継ぐときは`artifacts/handoff.md`に目的・ブランチ・次の操作・未解決条件、読んだ資料とそのGit revisionまたはhash、検証の`result.json`とrunのパスを短く残す。会話・ログ・規約全文を複製しない。次の担当は`git status`と差分、[検証状態の要約](docs/ios-verification.md#検証状態を確認する)を確認し、変わった入力に対応する資料と検査だけを開く。handoffの記載を検証成功の根拠には使わない。

リポジトリの指示は[AGENTS](AGENTS.md)を作業別の入口とし、宣言・構文・検査契約は各正本に集約する。CodexやOrcaが注入するシステム指示・スキル一覧、トークン計測の提供範囲は実行環境側の責務であり、このリポジトリで置き換えない。

### スクリプトの表示とデータ

stdoutは結果データ、stderrは工程と診断に使う。[表示Adapter](docs/script-tooling.md)の障害で業務処理を再試行しない。秘密情報と生ログを表示APIへ渡さない。

## UIの設計と実装

[UI設計](docs/design/README.md)から対象IDの目的・構成・配置理由・制約・評価条件を確認する。採用仕様、外部根拠、仮説、観測を区別する。共通ツールキットは製品非依存とし、nibbleのパス・検査範囲は製品のpolicyへ置く。

設計と実装を照合し、確認文書と判断要約をreview.jsonに記録する。仕様を維持する変更にも根拠を記す。ID・hashは機械検査、理由と網羅性はレビュー、挙動と見た目は実行検証の責務である。更新方法は[変更時の手順](docs/design/README.md#変更時の手順)に従う。

## 性能の評価

応答・フレーム・メモリ・容量は異なる評価単位である。対象導線の基準値と許容条件を決め、同じソース条件・端末・OS・Release構成・データ・操作で比較する。体感、body回数、画像一致、driverの待機を含む録画時間で高速化を断定しない。[性能手順](docs/performance-verification.md)で測定の成立と適用限界を確認する。

## ローカルとクラウドの責務

iOSのビルド・テスト・操作・撮影・性能はローカルMacで行う。Apple CLIが実行と撮影、Nixのsim-useが画面の読取と操作を担う。ダミーデータと専用Simulatorを使い、既存端末を消去・削除しない。

GitHub Actionsの全jobは`runs-on: ubuntu-24.04`を直接指定する。runnerの式・matrix・group、self-hosted、job単位の再利用workflow、別サービス経由のmacOS起動は禁止。外部ActionはSHA固定。Ubuntuの成功をiOS検証済みと扱わない。

## TestFlight配布

配布は[専用手順](docs/testflight.md)で行う。署名・送信と、Apple側の処理・本人用グループへの配信・実機確認を分ける。秘密情報の設定と生ログ確認は配布担当者、エージェントはレビュー済みスクリプトによる工程・成否・公開manifestの確認を担う。

## 技術の選定

OS/API制約、原文とデータの安全性、実測した応答・描画、保守・依存更新、移行と復旧の負担を比較する。変更負担の大きい選択は小さい比較実験で確かめ、製品の設計文書へ目的・構成・責務・要件に対する利点と負担・見直し条件を記す。実験結果は対象ソース付きの記録とし、設計文書は採用する仕様を直接説明する。

## コード公開の運用

コード公開を目的とし、外部からのIssue・PR・コメント投稿を受け付けない。GitHubの権限設定と投稿制限で運用する。公開リポジトリの閲覧・clone・forkはGitHubの機能に従う。[ライセンスと公開範囲](docs/reference/security.md#公開コードとライセンス)を参照する。

## PRの作り方と完了条件

1 PRは単一の目的とし、無関係な整形・依存更新を混ぜない。[PRテンプレート](.github/pull_request_template.md)の全欄・全コミットを最終差分へ対応させる。UI対象外でも理由付きで証跡欄を残す。

マージには必要なローカル検証、閲覧可能な媒体、本文と全コミットの一致、最終headのCI成功、baseへの追従が必要。[証跡手順](docs/review-evidence.md)でlocal/remoteを照合する。mainの必須checkを変える場合は[ruleset宣言](.github/main-ruleset.json)と実効ルールをそろえる。未実施を完了へ書き換えない。
