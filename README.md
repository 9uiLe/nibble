# nibble

nibbleは、よく使うテキストを保存し、必要なときに探してコピーするiPhone向けのスニペットツールです。最低対応OSはiOS 26.0。使いやすさ、シンプルさ、描画と応答の速さを設計の判断基準にします。

## MVPでできること

- 作成・編集、日本語1文字からの検索、ピン留め、本文のコピー。
- 削除と復元、確認付きの完全削除、下書きの保存・再開。
- 共有シートからテキスト・URLを取り込み、標準ショートカットから一覧・作成画面を呼び出し。

日本語UIの本体と共有拡張は、アカウントや通信を必要とせず、テキストを端末内へ保存します。入力先のアプリへの復帰とペーストは利用者が行います。同期・独自バックアップ・キーボード拡張は提供しません。

## 設計資料とリポジトリの構成

開発に参加する際は、[製品設計](docs/decisions/0002-mvp-app.md)で目的・提供範囲・画面・保存・処理の所有者を確認し、[実装規約](docs/library-policy.md)で非同期処理とアニメーションの入口を確認してください。[操作と検証手順](docs/mvp.md)は期待する動作、[検証結果](docs/mvp-validation.md)は実際に確認したソース・条件・制約を示します。実行評価はiOS 26.5 Simulatorを対象とし、実機検証はMVPの受け入れ範囲に含みません。

このリポジトリは、製品アプリ、開発規約、研究資料、Apple CLIとsim-useによるローカルiOS検証を管理します。

| アプリ | 目的 | 設定・手順 |
| --- | --- | --- |
| Nibble / NibbleShare | 本体と共有拡張。日常のスニペット作成・検索・利用 | [MVPの操作と検証](docs/mvp.md)、`app/project.json` |
| VerificationApp | 検証コマンド、文字列反映、テスト、撮影の成立を確かめるfixture | [共通の検証手順](docs/ios-verification.md)、`validation/project.json` |
| ResearchProbe | 保存3案、検索、入力、コピー、復旧、OS連携を同じダミーデータで比較する | [設計と実行手順](validation/RESEARCH.md)、`validation/research-project.json` |

本体と共有拡張は、SwiftUI・Observationによる画面、Taskingによる非構造化タスクの所有、ScopedAnimationによる表示変化の範囲、Swift Concurrencyのactor内で扱うApple同梱SQLiteで構成します。2つのプロセスはApp Groupの保存先を共有します。モデルは完了まで待機可能な`async` APIを公開し、UI側がタスク開始を選びます。隠れたタスク開始、開始APIの別名化、Tasking・ScopedAnimationを経由しない直接APIはLintで禁止します。[研究資料](research/README.md)は採用理由の根拠と比較候補を管理し、試作の結果は記録した構成に限って解釈します。

| 入口 | 内容 |
| --- | --- |
| [開発ガイド](CONTRIBUTING.md) | 対応OS、依存管理、ローカルとCIの責務、UI/UX・性能、PRの規約 |
| [非同期処理とアニメーション](docs/library-policy.md) | Taskingの所有・寿命・重複方針、ScopedAnimationの適用範囲、禁止APIとLint |
| [製品の検証結果](docs/mvp-validation.md) | ソースごとのテスト・操作・画像と動画・検索測定、未検証の条件 |
| [検証基盤の設計](docs/decisions/0001-local-ios-verification.md) | Apple CLI・sim-use・Nixの役割、構成、採用理由、対応範囲 |
| [ローカル iOS 検証](docs/ios-verification.md) | Simulatorの準備、ビルド・テスト・操作・画面記録、証跡の確認 |
| [研究用の実行検証](validation/RESEARCH.md) | ResearchProbeの構成、データ・操作の契約、再現コマンド |
| [研究資料](research/README.md) | 論文・一次資料による仕様の根拠、設計候補、製品の検証計画 |
| [AGENTS.md](AGENTS.md) | AIエージェント向けの規約の入口 |
| [PRテンプレート](.github/pull_request_template.md) | 目的・背景、アウトカム、コミット表、画像・動画、検証結果の記載形式 |

## セットアップ

補助ツールは [flake.nix](flake.nix) に宣言し、[flake.lock](flake.lock) で固定します。AppleのツールチェーンはローカルのXcodeを使用します。

| 環境 | 用途・前提 |
| --- | --- |
| macOS（Apple Silicon / Intel） | Nixの共通検査。iOSの検証にはXcodeと対象Simulator runtimeも必要 |
| Linux（ARM64 / x86_64） | Nixの共通検査。Apple SDKを使うビルド・テストはローカルMacで実行 |
| iOS検証の確認環境 | Xcode 26.5、Apple Swift 6.3.2、Swift language mode 6、Simulator SDK 26.5 |
| 検証対象 | iOS 26.5のみ。`Nibble` / `VerificationApp` / `ResearchProbe`、deployment target `26.0` |
| 研究用driver | Apple Silicon Mac。SDK型検査とSQLite workerはarm64を指定 |

