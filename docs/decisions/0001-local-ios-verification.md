# 0001：検証とレビュー基盤の設計

- 状態：採用
- 設計基準日：2026-09-16
- 対象：ローカルMacでのiOS検証、証跡の管理、Ubuntu CI、PRの検査
- 最低対応OS：iOS 26.0。実行検証の対象はiOS 26.5のみ

## 目的と設計条件

nibbleの検証基盤は、製品の正しさと使いやすさを、対象ソース・実行条件・観測結果に基づいて評価するために設ける。ビルドやコマンドの成功に加え、保存内容、画面への反映、操作と遷移、描画・応答性能を確認する。レビュー担当者は、評価したソースと証跡を対応付けて変更を判断できる。

機械的に扱える条件はスクリプトとGitHubの必須チェックで検査する。目視による品質評価、測定条件の妥当性、必要な導線を検証したかという判断はレビューの責務とする。検査の成功と、製品の受け入れ条件を満たすことを区別する。

補助ツールはNixで固定する。Apple SDKを使う処理はローカルXcode、Simulatorの画面読取・操作はsim-use、クラウドの検査はUbuntuが担当する。macOS runnerはself-hosted・再利用workflow・間接起動を含め使用しない。MVPの受け入れはSimulatorで評価し、実機検証を含めない。

## 全体構成

| 構成 | 実装 | 責務 |
| --- | --- | --- |
| 開発規約 | [開発ガイド](../../CONTRIBUTING.md)、[実装規約](../library-policy.md) | プロダクトの判断基準、コードの契約、検証とPRの完了条件を定義 |
| エージェントの入口 | [AGENTS.md](../../AGENTS.md)、[共有Skill](../../.agents/skills/nibble-verification/SKILL.md) | 判断基準と作業手順を参照可能にする |
| ローカル実行 | [ios.py](../../scripts/ios.py)、対象別の操作driver | project・端末・プロセス・排他制御・成否・生成物を管理 |
| 進捗と結果の表示 | [共通表示Adapter](../../scripts/script_ui.py)、hamio | 公開可能な工程と結果をstderrへ表示。業務の成否と実行記録は呼出元が所有 |
| 証跡の照合 | [verification_evidence.py](../../scripts/verification_evidence.py)、[check_evidence.py](../../scripts/check_evidence.py) | ソース、実行記録、媒体、レビュー申告を照合 |
| 共通検査 | [flake.nix](../../flake.nix)の5つのcheck | workflow、Nix、Swift規約、Python回帰テスト、文書を検査 |
| PR検査 | [check_pr.py](../../scripts/check_pr.py) | 本文と実際の全コミット・変更ファイル・対象headのcheck runを照合 |
| マージ条件 | [workflow](../../.github/workflows/workflow-policy.yml)、[ruleset](../../.github/main-ruleset.json) | Ubuntuで検査し、mainへの更新に`workflow-policy`の成功を要求 |

開発規約は判断基準、スクリプトは検査可能な条件、Skillは対象選択・操作・失敗切り分けを受け持つ。詳細な手順は担当するガイドへ集約し、AGENTS.mdから参照する。文書間と実装ファイルへの参照先の存在はリンク検査で確認する。

## 検証対象と設定

| 項目 | Nibble / NibbleShare | VerificationApp | ResearchProbe |
| --- | --- | --- | --- |
| 目的 | 製品の本体と共有拡張 | 共通検証処理を試験するfixture | 製品技術の比較試作 |
| project | `app/Nibble.xcodeproj` | `validation/VerificationApp.xcodeproj` | `validation/ResearchProbe.xcodeproj` |
| shared scheme | `Nibble` | `VerificationApp` | `ResearchProbe` |
| bundle ID | `nibble.9uiLe.com` / `nibble.9uiLe.com.share` | `dev.nibble.VerificationApp` | `dev.nibble.ResearchProbe` |
| 設定 | [app/project.json](../../app/project.json) | [validation/project.json](../../validation/project.json) | [validation/research-project.json](../../validation/research-project.json) |
| 画面の自動操作 | `scripts/check-mvp-ui.py` | `scripts/ios.py smoke` | `validation/check-research-ui.py` |
| 期待結果と手順 | [製品手順](../mvp.md) | [共通手順](../ios-verification.md) | [研究手順](../../validation/RESEARCH.md) |

