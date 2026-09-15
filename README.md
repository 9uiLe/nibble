# nibble

nibbleは、よく使うテキストを保存し、必要なときに探してコピーするiPhone向けのスニペットツールです。最低対応OSはiOS 26.0。使いやすさ、シンプルさ、描画と応答の速さを設計の判断基準にします。

日本語UIの本体と共有拡張で、作成・編集、日本語1文字からの検索、ピン留め、コピー、削除・復元、下書きの保存・再開を提供します。他アプリの共有シートからテキスト・URLを取り込み、Appleの「ショートカット」の標準URLアクションから一覧・作成画面を開けます。

保存は端末内で完結し、アカウントと通信を必要としません。入力先のアプリへの復帰とペーストは利用者が行います。同期、独自バックアップ、キーボード拡張はMVPの提供範囲外です。

## 開発を始めるときに読む資料

[製品設計](docs/decisions/0002-mvp-app.md)で機能・画面・用語・責務を確認し、このREADMEのセットアップで開発環境を用意してください。実装時は[実装規約](docs/library-policy.md)、動作確認時は[操作と検証手順](docs/mvp.md)を使います。[検証結果](docs/mvp-validation.md)には確認した契約・ソース・条件と未検証の範囲を記録します。

| 資料 | 内容 |
| --- | --- |
| [開発ガイド](CONTRIBUTING.md) | 対応OS、Nix、ローカルとCIの責務、UI/UX・性能、PRの受け入れ条件 |
| [製品設計](docs/decisions/0002-mvp-app.md) | 提供範囲、画面、ドメインの用語、保存・検索、非同期操作、採用理由 |
| [ライブラリの実装規約](docs/library-policy.md) | 操作の完了契約、Taskingの開始・所有、ScopedAnimationの範囲、AppMacrosのView比較、Lintと依存管理 |
| [MVPの操作と検証](docs/mvp.md) | 日常操作、ショートカット設定、製品のビルド・操作・撮影手順 |
| [製品の検証結果](docs/mvp-validation.md) | コミット・端末・OSごとのテスト、画面証跡、測定、未検証条件 |
| [検証基盤の設計](docs/decisions/0001-local-ios-verification.md)・[実行手順](docs/ios-verification.md) | Apple CLI・sim-use・Nixの役割、Simulator、ログと画像・動画の記録 |
| [研究資料](research/README.md) | 一次資料と比較実験。製品で採用する構成は製品設計を参照 |
| [AGENTS.md](AGENTS.md)・[PRテンプレート](.github/pull_request_template.md) | エージェント向けの規約、レビューに必要な記載欄 |

## アプリの構成

SwiftUI・Observationで画面を構成します。操作の完了、タスクの所有、表示の更新を次のように分担します。

| 責務 | 構成 |
| --- | --- |
| 入力・処理・表示状態 | MainActorのモデルが`async`操作APIを提供し、受理した処理と結果反映を完了まで待ちます |
| タスクの開始・寿命・重複 | UI所有者がswift-taskingで管理します。下書き保存と通知期限はSwiftUI `.task`から直接awaitします |
| 一覧行の表示 | swift-app-macrosの`@Equatable`と`EquatableBodyView`でタイトル・本文プレビュー・ピン状態を比較します。状態と操作は呼出元のViewに保持します |
| アニメーション | swift-scoped-animationで通知の表示変化と入力への伝播を制御します |
| 永続化 | 本体と共有拡張がApp GroupのSQLiteを共有し、各プロセスのactorが接続とトランザクションを管理します |

