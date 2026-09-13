# 開発ガイド

## プロダクトの判断基準

nibbleはiOS向けのスニペットツール。作業中に必要なスニペットを素早く呼び出せ、作成・編集・削除を迷わず行えることを価値とする。操作の少なさ、理解しやすさ、入力や描画を待たせないことを優先し、UI/UXと性能を設計・実装・レビューの受け入れ条件にする。

呼び出し導線は、対象となる作業シーンとiOSの公開API、権限、extensionの制約から設計する。呼び出し、内容の取り込み、他アプリへの挿入、作業への復帰を実機で確認し、提供できる範囲を仕様に記録する。

開発者のセットアップは [README](README.md)、実行手順は [ローカル iOS 検証](docs/ios-verification.md)、構成と採用理由は [検証基盤の設計](docs/decisions/0001-local-ios-verification.md) を参照する。

## 対応 OS

- 最低対応バージョンは **iOS 26.0**。
- アプリとextensionのdeployment targetは `26.0` にそろえる。Swift Packageにも同じ最低対応条件を適用する。
- 26.0より新しいAPIを使う場合はavailabilityを扱い、26.0で主要な体験を維持する。
- ビルド・テスト・UI/UX・性能・OS連携の実行検証は **iOS 26.5のみ** を対象とする。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認する。
- 検証対象のruntime識別子、実際のOSバージョン、buildを記録する。
- 最低対応OSの引き上げは、対象ユーザーへの影響と理由を記録し、独立した変更としてレビューする。

製品の検証対象は`app/Nibble.xcodeproj`・shared scheme `Nibble`（設定`app/project.json`、[MVP手順](docs/mvp.md)）。本体と共有拡張のApp Groupを扱うSimulator検証ではad hoc署名を指定し、Developer Teamは使わない。

基盤・研究用の検証対象は、`VerificationApp`と`ResearchProbe`。それぞれ`validation/<名前>.xcodeproj`と同名のshared schemeを持ち、deployment targetは26.0、Swift language modeは6、確認環境はXcode 26.5とする。`--project-config`で設定を選ぶ。

[共通手順](docs/ios-verification.md)はビルド・実行管理・撮影を定義し、[研究用の設計と手順](validation/RESEARCH.md)は比較するデータ・操作・判定を定義する。製品のtargetにもproject・scheme・Xcode・Swift・設定・操作の期待結果を明記する。

## 開発ツールの管理

補助ツールは [flake.nix](flake.nix) に宣言し、[flake.lock](flake.lock) をコミットして固定する。ローカルとCIは同じlockを使う。Homebrewやpipによる個別導入を開発手順の前提にしない。

| ツール | 用途 |
| --- | --- |
| Python 3 | workflow方針の検査、iOS検証スクリプト、スクリプトのテスト |
| PyYAML | workflowのYAML読込 |
| actionlint + ShellCheck | GitHub Actionsの構文・式・埋め込みシェルの検査 |
| nixfmt（`nix fmt`経由） | Nix定義の整形 |
| sim-use 0.14.0（macOSのみ） | Simulatorの画面読取・操作。release archiveをflake入力として固定 |

nixpkgsの入力は安定版 `nixos-26.05` とし、使用するrevisionはlockに固定する。補助ツールの宣言対象はApple Silicon / IntelのmacOSと、ARM64 / x86_64のLinux。nixpkgsのIntel Mac対応は26.05が最終版のため、nixpkgsの更新時に対応範囲も確認する。

Xcode、AppleのSwift、iOS SDK、Simulator runtime、署名情報はローカルMacで管理する。Nixの開発シェルは `mkShellNoCC` を使用し、iOSのビルドは選択したXcodeのツールチェーンで行う。

### 実行と検査