各targetのdeployment targetは26.0、Swift language modeは6。共通driverは`--project-config`で設定を選び、省略時はVerificationAppを使用する。製品はApp GroupのentitlementをSimulatorへ渡すため、`simulator_signing: "ad-hoc"`でローカル署名を指定する。証明書・Developer Teamは使わない。基盤・研究用fixtureは未署名でビルドする。

VerificationAppは入力・反映・リセットを持ち、文字列照合と操作・撮影の成立を検査する。ResearchProbeは独立した保存領域とダミーデータで、保存方式・検索・復旧・OS連携を比較する。製品の採用構成は[製品設計](0002-mvp-app.md)、評価状態は[MVPの検証結果](../mvp-validation.md)を正とする。fixtureや比較試作の合格を製品の合格に置き換えない。

## 依存と実行環境

補助ツールは`flake.nix`に宣言し、`flake.lock`の同じrevisionをmacOSとLinuxで使う。Pythonとそのライブラリ、Git、GitHub CLI、actionlint、ShellCheck、nixfmt、macOS用sim-useをNixで管理する。開発シェルは`mkShellNoCC`を使用する。Xcode・Apple Swift・SDK・Simulator runtime・署名情報はMac側で管理する。

| 処理 | 使用するツール | 採用理由 |
| --- | --- | --- |
| ビルド・テスト | Apple `xcodebuild` | project・scheme・destinationを明示し、標準の結果bundleを保存できる |
| Simulatorとアプリの実行管理 | Apple `xcrun simctl` | Xcodeと同じツールチェーンで作成・起動・installを実行できる |
| 画面読取・操作 | Nixの`sim-use` 0.14.0 | accessibility情報から要素を特定して操作できる |
| 静止画・動画 | Apple `simctl io screenshot / recordVideo` | PNGとH.264動画をCLIで取得できる |
| テスト結果 | Apple `xcresulttool` | 実行件数・成否・添付物を結果bundleから取得できる |
| 動画の抽出フレーム | Apple Swift / AVFoundation / AppKit | Apple APIで復号し、実際の時刻と画像を保存できる |
| SDKと別プロセスの比較 | Apple `swiftc` / `simctl spawn` | iOSの型検査とSimulatorのSQLite動作を評価できる |
| ソース・PRの照合 | Git / GitHub CLIとPython | コミット、ファイル内容、GitHubの記録を直接扱える |
| Swift・文書の構文解析 | tree-sitter-language-pack / markdown-it-py | 言語とMarkdownの構造を解析できる |

sim-useはv0.14.0の公開アーカイブを非flake入力として固定する。アーカイブのSHA-256は`67e2ee29a7246272de8646e46664a93d9cebcace134094cfd3d07dfb82bda3e6`。lockの`narHash`はNixのファイル表現を識別する値であり、アーカイブそのもののSHA-256と区別する。配布バイナリのarm64 / x86_64 slice、Mach-O署名、実行ファイルに隣接するresource bundleを保持する。ライセンスはApache-2.0で、配布アプリへsim-useの内部frameworkをリンクしない。

実行確認環境はApple Silicon Mac、Xcode 26.5、Apple Swift 6.3.2、Simulator SDK 26.5。研究用SQLite workerとSDK driverはarm64を指定する。端末はiPhone 17 Proや小画面用iPhone SE第3世代を使用し、実際のUDID・runtime version・OS build・Xcode選択先を記録する。

表示の入出力、障害時の動作、Nix依存、秘密情報境界は[開発スクリプトの契約](../script-tooling.md)に定義する。

## 実行の契約

### 対象と排他制御

共通driverは明示したUDIDだけを操作し、利用可能なiOS 26.5のruntimeを要求する。端末作成時も同じバージョンを要求する。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認する。

