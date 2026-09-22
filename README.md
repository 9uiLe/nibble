# nibble

nibbleは、よく使うテキストを保存して素早く利用するiOS 26.0以上向けアプリです。端末内で動作し、アカウント・同期・独自バックアップを持ちません。保存・編集・挿入・コピーでは原文の空白・改行・Unicodeを保持します。

## 画面と基本操作

| 場所 | できること |
| --- | --- |
| 一覧 | 保存済みを使用回数順に表示し、編集・コピー・整理する。直近の下書きは別区分から再開する。すべて・ピン留め・下書きは保持した内容へ即座に切り替え、Pull to Refreshで更新する |
| 検索 | 保存済みのタイトル・本文を日本語1文字から探す。上部の検索欄をタップして入力を始める |
| 設定 | 削除一覧、キーボード案内、製品情報を開き、バージョンを確認する |
| 編集 | Markdownの見出しや太字を入力中に確認し、原文のまま保存する。任意タイトルと本文を入力する。「保存」は利用対象へ確定、「閉じる」は下書きを保持する |
| 共有拡張 | 他アプリの共有シートからテキスト・URLを取り込む |
| キーボード | 行タップで本文を挿入し、右端の「その他」から全文を読む。フルアクセスを許可するとコピー・ピン更新も使える |

一覧・検索・設定は下部の標準タブバーで切り替えます。スクロール中も縮小せず、タップとOS標準のドラッグ選択を使えます。新規作成は各ルート画面右上の＋から開きます。編集画面の×は閉じる、チェックは保存で、すべてのアイコンに読み上げ名と操作領域を設けます。

本文には`# 見出し`、`**太字**`、`*斜体*`、コードなどのMarkdownを入力できます。記号を含む原文が保存・コピーされます。「末尾にペースト」はテキストをコピーすると使えます。入力中の説明は「入力と保存について」から開けます。

一覧のフィルターとメインタブを切り替えても一覧を再読み込みしません。他アプリの共有拡張などによる更新は、一覧を下へ引いて取り込みます。アプリ内の保存や整理の結果は自動で反映します。

削除した項目は通知の「元に戻す」または設定の削除一覧から復元できます。全文、入力の保持、操作の失敗を区別して扱う契約は[製品仕様・要件](docs/product-specification.md)に定義します。

## 開発を始めるときに読む資料

