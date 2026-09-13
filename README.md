# nibble

nibble は iOS 26.0 以上向けのスニペットツールです。作業中に必要なテキストを素早く呼び出し、作成・編集・削除を少ない操作で行える体験を目指します。使いやすさ、シンプルさ、描画と応答の速さを設計の判断基準にします。

## リポジトリの構成

このリポジトリは、開発規約、製品設計の研究資料、ローカルの iOS 検証基盤を管理します。実行対象の `VerificationApp` は、入力・操作・テスト・撮影を確かめる検証用アプリです。製品本体の機能、画面、保存方式、呼び出し導線は [研究と検証計画](research/README.md) の評価対象です。

| 入口 | 内容 |
| --- | --- |
| [開発ガイド](CONTRIBUTING.md) | 対応OS、依存管理、ローカルとCIの責務、UI/UX・性能、PRの規約 |
| [検証基盤の設計](docs/decisions/0001-local-ios-verification.md) | Apple CLI・sim-use・Nixの役割、構成、採用理由、対応範囲 |
| [ローカル iOS 検証](docs/ios-verification.md) | Simulatorの準備、ビルド・テスト・操作・画面記録、証跡の確認 |
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
| 検証対象 | iOS 26.5のみ。`VerificationApp` scheme、deployment target `26.0` |

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

共通検査は `workflow-policy`・`nix-format`・`ios-tooling` の3つです。workflowのrunner・構文・シェル、Nix書式、iOS検証スクリプトの失敗処理を検査します。GitHub Actionsも `ubuntu-24.04` で同じlockとコマンドを使います。Apple SDKやSimulatorを使う検証は次の手順で行います。

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

### 5. Simulatorで検証する

環境と利用可能な端末を確認します。

```sh
nix develop --command python3 scripts/ios.py doctor
nix develop --command python3 scripts/ios.py devices
```

[Simulatorの作成・選択手順](docs/ios-verification.md#simulatorの作成と選択) に従って専用端末を用意し、そのUDID（端末の一意な識別子）を `NIBBLE_SIMULATOR` に設定します。テストと操作・撮影は次のコマンドで実行します。

```sh
nix develop --command python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py smoke --device "$NIBBLE_SIMULATOR"
```

結果はGit管理対象外の `artifacts/` に保存されます。画像と動画を開いて内容を確認し、生成された `REVIEW.md` に確認結果とPRの添付先を記録します。

## よく使うコマンド

| 操作 | コマンド |
| --- | --- |
| 開発シェルを起動 | `nix develop` |
| CIと同じ検証 | `nix flake check --no-update-lock-file --print-build-logs` |
| runner方針だけを検査 | `nix develop --command python3 scripts/check_workflows.py` |
| Nix定義を整形 | `nix fmt flake.nix` |
| iOS検証環境を確認 | `nix develop --command python3 scripts/ios.py doctor` |

依存の追加・更新は [開発ツールの管理](CONTRIBUTING.md#開発ツールの管理)、実装とレビューは [開発ガイド](CONTRIBUTING.md) に従います。セットアップ時にlockを更新する必要はありません。