同じUDIDを使う共通driverは排他制御する。直接のsim-use、Xcode、研究用SQLite driverはこの排他に参加しないため、端末単位で検証を直列に実行する。端末の消去・削除は行わない。DerivedDataは`artifacts/ios/DerivedData/<UDID>/`に置くコンパイルcacheであり、証跡の対象ソースを決める根拠には使わない。

### 成否と回復

コマンドは引数、stdout、stderr、終了コード、所要時間を記録する。テストは`xcodebuild`の終了コードと`xcresulttool`のsummaryで判定し、成功したテストが1件以上必要となる。0件・全skip・失敗を成功にしない。研究用の評価は、期待条件と実測を結果JSONで照合する。

driverが既知の終了コード1を処理する場合は、そのコマンドに理由と結果を検証するassertion名を記録する。証跡検査は、指定assertionが`true`でrun全体が成功した場合だけ処理済みとして認める。タイムアウトや任意の非ゼロ終了は許可しない。失敗runは独立した記録として保存し、成功runで上書きしない。

### 画面と文字列

画面要素はsim-useの観測結果にある`uniqueId`で特定する。fixtureの文字列反映はaccessibilityの`value`、コピー本文はpasteboardのUTF-8で照合する。整形されたoutlineやlabelを原文一致の根拠にしない。項目の追跡には一意な検索語とUUIDを使い、表示行数に依存しない。

貼り付け、システムIMEの変換、保存、再表示、コピーはそれぞれの期待結果を検証する。日本語編集メニューの操作は観測できた要素に限定し、製品driverでは編集後本文の完全一致まで確認する。

### 撮影

録画は開始通知を待ってから操作し、操作に失敗した場合もSIGINTで保存を確定する。fixtureのsmokeは録画確定後に操作後の静止画を撮る。動画は代表フレームと実際の抽出時刻を保存する。静止区間やAPIの許容幅により、複数の指定時刻で同じフレームが選ばれる場合がある。

## 証跡のデータと照合

1回のコマンド実行をrunと呼び、`artifacts/ios/<UTC日時>-<コマンド>-<ID>/`で識別する。ソース、実行結果、媒体、レビュー申告を別々の記録として保存する。

| 記録 | 内容と所有者 |
| --- | --- |
| `manifest.json` | driverが実行条件・コマンド・成否・開始と終了のソースhash・媒体hashを保存 |
| ログ・xcresult・結果JSON | 実行コマンドと期待結果の根拠 |
| PNG・MP4・`video-frames/` | 画面と時間経過を確認するための媒体 |
| `review.json` | 確認者が媒体hash、確認方法、観測、未実施条件、添付URL、閲覧結果を申告 |
| `REVIEW.md` | 証跡検査が整合性を確認したレビュー申告を、人が読める形式で出力 |

証跡形式は`evidence_version: 1`とする。ソースの照合範囲は、projectを含む`app/`または`validation/`全体、共有`scripts/`、`flake.nix`、`flake.lock`。Markdownを除き、ファイルの追加・変更・削除を検査する。実行中に入力が変わるとrunを失敗にする。

`check_evidence.py`は開始・終了の入力と指定Git revisionのファイル内容を照合する。同じrun内で、対象scheme・UDIDへのビルド成功が記録されていることも要求する。文書のみの変更で入力が一致する場合はrunを再利用できる。単独の`screenshot`・`record`にはビルドの対応がないため、補助的な撮影記録として扱う。

必要な形式・開始と終了のhash・実行記録が不足するrunは、ソース照合に使用できない。不足した情報を事後に推定して成功認定しない。媒体はrun確定時のhashと照合し、レビュー申告も同じ媒体のhashに結び付ける。

## レビューとPR

画像の目視、動画の抽出フレーム確認、全編再生、アップロード、ブラウザーでの読込を独立した確認として記録する。動画の確認方法は`sampled`または`continuous`とし、`sampled`には原本の実際の確認時刻を記載する。ブラウザーでは媒体の読込と閲覧時のログイン状態を確認する。HEADの結果だけでは閲覧可否を判定しない。

