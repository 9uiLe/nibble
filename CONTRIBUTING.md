# 開発ガイド

## プロダクトの判断基準

nibbleはiOS向けのスニペットツール。作業中の文脈を保ちながら必要なスニペットを素早く呼び出せ、作成・編集・削除を迷わず行えることを価値とする。操作の少なさ、理解しやすさ、入力・描画・応答の速さを設計とレビューの判断基準にする。

呼び出し、取り込み、他アプリでの利用、作業への復帰は、iOSの公開API・権限・extensionの制約に基づいて設計する。採用構成は[製品設計](docs/decisions/0002-mvp-app.md)、評価状態は[MVPの検証結果](docs/mvp-validation.md)に定義する。

| 文書 | 用途 |
| --- | --- |
| [README](README.md) | セットアップと主要コマンド |
| [UI設計](docs/design/README.md) | 情報構造、画面と部品の責務、配置理由、設計と評価の手順 |
| [ライブラリ規約](docs/library-policy.md) | 非同期処理、アニメーション、View比較の実装契約 |
| [検証基盤の設計](docs/decisions/0001-local-ios-verification.md) | 実行、証跡、CI、レビューの責務と保証範囲 |
| [ローカルiOS検証](docs/ios-verification.md) | ビルド・テスト・画面操作・撮影 |
| [証跡とPRの検査](docs/review-evidence.md) | ソースと媒体の照合、レビュー記録、PR本文とGitHubの確認 |
| [AGENTS.md](AGENTS.md)と[共有Skill](.agents/skills/nibble-verification/SKILL.md) | エージェントの判断基準と作業手順 |

設計資料は目的、採用構成、責務、契約、制約を定義する。実験条件、対象コミット、観測、失敗、未実施項目は検証記録に置く。用語を文書内で説明し、新規参加者が実装判断できる構成にする。

## 対応 OS

- 最低対応バージョンは**iOS 26.0**。本体・extension・所有するSwift Packageのdeployment targetをそろえる。
- 外部パッケージはiOS 26.0で利用できる版とAPIを選ぶ。26.0より後のAPIにはavailabilityと主要機能の代替動作を用意する。
- ビルド・テスト・UI/UX・性能・OS連携の実行検証は**iOS 26.5のみ**。実際のruntime識別子、version、OS buildを記録する。
- MVPの受け入れはSimulatorで評価し、実機検証を含めない。最低対応OSへの適合と実行対象OSでの評価を区別する。
- 最低対応OSの変更は、対象ユーザーへの影響と理由を記録した独立の意思決定とする。

| 検証対象 | 設定 | 責務と手順 |
| --- | --- | --- |
| Nibble / NibbleShare | `app/project.json` | 製品の本体・共有拡張。[製品手順](docs/mvp.md) |
| VerificationApp | `validation/project.json` | ツールチェーン・文字列反映・操作・撮影のfixture。[共通手順](docs/ios-verification.md) |
| ResearchProbe | `validation/research-project.json` | 保存・検索・復旧・OS連携の比較試作。[研究手順](validation/RESEARCH.md) |

各targetはproject・shared scheme・Xcode・Swift・設定・期待結果を定義する。Swift language modeは6、確認環境はXcode 26.5。製品のSimulator検証はApp Groupのためad hoc署名を使い、Developer Teamを使用しない。

## 開発ツールの管理

補助ツールは[flake.nix](flake.nix)に宣言し、[flake.lock](flake.lock)で固定する。ローカルとCIは同じlockを使う。Homebrew・pip・別の仮想環境による個別管理を開発手順の前提にしない。

| ツール | 用途 |
| --- | --- |
| Python 3 / PyYAML | CLIの制御、検証記録、workflowの解析、回帰テスト |
| tree-sitter-language-pack | Swiftのタスク開始・View比較の構文検査 |
| markdown-it-py | Markdownのリンク・見出し・コードブロックの解析 |
| Git / GitHub CLI | ソース、コミット、PR本文、GitHubの状態の取得 |
| actionlint / ShellCheck | workflowの構文・式・埋め込みシェルの検査 |
| nixfmt | Nix定義の整形 |
| sim-use 0.14.0（macOS） | Simulatorの画面読取と操作 |

