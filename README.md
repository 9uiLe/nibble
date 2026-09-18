# nibble

nibbleは、よく使うテキストをiPhoneに保存し、探してコピーするスニペットツールです。日本語UIの本体アプリと共有拡張を持ち、最低対応OSはiOS 26.0です。

利用者は、保存した本文を検索またはピン留めから選んでコピーし、入力先のアプリへ戻ってペーストします。テキストとURLは他アプリの共有シートから取り込めます。作成・編集、下書きの再開、削除・復元も本体から操作できます。

日常操作は端末内で完結し、アカウントと通信を必要としません。保存・編集・コピーでは原文の空白・改行・Unicodeを保持します。同期、独自バックアップ、キーボード拡張はMVPの提供範囲外です。

## 画面と基本操作

| 画面 | できること |
| --- | --- |
| 一覧 | 上部の「すべて／ピン留め／下書き」で対象を選び、保存済み項目を編集・コピーします。「すべて」では下書き、ピン留め済み、その他の順に表示します |
| 検索 | タイトルと本文から保存済み項目を探します。検索タブを選ぶと標準検索欄とキーボードが開きます |
| 設定 | 新規作成・コピーの左右位置を選び、削除した項目の復元と製品情報へ進みます |

新規作成は一覧・検索の下部にある＋から始めます。左右の設定は再起動後も保持します。各画面は標準ナビゲーションとLiquid Glassのタブバーを使い、リストの行と余白は共通の背景色、境界は区切り線で表します。

## 開発を始めるときに読む資料