Gitと `nix-command` / `flakes` が有効なNixを用意する。[READMEのセットアップ](README.md#セットアップ) に従い、リポジトリルートで実行する。

```sh
# 補助ツールを使うシェル。終了は exit
nix develop

# シェルの内外から実行できる共通検査
nix flake check --no-update-lock-file --print-build-logs
```

| 検査 | 対象 |
| --- | --- |
| `workflow-policy` | runner方針、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `ios-tooling` | 端末選択、失敗伝播、テスト結果判定、録画終了処理などのPythonテスト |

共通検査はApple SDKやSimulatorを起動しない。iOSの検証は [ローカル iOS 検証](docs/ios-verification.md) のコマンドを使う。

### 依存の追加・更新

- ツールは用途、macOS / Linuxの対応、保守負担を確認してflakeへ追加する。Pythonライブラリも `python3.withPackages` で宣言し、requirementsや仮想環境で重複管理しない。
- flakeが参照するファイルはGitの追跡対象に追加する。Git管理のflakeには未追跡ファイルが含まれない。
- nixpkgsの更新は `nix flake update nixpkgs` を使い、lock差分、ツール互換性、macOSとLinuxの検証結果をPRに記録する。通常のCIとセットアップではlockを更新しない。
- Nix定義を変更したら `nix fmt flake.nix` と共通検査を実行する。依存更新は単一目的のPRにし、定義とlockを一緒に戻せる状態にする。
- アプリのSwift Package依存を使用する場合は `Package.resolved` を共有する。Nixの補助ツール管理とは責務を分ける。

## ローカルとクラウドの責務

| 検証対象 | ローカルMac / Xcode / Simulator / 実機 | GitHub Actions |
| --- | --- | --- |
| workflow・Nix・検証スクリプト | 共通検査で事前確認 | Ubuntuで共通検査を実行 |
| iOSアプリ・extensionのビルド、署名 | 変更したtargetを確認 | 実行しない |
| Apple SDKを使う単体・統合・UIテスト | 変更の影響範囲を確認 | 実行しない |
| 見た目・操作・アクセシビリティ | 操作し、画像・動画を確認 | PRに添付された証跡をレビュー |
| 起動・入力応答・描画・メモリ | Release構成を実機で測定。必要に応じてInstrumentsを使用 | iOSの性能を判定しない |
| OS・他アプリ連携、実機固有の挙動 | 公開APIの制約を含め実機で確認 | 実行しない |

Apple SDKから独立した検査を追加する場合は、Linuxで動作することを確認してCIへ組み込む。クラウドだけで作業した場合は、必要なローカル検証を未実施と記載する。対象コミットの検証結果と証跡がそろうまでマージしない。

### GitHub Actionsの制約

- **macOS runnerは禁止。** GitHub-hosted、self-hosted、再利用workflow経由を含み、iOS検証を目的とした例外も設けない。
- 各ジョブにGitHub-hostedの `runs-on: ubuntu-24.04` を直接指定する。
- runnerの式・matrixによる動的選択、runner group、self-hosted、ジョブ単位の再利用workflow呼び出しを使用しない。runner以外のmatrixは使用できる。
- Actionやスクリプトから別のmacOSジョブを起動する迂回も禁止する。
- 外部ActionはコミットSHAで固定し、更新時に実行内容と互換性を確認する。
- `Workflow policy / workflow-policy` の結果は共通検査の保証範囲に限定する。iOSのビルド・テストを保証するものではない。
- 方針検査はworkflow起動前にrunnerを遮断する仕組みではないため、workflowの差分を必ずレビューする。ブランチ保護を設定する際は、このチェックを必須にする。

## UI/UXと性能の確認

UI/UXに影響する変更は、内部実装の変更も含めて対象導線を操作し、画像・動画で確認する。コードやPreviewだけで完了としない。ビルド・テスト・実行管理・撮影はApple CLI、Simulatorの画面読取・操作はNixのsim-useを使う。

### 画像・動画の記録

- 見た目の変更は変更前後のスクリーンショットを添付する。新規画面は変更後と到達手順を示し、変更前がない理由を書く。
- 呼び出し、入力、作成・編集・削除、遷移、キーボード、アニメーション、待ち時間など、操作や時間経過を伴う変更は画面録画も添付する。
- 対象コミット、端末・Simulator、iOSバージョン、再現手順を添える。PRへの直接アップロード、またはレビュー担当者が閲覧できる保存先を使う。
- 証跡にはダミーデータを使い、個人情報や秘密情報を写さない。`artifacts/` はGit管理対象外とし、生成された `REVIEW.md` には実際に確認した内容と添付先を記録する。
- 文書・CI設定などUI/UXに影響しない変更も証跡欄を残し、「対象外」と理由を書く。必要な証跡を用意できない場合は未実施とする。

### 操作と表示の評価

| 観点 | 確認内容 |
| --- | --- |
| 基本の導線 | 呼び出しから利用までの操作数、作成・編集・削除、閉じる操作、作業への復帰 |
| 状態と回復 | 空・少量・大量データ、長文、検索結果なし、エラー、連打、繰り返し、誤削除からの回復 |
| 入力と表示 | 日本語の変換・確定、フォーカス、キーボード、小さい画面、大きな文字、ライト・ダーク |
| アクセシビリティ | VoiceOverの順序、操作領域、コントラスト、Dynamic Type、視差効果を減らす設定 |
| 応答と描画 | 起動・再呼び出し、入力追従、検索、保存、スクロール、遷移の待ち時間や引っかかり |

### 性能の評価

性能に関係する変更は、同じ実機・OS・ビルド構成・データ件数・操作条件で変更前後を比較する。起動・呼び出し時間、入力から表示までの遅延、スクロールのhitch、メモリなど、対象の体験に対応する指標を選び、測定回数と集計方法を記録する。

導線の実装時に基準値を測り、受け入れ可能な応答時間やデータ量の性能予算を決める。メインスレッドの重い処理、不要な再描画、全件読み込みを測定に基づいて見直す。体感や動画だけで改善を断定せず、悪化があれば原因と対策を示し、合意した基準を満たすまで完了としない。

## 技術の選定

モダンな技術を候補として評価し、プロダクトの体験と継続的な開発を支える適性で判断する。OS/API制約、性能、保守・運用、移行の負担を比較し、新しさだけを採用理由にしない。

製品の候補にはSwiftUI・UIKit、Observation、Swift Concurrency、Swift Testing、保存方式、App Intents、Share Extension、キーボード等がある。[研究資料](research/README.md) の事実・推奨・未確認を区別し、対象シーンと公開APIの制約を検証して選ぶ。

変更負担の大きい選択は、小さな試作で比較し、`docs/decisions/NNNN-短い名前.md` に設計判断（ADR）を記録する。

1. 解決する課題と期待する体験。
2. 比較候補、採用案、代替案を採用しない理由。
3. iOS 26.0・extension・公開APIへの適合性と必要な権限。
4. 描画・応答速度、メモリ、バッテリー、データ量への影響と検証結果。
5. APIの成熟度、テスト容易性、依存の保守状況、ライセンス、運用負担。
6. データ保護、移行・互換性、置き換える方法。
7. 決定日、状態（提案 / 採用 / 廃止）、見直す条件、関連PRと証跡。

外部依存は標準APIや小さな実装と比較する。保存・読み出しの変更では、利用者のスニペットを失わずに移行できることを確認する。

## コード公開の運用

リポジトリはコード公開を目的とし、外部からのIssue・PR・コメント等の投稿を受け付けない。GitHubの権限設定と投稿制限で運用する。Public repositoryの閲覧・clone・forkなど、GitHubが提供する機能の制約は [公開コードとライセンス](research/04-security-distribution-and-operations.md#7-公開コードとライセンス) を参照する。

## PRの作り方と完了条件

- 1 PRを小さく単一の目的にする。無関係な整形・リファクタリング・依存更新を混ぜない。
- 行数だけで判断せず、1つのアウトカムを独立して理解・検証・差し戻しできる範囲にする。大きくなる場合は、利用可能な単位に分割する。
- [PRテンプレート](.github/pull_request_template.md) の全欄を埋める。目的・背景、アウトカム、全コミットの表、画像・動画、検証結果を記載する。
- コミット表には実際のハッシュと変更の説明を書く。追加やrebase後は表を更新する。
- アウトカムは利用者・開発者に可能になることと達成条件、検証結果は対象コミット・環境・コマンド・結果を記す。未実施や対象外には理由を書く。
- UI/UX・性能に影響する修正後は再検証し、証跡を更新する。証跡取得後に関連しない変更だけを行った場合は、その範囲を記録する。
- マージ前にCI成功、必要なローカル検証、閲覧可能な証跡、PR本文と最終差分の一致を確認する。