nixpkgsは安定版`nixos-26.05`を入力とし、revisionをlockで固定する。Apple Silicon / IntelのmacOSと、ARM64 / x86_64のLinuxを宣言対象とする。nixpkgsのIntel Mac対応は26.05が最終版のため、入力更新時に対応範囲を確認する。

Xcode・Apple Swift・SDK・Simulator runtime・署名情報はローカルMacで管理する。Nix開発シェルは`mkShellNoCC`を使い、Appleのコンパイラを別のCツールチェーンで置き換えない。sim-useは固定した公開アーカイブの署名とresource bundleを保持して配置する。

### 実行と検査

[READMEのセットアップ](README.md#セットアップ)を完了し、リポジトリルートで実行する。

```sh
nix develop
nix flake check --no-update-lock-file --print-build-logs
```

| Nix check | 検査対象 |
| --- | --- |
| `workflow-policy` | runner方針、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `swift-library-policy` | 所有するSwiftの禁止API、タスク開始・所有、View比較の構文境界 |
| `ui-design` | 共通Moduleだけのruntimeで実行する照合・設定・移設・別製品の回帰テスト |
| `ios-tooling` | driver、証跡、PR、文書、Swift規約のPython回帰テスト |
| `documentation` | Markdownの相対リンク・見出し、Skillのメタデータ、Swift記載例、UI設計IDと実装・文書の照合 |

共通検査はApple SDK・Simulatorを起動せず、GitHub認証やPRを要求しない。Nixの依存取得にはネットワークが必要になる。iOS実行は`ios.py`と対象別driver、runの照合は`check_evidence.py`、PR本文と全コミットの照合は`check_pr.py`を使う。

### 依存の追加・更新

依存は用途、macOS / Linux対応、保守負担を確認して宣言する。Pythonライブラリは`python3.withPackages`で管理する。アプリのSwift Packageはexact versionと共有`Package.resolved`を使い、Nixの補助ツール管理と区別する。

flakeが参照するファイルはGitの追跡対象にする。nixpkgsの更新は`nix flake update nixpkgs`で行い、lock差分と互換性を確認する。通常のセットアップとCIではlockを更新しない。Nix定義は`nix fmt flake.nix`で整形し、共通検査を実行する。依存更新は宣言とlockを一緒に差し戻せる単一目的の変更にする。

## 非同期処理・アニメーション・View比較

モデルは処理と状態、UIはタスクの開始・所有・寿命を持つ。表示値の比較とアニメーションには適用範囲を設ける。[ライブラリ規約](docs/library-policy.md)を本体・共有拡張・テスト・研究・基盤用Swiftへ適用する。

| 責務 | 必須の契約 | 検証 |
| --- | --- | --- |
| 操作の完了 | 受理した処理と結果反映を待つ`async` API。モデルへ所有者や開始用closureを渡さない | APIを直接awaitし、戻った時点の状態と永続化を検査 |
| 開始と所有 | `startTask`の境界とswift-taskingの`ViewTaskStore` / `TaskSlot`でID・寿命・重複方針を定義 | 所有者の受理・重複・キャンセル・終了を検査 |
| 表示値の比較 | swift-app-macrosの`@Equatable`＋`@MainActor EquatableBodyView`で通常の値型`let`入力をすべて比較。状態・操作は呼出元に保持 | 入力の変更・復元と、同じ入力での外観・文字サイズの更新を検査 |
| アニメーション | swift-scoped-animationの`AnimationScope` / `animationBarrier`で適用範囲を定義 | Debug診断、入力・通知・Reduce Motionの画像・録画を確認 |

同期メソッド・setterによる隠れた開始や、タスク開始後に完了を待たず戻る操作APIは禁止する。入力setterは値と入力順序の番号だけを更新し、UIはその時点の下書きを固定して渡す。保存・閉じるは最新入力を永続化し、コピーと通知期限は別の操作にする。

生のTask・別scheduler・直接アニメーション・直接比較ゲート・手書き`==`・比較除外をLintで禁止する。構造化されたasync/await・task group・SwiftUI `.task`・協調用Task API、通常のView、値型・enumの標準Equatable合成は許可する。

Lintは構文を検査する。型解決・マクロ展開・外部APIの副作用・操作の完了はcompiler、テスト、レビューで確認する。抑制コメントを設けず、許可する入口や構文の変更は規則と回帰テストに反映する。

## ローカルとクラウドの責務

| 検証対象 | ローカルMac | GitHub Actions |
| --- | --- | --- |
| workflow・Nix・検証スクリプト・文書 | 共通検査で確認 | Ubuntuで同じ共通検査を実行 |
| iOSのビルド・テスト・実行・署名 | Apple CLIで対象targetを確認 | 実行しない |
| UI/UX・アクセシビリティ | 対象導線を操作し、画像・動画を確認 | 添付された証跡をレビューに使用 |
| 応答・描画・メモリ | Simulatorで条件と実測を記録 | iOSの性能を判定しない |
| ソース・媒体の照合 | runとコミットの入力、媒体hash、レビュー申告を照合 | ローカルrunを取得しない |
| PR本文・コミット | 公開前と公開後に照合 | PRイベントで本文と全コミットを検査 |

実機性能・ロック時の保護・Handoff・署名配布を評価する場合は、対象の実機と手順を別途定義する。Simulatorの結果だけで実機条件を保証しない。クラウドのみで作業した場合は、必要なローカル検証を未実施と記録する。

### GitHub Actionsの制約

各ジョブはGitHub-hostedの`runs-on: ubuntu-24.04`を直接指定する。runnerの式・matrix・group、self-hosted、ジョブ単位の再利用workflowを使わない。runner以外のmatrixは使用できる。Actionやスクリプトから別のmacOSジョブを起動することも禁止する。

外部ActionはコミットSHAで固定し、更新時に実行内容と互換性を確認する。workflow検査は起動前にrunnerを遮断する機構ではないため、workflowの差分はレビューする。

`workflow-policy`ジョブは共通検査とPR本文の検査を担当する。PRの作成・push・再開・本文編集・draft解除で再実行する。mainの[ruleset](.github/main-ruleset.json)はGitHub Actionsの同ジョブの成功とbaseへの追従を要求し、バイパスを設けない。設定変更時は[実効ルール](docs/review-evidence.md#githubの必須チェック)と宣言を照合する。CI成功をiOS検証済みの意味で使わない。

## TestFlight配布

TestFlightの内部配布先は、Apple Developerアカウントと端末を管理する配布担当者1名を登録した「本人用」グループとする。開発と同じmacOSユーザーで`scripts/deploy-testflight.sh`を実行し、検査・archive・署名・送信を行う。Apple側の処理と必要な申告が完了した各ビルドを、App Store Connectがグループへ自動配信する。構成と責務は[配布設計](docs/decisions/0003-testflight-distribution.md)、設定と運用は[配布手順](docs/testflight.md)に定義する。

認証設定・秘密鍵・生ログはGitに保存せず、配布担当者がリポジトリ外で管理する。エージェントは直接参照せず、レビューした配布スクリプトが返す工程・成否・公開メタデータだけを確認する。この制限は同一ユーザー内の運用規約であり、OSによるアクセス分離ではない。

署名とアップロード、Apple側の処理とグループ配信、実機インストール、実機操作を別々に確認する。配布の受け入れはiOS 26.5実機で起動・編集・コピー・共有保存を確認し、MVPのSimulator評価と区別して[検証記録](docs/testflight-validation.md)へ残す。

## UIの設計と実装

[共通ツールキット](tools/ui-design/README.md)が設計手順・ひな形・照合を担当する。製品の仕様・根拠・検証結果は`docs/design/`等、検査範囲は[policy](docs/design/policy.json)に置く。共通Moduleの単独テストとnibbleのAdapter接続テストを別々に実行し、別リポジトリへ移す際も両方を維持する。共通基盤はファイル取得と設計判定を分離し、1回の検査で同じ入力を繰り返し読まない。nibbleの文書検査も解析結果と見出しを検査内で共有し、適用する規約は文書の配置ごとに確認する。性能比較には共通ツールの`benchmarks/measure.py`と`scripts/benchmark_docs.py`を使用する。

[UI設計](docs/design/README.md)は、情報構造、部品の責務、採用理由、評価条件を定義する。設計の意味はMarkdownとMermaid、実装値と振る舞いはSwift、観測結果は対象ソースを持つ検証記録で管理する。

| 作業 | 記録・確認すること | 参照先 |
| --- | --- | --- |
| 利用場面の定義 | 目的、対象データ、操作後の復帰先、失敗・中断・復旧 | [画面構成](docs/design/screens.md) |
| 要素の割当 | 目的、構成、配置理由、代替案、評価条件 | [部品台帳](docs/design/components.md)、[共通原則](docs/design/foundations.md) |
| 候補の比較 | 外部指針、製品判断、仮説、比較条件 | [一次資料](research/06-interface-design-evidence.md)、[判断記録](docs/design/decision-template.md) |
| 実装と評価 | 状態の所有者、操作の完了、表示と回復、画像・録画 | [実装規約](docs/library-policy.md)、[製品手順](docs/mvp.md) |
| 仕様の保守 | 採用構成、対象ソースの観測、未評価条件、改善候補 | [設計監査](docs/design/audit.md)、[製品の検証結果](docs/mvp-validation.md) |

情報構造や操作の意味に関わる選択には判断記録を作り、契約内の寸法や表現の調整には部品台帳へ理由を記す。同じ責務には同じIDを使い、独立した意味を持つ要素にはIDを追加する。UIと対応する設計資料は同じ変更で更新する。

情報の順序は構成図、iOS固有のタップ・入力・スクロール・素材はSwiftUIの実装・試作で比較する。補助的なデザインツールを使う場合は、その比較目的を定め、採用結果をリポジトリの設計資料へ反映する。

台帳の網羅性、理由の妥当性、出典の適用はレビューで評価する。共通検査は文書リンク・設計IDに加え、製品ソース・設定・アセット・設計文書を照合記録へ突き合わせ、未確認の追加・変更・削除を拒否する。[照合記録の更新手順](docs/design/README.md#変更時の手順)に従い、仕様を維持する場合も確認理由を残す。動作と見た目はローカルiOS検証で確認する。PRの目的・背景には対象IDと判断の要点を記載し、評価結果は対象ソースと実施範囲に結び付ける。

## UI/UXと性能の確認

UI/UXに影響する変更は、内部実装も含めて対象導線を操作し、画像・動画で確認する。ビルド・テスト・実行管理・撮影はApple CLI、画面読取・操作はNixのsim-useを使う。

### 画像・動画の記録

- 見た目の変更は変更前後のスクリーンショットを添付する。新規画面は到達手順と、変更前がない理由を記載する。
- 呼び出し・入力・遷移・キーボード・アニメーション・待ち時間など、時間経過を伴う変更は画面録画も添付する。
- 対象コミット、端末、iOS version・build、操作手順を記載し、レビュー担当者が閲覧できる保存先を使う。
- 個人情報や秘密情報を含まないダミーデータを使う。生成物は`artifacts/`へ保存し、Git管理しない。
- 目視・抽出フレーム確認・全編再生・アップロード・閲覧を区別し、実際の確認範囲を`review.json`に記載する。

証跡は`check_evidence.py`で開始・終了・コミットの入力と媒体を照合し、レビュー申告から`REVIEW.md`を生成する。実行中の入力変化は失敗にする。必要な形式や記録のないrunを事後の推定で合格させない。UI対象外の変更も証跡欄を残し、理由を記載する。

### 操作と表示の評価

| 観点 | 確認内容 |
| --- | --- |
| 導線 | 呼び出しから利用までの操作数、作成・編集・削除、閉じる、作業への復帰 |
| 状態と回復 | 空・少量・大量データ、長文、検索結果なし、エラー、連打、繰り返し、削除取り消し |
| 入力と表示 | 日本語の変換・確定、フォーカス、キーボード、小画面、大きな文字、ライト・ダーク |
| アクセシビリティ | VoiceOverの順序、操作領域、コントラスト、Dynamic Type、Reduce Motion |
| 応答と描画 | 起動・再呼び出し、入力追従、検索・保存、スクロール、遷移の待ち時間 |

### 性能の評価

性能に関係する変更は、同じ端末・OS・ビルド構成・データ件数・操作条件で比較する。起動・呼び出し時間、入力から表示までの遅延、スクロールのhitch、メモリなど、対象の体験に対応する指標を選び、測定回数と集計方法を記録する。

導線の実装時に基準値を測り、許容する応答時間とデータ量の性能予算を決める。メインスレッドの重い処理、不要な再描画、全件読込を実測から見直す。体感や録画時間だけで改善を断定せず、合意した基準を満たすまで完了にしない。Simulatorの観測条件と限界を記載し、実機性能を評価する場合は同じ実機のRelease構成で比較する。

## 技術の選定

モダンな技術を候補に含め、OS/API制約、性能、保守・運用、移行の負担から判断する。製品MVPはSwiftUI・Observation・Swift Concurrency・Tasking・ScopedAnimation・AppMacros・Swift Testing・Apple同梱SQLite・Share Extensionを採用する。技術の新しさだけを採用理由にしない。

[研究資料](research/README.md)では事実・候補・採用判断・未確認を区別する。変更負担の大きい選択は小さな試作で比較し、`docs/decisions/NNNN-短い名前.md`へ次を記録する。

1. 解決する課題、対象シーン、期待する体験。
2. 候補、採用案、代替案の評価。
3. iOS 26.0・extension・公開APIへの適合、権限とデータ保護。
4. 描画・応答・メモリ・電力・データ量の影響と評価条件。
5. APIの成熟度、テスト容易性、依存の保守・ライセンス・運用。
6. データとAPIの互換性、移行と置き換えの方法。
7. 判断の基準日、状態、見直し条件、関連PRと証跡。

外部依存は標準APIや小さな実装と比較する。保存方式の変更は、スニペットを失わずに移行できることを検証する。

## コード公開の運用

リポジトリはコード公開を目的とし、外部からのIssue・PR・コメント等の投稿を受け付けない。GitHubの権限設定と投稿制限で運用する。Public repositoryの閲覧・clone・forkなど、GitHubが提供する機能の制約は[公開コードとライセンス](research/04-security-distribution-and-operations.md#7-公開コードとライセンス)を参照する。

## PRの作り方と完了条件

1 PRは小さく単一の目的とし、無関係な整形・リファクタリング・依存更新を含めない。行数だけで判断せず、独立して理解・検証・差し戻しができる単位にする。

[PRテンプレート](.github/pull_request_template.md)の全欄を埋める。目的・背景は課題と利用場面、アウトカムは可能になる動作と達成条件、変更内容は全コミットの実際のSHAと説明の表にする。対象外と未実施には理由を記載する。

全コミット表は`check_pr.py commits`で生成し、コミット済みの差分と本文を`local --complete`で照合する。公開後は`remote --complete --check-ci`で現在headを確認する。コマンドは[証跡とPRの検査](docs/review-evidence.md#pr本文の作成と照合)に従う。

マージには、必要なローカル検証、閲覧可能な画像・動画、PR本文と最終差分の一致、現在headのCI成功が必要になる。UI/UX・性能に影響する修正後は再検証する。文書のみの変更でrunを再利用する場合もファイル照合を行う。自動検査は記録の整合性と形式を扱い、検証の十分性、申告の真実性、単一目的かという判断はレビューが担う。