| 目的 | 入口 |
| --- | --- |
| 環境を用意して起動する | この文書のセットアップ、[製品の実行手順](docs/ios-verification.md) |
| 変更に必要な規約・検査を知る | [開発ガイド](CONTRIBUTING.md)、[テストの設計と選択](docs/testing.md)、[エージェント向け入口](AGENTS.md) |
| データ・状態・失敗回復を理解する | [製品仕様・要件](docs/product-specification.md)、[Swift規約](docs/library-policy.md) |
| UIや説明イラストを変える | [UI設計](docs/design/README.md)、[Rive制作](app/Animations/README.md) |
| 実行・証跡・PRを確認する | [検証基盤](docs/ios-verification.md)、[証跡とPR](docs/review-evidence.md) |
| AIでSimulatorの動作・外観を確認する | [観測データの確認](docs/simulator-inspection.md)。原本を保存し、要素情報と必要な領域の画像を読む |
| 外部の制約・未確認条件を調べる | [参照資料](docs/reference/README.md)、[検証範囲](docs/testing.md#検証範囲と制約) |
| 本人向けに配布する | [TestFlight手順](docs/testflight.md) |

## アプリの構成

本体と共有拡張はApp GroupのSQLiteへ読み書きします。キーボードは既存DBを読み、許可されたピン更新だけを書き込みます。UIがタスクの寿命、モデルが操作と表示状態、保存層が原文と更新の整合性を所有します。画面はSwiftUI、説明イラストはRivePresentationとRMLで構成します。コードの配置と依存関係は[アーキテクチャ](docs/architecture/README.md)、資料の責務は[文書一覧](docs/README.md)を参照してください。

| 配置 | 内容 |
| --- | --- |
| `app/` | 本体、共有拡張、キーボード、共有モデル・保存層、Rive、製品回帰と性能target |
| `runtime/rive/` | Rive描画基盤のソース加工・依存解決・ビルド対象・Package定義 |
| `scripts/` | ビルド・検証・証跡・配布のCLIと回帰テスト |
| `validation/` | 実行基盤のVerificationApp、保存層の測定harness、OS連携用の入力ページ |
| `tools/ui-design/` | 製品に依存しない設計照合ツール |
| `docs/` | 仕様、構成、UI設計、開発・検証手順、外部仕様の参照 |
| `artifacts/` | Git管理外の実行結果・ログ・媒体 |

## セットアップ

Intel Macではtree-sitter-language-packが未対応のためNix環境全体の検査は成立しない。Linux arm64は構成評価と実行確認を区別し、CIの実行対象はUbuntu x86_64とする。

補助ツールは[flake.nix](flake.nix)に宣言し、[flake.lock](flake.lock)で固定します。ローカルとCIは同じlockを使います。Xcode・Apple Swift・SDK・Simulator runtime・署名情報はローカルMacで管理します。

| 環境 | 用途 |
| --- | --- |
| macOS（Apple Silicon） | Nix共通検査。製品ビルドにはmacOS 26以上、対応するXcodeと対象runtimeが必要 |
| Linux x86_64 | Ubuntu CIでNix共通検査。ARM64は構成評価のみで実行は未確認 |
| iOSの確認環境 | Xcode 26.5、Apple Swift 6.3.2、Swift language mode 6、Simulator SDK 26.5 |
| 対応OSと実行対象 | deployment target 26.0。ビルド・テスト・操作・性能の実行検証はiOS 26.5のみ |

製品の受け入れはSimulator評価に限定し、実機検証は含めません。最低対応OS 26.0への適合はdeployment targetとAPI availabilityで確認します。

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
export NIBBLE_UI_FORMAT=json
nix flake check --no-update-lock-file --print-build-logs
```

以降はリポジトリルートで実行します。初回はlockで固定した依存を取得します。開発シェルにはPython 3、PyYAML、markdown-it-py、tree-sitter-language-pack、actionlint、ShellCheck、Git、GitHub CLI、hamioが入り、macOSではsim-use 0.14.0も使えます。画像加工はmacOS付属のsipsを使います。Homebrew・pipでの個別導入は不要です。開発シェルは`exit`で終了できます。

| 共通検査 | 確認する内容 |
| --- | --- |
| `workflow-policy` | runner方針、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `ios-tooling` | driver、証跡、画面要素の解析、画像加工の拒否・失敗契約、CLI入出力、PR、文書、Swift規約のPython回帰テスト |
| `swift-library-policy` | 所有するSwiftソースのTasking・ScopedAnimation・AppMacros使用、タスク開始・View比較・型とファイルによるView構成の構文境界 |
| `documentation` | Markdownの相対リンク・見出し、Skill、Swift記載例、shell例のコマンド・設定パス、UI設計IDと照合記録 |
| `ui-design` | 製品に依存しない設計ツールの照合・設定・移設・別製品の回帰テスト |
| `rive-assets` | RML・生成物のhash、Data Bindingの名前・型・参照 |

GitHub ActionsもUbuntuで同じ共通コマンドを使います。macOS runnerは間接起動を含めて禁止し、Apple SDK・Simulatorの検証はローカルMacで行います。PRイベントでは本文と全コミットも検査し、mainは`workflow-policy`の成功をマージ条件にします。共通検査にはGitHub認証は不要です。

### 3. 変更に必要な検証を確認する

```sh
python3 scripts/verify.py plan --base origin/main
```

工程・準備事項・手動確認と、詳細を保存した`plan.json`のパスが返ります。計画だけでは検査を実行しません。文書や静的検査の変更はNix環境だけで実行できます。iOSの工程が選ばれた場合は、次のXcodeとSimulatorの準備へ進みます。実行と状態確認は[検証計画の手順](docs/ios-verification.md#変更から検証を実行する)、作業別の資料は[開発ガイド](CONTRIBUTING.md#作業の進め方)を参照してください。

### 4. XcodeとSwift Packageを準備する

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
| swift-app-macros | 0.3.0 | 本体・共有拡張・キーボード・RivePresentationのViewにMainActor上の比較を定義 |
| swift-syntax | 603.0.2 | Mac上でAppMacrosのマクロを構築する間接依存 |
| RiveRuntime | 6.27.0の固定ソースから構築 | [描画基盤](runtime/rive/README.md)がMetal描画先の取得を専用キューで実行。RivePresentation経由で本体だけに組み込む |

swift-syntaxはAppMacrosのmanifestが指定する版を使います。製品の構成と依存の対応条件は[依存とビルド](docs/library-policy.md#依存とビルド)に定義しています。ネットワーク接続のあるMacで依存を解決してください。

```sh
python3 scripts/rive_runtime.py prepare
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

`AppMacrosMacros`は、Swiftソースから等価比較を生成するビルド時のプログラムです。実行にはmacOS 26以上・Swift 6.3以上と、対象revisionへのXcodeの承認が必要です。Xcodeが未承認の診断を表示した場合は次の手順で有効にします。

1. 取得したswift-app-macros 0.3.0のソースと共有lockを読み、revisionが`9b6d5d699b44990029cdfa61cddf35cec46d1520`であることを確認します。
2. Xcodeで`app/Nibble.xcodeproj`を開き、Issue Navigatorの「Macro “AppMacrosMacros” … must be enabled」を選びます。
3. 対象パッケージの確認画面で「Trust & Enable」を選び、CLIのビルド・テストを実行します。

通常のセットアップでは共有lockを使用し、全マクロの検証を無効にする設定は使いません。ライセンスと依存構成の見直し条件は[実装規約](docs/library-policy.md#採用理由と更新条件)を参照してください。


### 5. 専用Simulatorで製品を実行する

[ローカルiOS検証](docs/ios-verification.md)で環境を確認し、iOS 26.5の専用Simulatorを選びます。計画の準備事項を満たしたら`verify.py run`で共通検査・対象テスト・UI操作を実行し、`verify.py status --result <結果ファイル>`で成否と未開始工程を確認します。

通常回帰は`--scope regression`、製品は`--scope product`、Riveの時間・メモリ測定は`--scope performance`で選べます。測定は目的と条件を決めて実行します。

製品の期待動作は[製品仕様・要件](docs/product-specification.md)、操作とVerificationAppの実行は[共通手順](docs/ios-verification.md)を参照します。

専用端末のUDIDを`NIBBLE_SIMULATOR`に設定した後、製品を起動できます。

```sh
python3 scripts/ios.py run --project-config app/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
```

### 6. 証跡を確認してPRへ記載する

[観測データの確認](docs/simulator-inspection.md)で操作の状態を要素情報から読み、外観は全体画像と必要な細部を開いて確認します。[証跡とPRの手順](docs/review-evidence.md)で、実行ソース・原本媒体・観測記録を照合します。文書だけの変更は[共通検査](CONTRIBUTING.md#実行と検査)とPR本文の確認を行い、撮影が不要な理由を記載します。

## 他アプリで使うキーボード

設定のキーボード利用案内からOS設定で追加します。入力欄のキーボード切替でnibbleを選びます。secure入力等では利用できないことがあります。[権限と操作](docs/architecture/keyboard.md)と[検証方法](docs/ios-verification.md#キーボードの操作検証)を参照してください。