最初に[製品設計](docs/decisions/0002-mvp-app.md)で目的・用語・責務・処理の流れを確認し、このREADMEの[セットアップ](#セットアップ)で開発環境を用意してください。実装には[開発ガイド](CONTRIBUTING.md)と[実装規約](docs/library-policy.md)を適用します。

| 知りたいこと | 資料 |
| --- | --- |
| 製品の目的、機能、構成、データ、操作の成立条件 | [製品設計](docs/decisions/0002-mvp-app.md) |
| UI要素の目的、配置理由、共通原則、画面構成、改善課題 | [UI設計](docs/design/README.md)、[設計監査](docs/design/audit.md) |
| 説明アニメーションの意図、制作、iOS表示、他製品での利用 | [演出設計](docs/decisions/0004-rive-presentation.md)、[制作手順](app/Animations/README.md)、[RivePresentation](app/Packages/RivePresentation/README.md) |
| UI設計基盤の責務、設定、実行と他製品での利用 | [共通ツールキット](tools/ui-design/README.md)、[基盤の測定記録](docs/ui-design-tooling-validation.md) |
| 開発スクリプトの処理・表示、hamioの導入と保守 | [スクリプトの契約](docs/script-tooling.md)、[導入検証](docs/hamio-validation.md) |
| 対応OS、ツール管理、検証とPRの条件 | [開発ガイド](CONTRIBUTING.md) |
| 非同期処理、タスク所有、View比較、アニメーション、Lint | [ライブラリの実装規約](docs/library-policy.md) |
| 固定したSwift Package構成の確認結果と未実施条件 | [Swift Package構成の検証](docs/spm-validation.md) |
| 日常操作と期待結果、製品のビルド・操作・撮影 | [MVPの操作と検証](docs/mvp.md) |
| 確認したソース、環境、成功・失敗、未検証条件 | [製品検証の索引](docs/mvp-validation.md)、[一覧と編集の検証結果](docs/library-validation.md) |
| 検証基盤の責務、端末選択、実行記録 | [基盤設計](docs/decisions/0001-local-ios-verification.md)、[実行手順](docs/ios-verification.md) |
| ソースと媒体の照合、PR本文とGitHubの確認 | [証跡とPRの検査](docs/review-evidence.md) |
| 基盤の確認結果と技術選定の比較資料 | [基盤の検証記録](docs/review-tooling-validation.md)、[研究資料](research/README.md) |
| TestFlightの本人向け自動配信、秘密情報の管理、セットアップ | [配布手順](docs/testflight.md)、[配布設計](docs/decisions/0003-testflight-distribution.md)、[検証記録](docs/testflight-validation.md) |
| エージェントの作業入口 | [AGENTS.md](AGENTS.md)、[共有Skill](.agents/skills/nibble-verification/SKILL.md)、[PRテンプレート](.github/pull_request_template.md) |

設計資料は現在の契約、検証記録は記載したコミットと条件に対する観測を示します。研究用アプリの構成や比較実験は製品の構成とは区別します。

## アプリの構成

本体と共有拡張の入口が保存層を作り、画面とモデルへ渡します。モデルは操作と状態、UIはタスクの開始と寿命、保存層はデータの整合性を担当します。本体と拡張はApp Group内の同じSQLiteを、別々の接続から利用します。

| 読む場所 | 責務 |
| --- | --- |
| `NibbleApp` / `SnippetStorage` / `ShareViewController` | 依存の構成、保存先の解決、本体と共有拡張の入口 |
| `LibraryView` / `LibraryScreen` | タブごとの状態、一覧の配置、編集・整理の操作を所有者へ接続 |
| `SnippetRow` / `SnippetRowContent` / `LibraryFilterBar` / `LibraryNotice` | 行の意図、値だけの表示、集合の選択、一時的な通知 |
| `LibraryTaskOwner` / `LibraryModel` | タスクの所有・重複・寿命 / 一覧状態と完了を待てる操作 |
| `SnippetEditor` / `EditorModel` / `Draft` | 入力、自動保存、保存・保持・破棄の確定と失敗回復 |
| `SnippetStore` / `SnippetSchema` / `SQLiteDatabase` | 検索・更新・競合 / 保存構造 / 接続・SQL資源の管理 |
| `LibraryEffects` / `SystemLibraryEffects` | コピーと通知の同期契約 / UIKitによる実行 |
| `LibrarySettingsView` / `AboutView` / `AboutIllustration` | 操作位置、製品情報、説明イラストの表示設定と寿命 |
| `app/Packages/RivePresentation/` / `app/Animations/` | Riveの読込・表示 / 再生成可能なRMLとアセットの契約 |
| `app/NibbleTests/` | 保存、下書き、操作完了、タスク所有、表示比較、固定表示、Rive接続の検査 |

一覧は要約を使い、再開とコピーはその時点のDBから対象1件の全文を読みます。保存・閉じる・破棄は下書きの入力番号を照合し、既存項目の保存では更新番号も確認します。失敗時は入力を残し、競合した内容は別項目として保存できます。

SwiftUI・Observationが表示状態、Taskingがタスク所有、AppMacrosがViewの比較、ScopedAnimationが表示変化の範囲を扱います。自作Viewは比較を宣言し、値表示の更新条件、親から渡される操作やBindingの反映、状態の保持期間をそれぞれ定義します。Releaseはサイズを優先して最適化し、製品容量と応答を同じ条件で評価します。契約の詳細は[製品設計](docs/decisions/0002-mvp-app.md)、Swiftの記述規則は[実装規約](docs/library-policy.md)を参照してください。

| 検証対象 | 用途 | 設定 |
| --- | --- | --- |
| `Nibble` / `NibbleShare` | 製品の本体・共有拡張 | `app/project.json` |
| `VerificationApp` | コマンド、テスト、文字列反映、撮影を確認するfixture | `validation/project.json` |
| `ResearchProbe` | 保存方式、検索、復旧、入力、OS連携の比較実験 | `validation/research-project.json` |

製品のXcode projectは`app/Nibble.xcodeproj`、shared schemeは`Nibble`です。基盤・研究用は`validation/<対象名>.xcodeproj`と同名schemeを使います。

## Riveの説明イラスト

「nibbleについて」では、ほかのアプリの文章を選んでコピーし、nibbleに保存する流れを図と動きで説明します。元の文章を残したまま複製が保存先へ移る演出を6.2秒周期で自動再生し、Reduce Motionの設定にかかわらず繰り返します。

説明文と表示設定はSwiftUI、図形と時間はRML、ファイルの読み込みと独立した再生状態の表示はSwift PackageのRivePresentationが担当します。図は説明用であり、コピーや保存を実行しません。

| 目的 | 参照先 |
| --- | --- |
| 構成、責務、採用理由を理解する | [演出設計](docs/decisions/0004-rive-presentation.md) |
| 図や動きを編集し、同梱する`.riv`を再生成する | [アセットの制作と配布](app/Animations/README.md) |
| iOSへ接続する、表示基盤を他製品で利用する | [RivePresentationの利用契約](app/Packages/RivePresentation/README.md) |
| 対象ソースの実行結果と未確認条件を調べる | [検証記録](docs/rive-validation.md) |

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
| `documentation` | Markdownの相対リンク・見出し、Skill、Swift記載例、UI設計IDと照合記録 |
| `ui-design` | 製品に依存しない設計ツールの照合・設定・移設・別製品の回帰テスト |
| `rive-assets` | RML・生成物のhash、Data Bindingの名前・型・参照 |

GitHub ActionsもUbuntuで同じ共通コマンドを使います。macOS runnerは間接起動を含めて禁止し、Apple SDK・Simulatorの検証はローカルMacで行います。PRイベントでは本文と全コミットも検査し、mainは`workflow-policy`の成功をマージ条件にします。共通検査にはGitHub認証は不要です。

### 3. XcodeとSwift Packageを準備する

iOSを検証するMacに[Xcode](https://developer.apple.com/xcode/)をインストールし、一度起動してライセンス確認と追加コンポーネントの導入を完了します。確認環境はXcode 26.5です。Settings → Locations → Command Line Toolsで使うXcodeを選び、確認します。

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
```

Xcodeの設定からiOS 26.5 Simulator runtimeを導入します。シェルごとにXcodeを選ぶ場合の`DEVELOPER_DIR`設定は[ローカルiOS検証](docs/ios-verification.md)を参照してください。

Swift Package Manager（SPM）がアプリのライブラリ依存を解決します。Xcode projectのexact versionは採用する版を指定し、共有`Package.resolved`は依存全体のバージョンとGit revisionを固定します。

| 依存 | 採用版 | 用途 |
| --- | --- | --- |
| swift-tasking | 0.3.0 | UIが開始するタスクの所有・寿命・重複管理 |
| swift-scoped-animation | 0.2.2 | アニメーションの適用範囲と伝播の制御 |
| swift-app-macros | 0.3.0 | 本体・共有拡張・RivePresentationのViewにMainActor上の比較を定義 |
| swift-syntax | 603.0.2 | Mac上でAppMacrosのマクロを構築する間接依存 |
| rive-ios | 6.27.0 | RivePresentationを通じた説明イラストの表示。本体のみ |

swift-syntaxはAppMacrosのmanifestが指定する版を使います。製品の構成と依存の対応条件は[依存とビルド](docs/library-policy.md#依存とビルド)に定義しています。ネットワーク接続のあるMacで依存を解決してください。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

`AppMacrosMacros`は、Swiftソースから等価比較を生成するビルド時のプログラムです。実行にはmacOS 26以上・Swift 6.3以上と、対象revisionへのXcodeの承認が必要です。Xcodeが未承認の診断を表示した場合は次の手順で有効にします。

1. 取得したswift-app-macros 0.3.0のソースと共有lockを読み、revisionが`9b6d5d699b44990029cdfa61cddf35cec46d1520`であることを確認します。
2. Xcodeで`app/Nibble.xcodeproj`を開き、Issue Navigatorの「Macro “AppMacrosMacros” … must be enabled」を選びます。
3. 対象パッケージの確認画面で「Trust & Enable」を選び、CLIのビルド・テストを実行します。

通常のセットアップでは共有lockを使用し、全マクロの検証を無効にする設定は使いません。ライセンスと依存構成の見直し条件は[実装規約](docs/library-policy.md#採用理由と更新条件)、この構成の実行結果は[Swift Package構成の検証](docs/spm-validation.md)を参照してください。

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