### 1. GitとNixを用意する

Gitと [Nix](https://nixos.org/download/) をインストールし、ターミナルを開き直して確認します。

```sh
git --version
nix --version
```

Nixの `nix-command` / `flakes` を有効にします。機能が無効な場合は `~/.config/nix/nix.conf` に次の設定を追加します。`experimental-features` に設定済みの値がある場合は、その値を残して統合してください。

```conf
experimental-features = nix-command flakes
```

### 2. リポジトリを取得する

```sh
git clone https://github.com/9uiLe/nibble.git
cd nibble
```

以降のコマンドはリポジトリルートで実行します。

### 3. 補助ツールを起動・検査する

```sh
nix develop
nix flake check --no-update-lock-file --print-build-logs
```

初回はlockで固定した依存を取得します。開発シェルではPython 3・PyYAML・actionlint・ShellCheckが使え、macOSではsim-use 0.14.0も使えます。終了は `exit` です。Homebrewやpipによる個別導入は不要です。

共通検査は `workflow-policy`・`nix-format`・`ios-tooling`・`swift-library-policy` の4つです。workflowのrunner・構文・シェル、Nix書式、iOS検証スクリプトの失敗処理、Tasking・ScopedAnimationを経由しない直接APIの使用を検査します。GitHub Actionsも `ubuntu-24.04` で同じlockとコマンドを使います。Apple SDKやSimulatorを使う検証は次の手順で行います。

### 4. Xcodeを準備する

iOSを検証するMacに [Xcode](https://developer.apple.com/xcode/) をインストールし、一度起動してライセンス確認と追加コンポーネントの導入を完了します。検証基盤の確認環境はXcode 26.5です。使用するSDKはiOS 26.0以上のdeployment targetに対応している必要があります。

Xcodeの Settings → Locations → Command Line Tools で使用するXcodeを選び、確認します。

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
```

Xcodeの設定からiOS 26.5のSimulator runtimeを導入します。ビルド・テスト・操作・性能の実行検証は26.5のみを対象とし、検証記録には実際のversionとbuildを残します。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認します。

Xcode・AppleのSwift・SDK・runtime・署名情報はMac側で管理します。シェルごとにXcodeを選ぶ場合は `DEVELOPER_DIR` を設定します。設定例と対応範囲は [ローカル iOS 検証](docs/ios-verification.md) を参照してください。

アプリのSwift Packageはswift-tasking 0.3.0とswift-scoped-animation 0.2.1を使用し、exact versionと共有`Package.resolved`で固定します。初回はネットワーク接続のあるMacで次を実行します。ライセンス・更新方針は[依存とビルド](docs/library-policy.md#依存とビルド)を参照してください。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

### 5. Simulatorで検証する

環境と利用可能な端末を確認します。

```sh
nix develop --command python3 scripts/ios.py doctor
nix develop --command python3 scripts/ios.py devices
```

[Simulatorの作成・選択手順](docs/ios-verification.md#simulatorの作成と選択)に従って専用端末を用意し、そのUDID（端末の一意な識別子）を`NIBBLE_SIMULATOR`に設定します。製品アプリは`app/project.json`で指定します。共有拡張のApp Groupを使用するため、SimulatorでもXcodeのad hoc署名を行います。証明書やDeveloper Teamは不要です。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py run \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
```

基本の操作と撮影を自動で確認するには、専用driverを使います。共有・ペースト・日本語入力の手順は[MVPの操作と検証](docs/mvp.md)を参照してください。

```sh
nix develop --command python3 scripts/check-mvp-ui.py --device "$NIBBLE_SIMULATOR"
```

共通検証処理を試験するVerificationAppには、標準設定の`test`と`smoke`を使います。`smoke`はfixture専用で、製品アプリの操作検証は行いません。

```sh
nix develop --command python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py smoke --device "$NIBBLE_SIMULATOR"
```

保存・検索などの比較は、ResearchProbeの設定と専用のUI driverを使います。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config validation/research-project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 validation/check-research-ui.py --device "$NIBBLE_SIMULATOR"
```

結果はGit管理対象外の `artifacts/` に保存されます。画像と動画を開いて内容を確認し、生成された `REVIEW.md` に確認結果とPRの添付先を記録します。

## よく使うコマンド

| 操作 | コマンド |
| --- | --- |
| 開発シェルを起動 | `nix develop` |
| CIと同じ検証 | `nix flake check --no-update-lock-file --print-build-logs` |
| runner方針だけを検査 | `nix develop --command python3 scripts/check_workflows.py` |
| Swiftライブラリ規約だけを検査 | `nix develop --command python3 scripts/check_swift_policy.py` |
| Nix定義を整形 | `nix fmt flake.nix` |
| iOS検証環境を確認 | `nix develop --command python3 scripts/ios.py doctor` |

依存の追加・更新は [開発ツールの管理](CONTRIBUTING.md#開発ツールの管理)、実装とレビューは [開発ガイド](CONTRIBUTING.md) に従います。セットアップ時にlockを更新する必要はありません。
