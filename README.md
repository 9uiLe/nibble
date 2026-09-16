# nibble

nibbleは、よく使うテキストをiPhoneに保存し、探してコピーするスニペットツールです。日本語UIの本体アプリと共有拡張を持ち、最低対応OSはiOS 26.0です。

利用者は、保存した本文を検索またはピン留めから選んでコピーし、入力先のアプリへ戻ってペーストします。テキストとURLは他アプリの共有シートから取り込めます。作成・編集、下書きの再開、削除・復元も本体から操作できます。

日常操作は端末内で完結し、アカウントと通信を必要としません。保存・編集・コピーでは原文の空白・改行・Unicodeを保持します。同期、独自バックアップ、キーボード拡張はMVPの提供範囲外です。

## 開発を始めるときに読む資料

最初に[製品設計](docs/decisions/0002-mvp-app.md)で目的・用語・責務・処理の流れを確認し、このREADMEの[セットアップ](#セットアップ)で開発環境を用意してください。実装には[開発ガイド](CONTRIBUTING.md)と[実装規約](docs/library-policy.md)を適用します。

| 知りたいこと | 資料 |
| --- | --- |
| 製品の目的、機能、構成、データ、操作の成立条件 | [製品設計](docs/decisions/0002-mvp-app.md) |
| 対応OS、ツール管理、検証とPRの条件 | [開発ガイド](CONTRIBUTING.md) |
| 非同期処理、タスク所有、View比較、アニメーション、Lint | [ライブラリの実装規約](docs/library-policy.md) |
| 日常操作と期待結果、製品のビルド・操作・撮影 | [MVPの操作と検証](docs/mvp.md) |
| 確認したソース、環境、成功・失敗、未検証条件 | [製品検証の索引](docs/mvp-validation.md)、[一覧と編集の検証結果](docs/library-validation.md) |
| 検証基盤の責務、端末選択、実行記録 | [基盤設計](docs/decisions/0001-local-ios-verification.md)、[実行手順](docs/ios-verification.md) |
| ソースと媒体の照合、PR本文とGitHubの確認 | [証跡とPRの検査](docs/review-evidence.md) |
| 基盤の確認結果と技術選定の比較資料 | [基盤の検証記録](docs/review-tooling-validation.md)、[研究資料](research/README.md) |
| エージェントの作業入口 | [AGENTS.md](AGENTS.md)、[共有Skill](.agents/skills/nibble-verification/SKILL.md)、[PRテンプレート](.github/pull_request_template.md) |

設計資料は現在の契約、検証記録は記載したコミットと条件に対する観測を示します。研究用アプリの構成や比較実験は製品の構成とは区別します。

## アプリの構成

画面、操作を実行するモデル、データを保存するactorで責務を分けます。本体と共有拡張は共通の編集画面・保存層を使い、App GroupのSQLiteにアクセスします。

| 配置・構成要素 | 責務 |
| --- | --- |
| `app/Nibble/LibraryView.swift` | 検索、一覧、通知、編集画面への入口 |
| `LibraryModel` / `LibraryTaskOwner` | 一覧の状態と待機可能な操作、操作タスクの開始・寿命・重複方針 |
| `app/Shared/SnippetEditor.swift` / `EditorModel` | 入力、自動保存、保存・閉じる・破棄の状態遷移 |
| `Draft` / `LibraryRequest` / `LibraryPage` | 編集中の値、一覧の取得条件、同じDB読取時点の一覧結果 |
| `app/Shared/SnippetStore.swift` | SQLite接続、検索、トランザクション、更新順序と競合の検査 |
| `app/NibbleShare/ShareViewController.swift` | 共有テキスト・URLの取得と、共通編集画面の表示 |
| `app/NibbleTests/` | 保存、下書き、操作完了、タスク所有、表示比較のテスト |

一覧は保存済み項目と下書きの要約を使います。下書きの再開と本文のコピーは、その時点のDBから対象1件を読みます。保存・閉じる・破棄は下書きの入力番号を照合し、既存項目の保存では更新番号も確認します。失敗時は入力を残し、競合した内容は別項目として保存できます。

SwiftUI・Observationが表示状態を扱い、swift-taskingがUI側のタスクを所有します。一覧行の表示値の比較にはswift-app-macros、アニメーションの適用範囲にはswift-scoped-animationを使います。操作APIの完了は直接awaitしてテストし、開始・比較・アニメーションの構文はLintで検査します。

| 検証対象 | 用途 | 設定 |
| --- | --- | --- |
| `Nibble` / `NibbleShare` | 製品の本体・共有拡張 | `app/project.json` |
| `VerificationApp` | コマンド、テスト、文字列反映、撮影の成立を確認するfixture | `validation/project.json` |
| `ResearchProbe` | 保存方式、検索、復旧、入力、コピー、OS連携の比較実験 | `validation/research-project.json` |

製品のXcode projectは`app/Nibble.xcodeproj`、shared schemeは`Nibble`です。基盤・研究用は`validation/<対象名>.xcodeproj`と同名schemeを使います。

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

以降はリポジトリルートで実行します。初回はlockで固定した依存を取得します。開発シェルにはPython 3、PyYAML、markdown-it-py、tree-sitter-language-pack、actionlint、ShellCheck、Git、GitHub CLIが入り、macOSではsim-use 0.14.0も使えます。Homebrew・pipでの個別導入は不要です。開発シェルは`exit`で終了できます。

| 共通検査 | 確認する内容 |
| --- | --- |
| `workflow-policy` | runner方針、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `ios-tooling` | driver、証跡、PR、文書、Swift規約のPython回帰テスト |
| `swift-library-policy` | 所有するSwiftソースのTasking・ScopedAnimation・AppMacros使用、タスク開始・View比較の構文境界 |
| `documentation` | Markdownの相対リンク・見出し、Skillのメタデータ、実装規約のSwift記載例 |

GitHub ActionsもUbuntuで同じ共通コマンドを使います。macOS runnerは間接起動を含めて禁止し、Apple SDK・Simulatorの検証はローカルMacで行います。PRイベントでは本文と全コミットも検査し、mainは`workflow-policy`の成功をマージ条件にします。共通検査にはGitHub認証は不要です。

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

画面の読取・操作はNixのsim-use、ビルド・テスト・実行管理・撮影はApple CLIを使用します。同じSimulatorへの操作は直列に行い、実行中は検証対象のソースを編集しません。結果はGit管理対象外の`artifacts/`へ保存します。

### 5. 証跡を確認してPRへ記載する

[証跡とPRの検査](docs/review-evidence.md)に従い、実行記録を対象コミットと照合します。画像・動画を開いて確認し、観測と確認範囲、添付URL、ブラウザーでの閲覧結果を`review.json`へ記録します。検査後に生成する`REVIEW.md`を共有用の記録として使います。

PR本文はテンプレートの全欄を埋め、実際の全コミット表と照合します。GitHubを使う場合は`nix develop --command gh auth status`で認証状態を確認してください。PR公開後は本文・現在head・CIの結果も照合します。ソースと媒体の整合性、画面の確認、アップロードと閲覧を、それぞれ独立して確認します。

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
| 文書の検査 | `nix develop --command python3 scripts/check_docs.py` |
| PRのコミット表生成 | `nix develop --command python3 scripts/check_pr.py commits --base origin/main` |
| Nix定義の整形 | `nix fmt flake.nix` |
| iOS検証環境の確認 | `nix develop --command python3 scripts/ios.py doctor` |

依存の追加・更新は[開発ツールの管理](CONTRIBUTING.md#開発ツールの管理)、実装・証跡・PRは[開発ガイド](CONTRIBUTING.md)に従います。