PRは[テンプレート](../../.github/pull_request_template.md)の目的・背景、アウトカム、全コミット表、画像・動画、検証結果、レビュー前の確認を持つ。`check_pr.py`は実際の全コミットと表を照合し、UI対象ファイルには画像・録画と対象コミット・端末・iOS 26.5・操作の記載を要求する。対象外の欄は理由付きで残す。ファイル配置によるUI対象の判定は保守的な検査であり、影響範囲の最終判断はレビューで行う。

ローカルではコミット済みの差分と本文を照合する。GitHubでは全コミット・変更ファイルをページングして取得し、件数不足や取得中のhead・本文変更を拒否する。`--complete`は未完了チェック項目を拒否し、`--check-ci`は取得したheadのcheck runが成功していることを確認する。これらのコマンドはPRの作成・編集・マージを行わない。

## 共通検査とマージ条件

| Nix check | 保証する範囲 |
| --- | --- |
| `workflow-policy` | 明示したUbuntu runner、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `swift-library-policy` | 所有するSwiftソースの禁止API、タスク開始・所有、View比較の構文境界 |
| `ios-tooling` | driver、証跡、PR、文書、Swift規約を検査するPythonの回帰テスト |
| `documentation` | Markdownの相対リンク・見出し、Skillのメタデータ、実装規約のSwift記載例 |

共通検査はApple SDKやSimulatorを起動せず、ローカルとUbuntuで同じlockを使用する。Swift規約の字句・構文検査と、Swift compiler・製品テスト・画面評価の分担は[実装規約](../library-policy.md)に定義する。

GitHub Actionsの`workflow-policy`ジョブは共通検査を実行し、PRイベントでは本文を`--complete`で検査する。PRの作成、push、再開、本文編集、draft解除で再実行する。進行中のジョブから自身のCI完了は確認しない。

mainにはGitHub Actions（integration ID `15368`）による`workflow-policy`の成功とbaseへの追従を要求する。管理者を含むバイパスは設けない。rulesetの宣言JSONとGitHubの実効設定は別に管理されるため、ジョブ名・条件の変更時は両方を照合する。workflow検査はジョブ起動前にrunnerを遮断する機構ではないため、workflowの差分もレビューする。

## 保証範囲と保守方針

hashと実行記録の照合は、記録間の整合性を検査する。記録の改ざんに対する署名、install済みバイナリの独立した鑑定、目視や閲覧の実施そのものの証明は行わない。GitHubの本文検査は、Git管理対象外のローカルrunを再検査しない。記録の真実性、期待結果、製品の品質は、対象ソースと証跡を用いてレビューする。

Simulatorの合格は実機性能、ロック時の保護、署名配布、全host・extension、支援技術、同期を保証しない。自動操作の待機を含む録画時間は応答時間に換算しない。性能は同じ端末・OS・構成・データ・操作条件で測定する。

| 比較候補 | 採用判断 |
| --- | --- |
| 専用のビルド自動化フレームワーク | 必要な処理はApple CLIとPythonで表せるため、独立した設定体系を増やさない |
| sim-useのソースビルド | idbのXCFrameworkやXcodeGen等の構築を避け、固定した公開アーカイブを使う。互換性の問題がある場合に比較する |
| GUIだけの検証 | CLIで条件・ログをそろえ、GUIは画面評価とCLIで扱えない操作に使用する |
| 自然言語の確認項目だけによる運用 | ファイルと記録の不変条件を自動検査し、判断が必要な品質評価をレビューへ残す |

Xcode・OS・sim-useの互換性、target構成、証跡形式、GitHub API、署名・配布・性能測定の要件を見直し条件とする。検査を変更する場合は、許可する例と拒否する例を回帰テストへ追加する。依存更新では宣言とlockをそろえ、同じデータと手順で確認する。

操作手順は[ローカルiOS検証](../ios-verification.md)、証跡とPRのコマンドは[証跡とPRの検査](../review-evidence.md)、実測結果は[基盤の検証記録](../review-tooling-validation.md)を参照する。Apple CLIとsim-useの根拠は[sim-use v0.14.0](https://github.com/lycorp-jp/sim-use/releases/tag/v0.14.0)、[upstream README](https://github.com/lycorp-jp/sim-use/tree/v0.14.0)、`sim-use init --print`、`simctl help io`、`xcresulttool`のhelpとschemaとする。