原文と検索キー、保存済み項目と下書きを分けます。保存済み項目の更新番号で編集競合を検出し、下書きの入力番号で遅れた書込を判定します。用語と処理順序は[データと永続化の設計](docs/decisions/0002-mvp-app.md#データの意味と永続化)に定義しています。

Lintは、モデル内部の隠れたタスク開始、生のTask・別scheduler、直接アニメーション、直接の比較ゲート・手書き比較・比較除外を禁止します。完了契約と表示反映はSwiftの製品テストで検査します。

| 対象 | 役割 | 設定・手順 |
| --- | --- | --- |
| `Nibble` / `NibbleShare` | 製品の本体・共有拡張 | `app/project.json`、[MVP手順](docs/mvp.md) |
| `VerificationApp` | コマンド・テスト・文字列反映・撮影の成立を確認するfixture | `validation/project.json`、[共通手順](docs/ios-verification.md) |
| `ResearchProbe` | 保存3方式、検索、復旧、入力、コピー、OS連携の比較用アプリ | `validation/research-project.json`、[研究用の構成と手順](validation/RESEARCH.md) |

製品のXcode projectは`app/Nibble.xcodeproj`、shared schemeは`Nibble`です。基盤・研究用は`validation/<対象名>.xcodeproj`と同名のschemeを使います。比較用アプリの画面や保存構成は実験条件として扱います。

## セットアップ

補助ツールは[flake.nix](flake.nix)に宣言し、[flake.lock](flake.lock)で固定します。ローカルとCIは同じlockを使います。Xcode・Apple Swift・SDK・Simulator runtime・署名情報はローカルMacで管理します。

| 環境 | 用途 |
| --- | --- |
| macOS（Apple Silicon / Intel） | Nix共通検査。製品ビルドにはmacOS 26以上、対応するXcodeと対象runtimeが必要 |
| Linux（ARM64 / x86_64） | Nix共通検査。GitHub Actionsは`ubuntu-24.04`のみ |
| iOSの確認環境 | Xcode 26.5、Apple Swift 6.3.2、Swift language mode 6、Simulator SDK 26.5 |
| 対応OSと実行対象 | deployment target 26.0。ビルド・テスト・操作・性能の実行検証はiOS 26.5のみ |
| 研究用driver | Apple Silicon Mac。SDK型検査とSQLite workerはarm64を指定 |

MVPの受け入れはSimulator評価に限定し、実機検証は含めません。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認します。

### 1. GitとNixを準備する

Gitと[Nix](https://nixos.org/download/)をインストールし、ターミナルを開き直して確認します。

```sh
git --version
nix --version
```

Nixの`nix-command` / `flakes`が無効な場合は、`~/.config/nix/nix.conf`へ次を設定します。既に`experimental-features`の値がある場合は残して統合してください。

```conf
experimental-features = nix-command flakes
```

### 2. リポジトリと補助ツールを用意する

```sh
git clone https://github.com/9uiLe/nibble.git
cd nibble
nix develop
nix flake check --no-update-lock-file --print-build-logs
```

以降はリポジトリルートで実行します。初回はlockで固定した依存を取得します。開発シェルにはPython 3、PyYAML、tree-sitter-language-pack、actionlint、ShellCheckが入り、macOSではsim-use 0.14.0も使えます。Homebrew・pipでの個別導入は不要です。開発シェルは`exit`で終了できます。

| 共通検査 | 確認する内容 |
| --- | --- |
| `workflow-policy` | runner方針、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `ios-tooling` | 端末選択、失敗処理、テスト判定、録画終了処理、Swift規約の回帰テスト |
| `swift-library-policy` | 所有するSwiftソースのTasking・ScopedAnimation・AppMacros使用、タスク開始・View比較の構文境界 |

GitHub ActionsもUbuntuで同じ共通コマンドを使います。macOS runnerは間接起動を含めて禁止し、Apple SDK・Simulatorの検証はローカルMacで行います。

### 3. XcodeとSwift Packageを準備する

iOSを検証するMacに[Xcode](https://developer.apple.com/xcode/)をインストールし、一度起動してライセンス確認と追加コンポーネントの導入を完了します。確認環境はXcode 26.5です。Settings → Locations → Command Line Toolsで使うXcodeを選び、確認します。

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
```

Xcodeの設定からiOS 26.5 Simulator runtimeを導入します。シェルごとにXcodeを選ぶ場合の`DEVELOPER_DIR`設定は[ローカルiOS検証](docs/ios-verification.md)を参照してください。

アプリはswift-tasking 0.3.0、swift-scoped-animation 0.2.1、swift-app-macros 0.2.0をexact versionと共有`Package.resolved`で固定します。AppMacrosのビルド依存swift-syntax 603.0.2も同じlockで管理します。ネットワーク接続のあるMacで依存を解決します。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

AppMacrosのマクロはビルド時にMac上で実行されるため、macOS 26以上とSwift 6.3以上を必要とします。初回は次の手順で対象パッケージの実行を有効にします。

1. swift-app-macros 0.2.0のソースと共有lockを確認し、固定revisionを[依存表](docs/library-policy.md#依存とビルド)と照合します。
2. Xcodeで`app/Nibble.xcodeproj`を開きます。ビルド時にマクロが未承認の診断が出た場合は、Issue Navigatorの「Macro “AppMacrosMacros” … must be enabled」を選びます。
3. 対象パッケージの確認画面で「Trust & Enable」を選び、CLIのビルド・テストへ進みます。全マクロの検証を無効にする設定は使いません。

ライセンスと更新条件は[依存とビルド](docs/library-policy.md#依存とビルド)を参照してください。通常のセットアップでlockを更新する必要はありません。

### 4. 専用Simulatorで製品を実行する

```sh
nix develop --command python3 scripts/ios.py doctor
nix develop --command python3 scripts/ios.py devices
```

[Simulatorの作成・選択手順](docs/ios-verification.md#simulatorの作成と選択)に従い、iOS 26.5の専用端末を用意します。そのUDID（端末の一意な識別子）を明示して製品をテスト・起動します。本体と共有拡張のApp GroupにはXcodeのad hoc署名を使用し、Developer Team・証明書は不要です。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py run \
  --project-config app/project.json --configuration Release --device "$NIBBLE_SIMULATOR"
```

基本操作と撮影を自動確認するには製品用driverを使います。共有・ペースト・日本語入力の手順は[MVP手順](docs/mvp.md)を参照してください。

```sh
nix develop --command python3 scripts/check-mvp-ui.py --device "$NIBBLE_SIMULATOR"
```

画面の読取・操作はNixのsim-use、ビルド・テスト・実行管理・撮影はApple CLIを使用します。同じSimulatorへの操作は直列に行います。結果はGit管理対象外の`artifacts/`へ保存し、画像・動画を開いて確認します。生成された`REVIEW.md`に確認範囲とPRの添付先を記録してください。

## 基盤・研究用アプリを検証する

VerificationAppのテストと撮影を確認する場合は標準設定を使います。`smoke`はこのfixture専用です。

```sh
nix develop --command python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py smoke --device "$NIBBLE_SIMULATOR"
```

保存・検索などの比較にはResearchProbeの設定と専用driverを使います。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config validation/research-project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 validation/check-research-ui.py --device "$NIBBLE_SIMULATOR"
```

## よく使うコマンド

| 操作 | コマンド |
| --- | --- |
| 開発シェル | `nix develop` |
| CIと同じ検査 | `nix flake check --no-update-lock-file --print-build-logs` |
| runner方針の検査 | `nix develop --command python3 scripts/check_workflows.py` |
| Swift規約の検査 | `nix develop --command python3 scripts/check_swift_policy.py` |
| Nix定義の整形 | `nix fmt flake.nix` |
| iOS検証環境の確認 | `nix develop --command python3 scripts/ios.py doctor` |

依存の追加・更新は[開発ツールの管理](CONTRIBUTING.md#開発ツールの管理)、実装・証跡・PRは[開発ガイド](CONTRIBUTING.md)に従います。
