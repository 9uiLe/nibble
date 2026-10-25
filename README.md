# nibble

nibbleは、繰り返し使う文章を用意し、必要な場面で意図した内容を再利用するiOS 26.0以上向けアプリです。保存済み文章と途中作業を分け、空白・改行・Unicodeを原文として保持します。

## 文章を用意して使う

1. 本体で作成するか、他アプリの共有から文章・URLを取り込みます。
2. 名前と本文をOS標準の日本語入力で編集し、保存します。「閉じる」は作業を保持し、後から「作業中」で再開できます。
3. 名前・本文から探すか、ピン留めした文章を選び、使う全文を確認します。
4. 明示的にコピーし、入力先のアプリへ戻って欄を選び、OSのペーストを行います。

保存・コピー・入力先への挿入は別の処理です。コピー後に自動で貼り付けたり送信したりしません。失敗・競合では現在入力を残し、再試行や別文章への保存で続けられるようにします。不要な文章はごみ箱へ移して戻せます。作業中の入力はごみ箱移動に巻き込まず、完全消去のUIは設けていません。

## 相手や用件に合わせる

編集画面で「差し替えを使う」をオンにして本文へ`{{宛名}}`のような印を入れると、使うときに本体の標準入力で値を用意できます。既定はオフで、コード例などに含まれる`{{…}}`も文字どおりに保存・利用します。同名の印は一つの入力で差し替えます。ひな型を変えず、文字どおりの完成文全文を確認してコピーします。Markdown記号を隠す描画切替はありません。

途中の値も作業として保持し、再利用カードを保存しなくても中断・再開・コピーできます。同じ完成文を繰り返し使う場合だけ、名前を確認して別の固定文に保存できます。由来となるひな型名は保存時の記録で、元ひな型が変わっても固定文は自動で変わりません。

## 他アプリで使うキーボード

任意で追加するnibbleキーボードは、ピン留めした固定文の全文確認・挿入を担当します。更新が新しい最大50件を表示し、差し替えが有効で印の値が必要なひな型や、作業中の入力は渡しません。差し替えをオフにした文章中の`{{…}}`は固定文としてそのまま使えます。未掲載の文章の検索や、毎回変わる差し替えは本体で行い、コピーして入力先でペーストします。

追加と切替は「使い方と管理」から案内します。Full Access許可を必須にしない読取専用構成で、Keyboardには本文編集、独自かな漢字入力、コピー、ピン更新、通信を持たせません。パスワード欄や第三者キーボードを許可しないホストでは、コピーとペーストを使います。[設計とOS境界](docs/architecture/keyboard.md)を参照してください。

## 保存と提供範囲

文章と作業は端末内に保存し、アカウント・サーバー同期・独自バックアップを持ちません。OSのバックアップに含まれる可能性はありますが、nibble独自の復旧として保証しません。アプリ削除後の復旧と旧保存形式からの移行は提供しません。

課金、広告、Rive、独自IMEは製品構成に含めません。採用する仕様と実装の責務は[製品仕様・要件](docs/product-specification.md)と[アーキテクチャ](docs/architecture/README.md)、実施した検証は対象sourceと条件を持つrunで確認します。説明や画面の実装を受入完了とは扱いません。

## 開発を始めるときに読む資料

| 目的 | 入口 |
| --- | --- |
| 環境を用意して起動する | この文書のセットアップ、[製品の実行手順](docs/ios-verification.md) |
| 変更に必要な規約・検査を知る | [開発ガイド](CONTRIBUTING.md)、[テストの設計と選択](docs/testing.md)、[エージェント向け入口](AGENTS.md) |
| データ・状態・失敗回復を理解する | [製品仕様・要件](docs/product-specification.md)、[Swift規約](docs/library-policy.md) |
| 画面の状態・非同期処理・描画を変更する | [画面の状態と応答性](docs/architecture/responsiveness.md)、[性能検証](docs/performance-verification.md) |
| 変数の編集・入力・出力を理解する | [変数の編集と利用](docs/architecture/variables.md)、[操作検証](docs/ios-verification.md#変数の編集と利用を確認する) |
| 課金・広告を採用しない範囲を理解する | [収益と機能アクセス](docs/architecture/monetization.md) |
| UIや保持する制作資産を扱う | [UI設計](docs/design/README.md)、[製品と制作資産の境界](docs/architecture/presentation.md) |
| 実行・証跡・PRを確認する | [検証基盤](docs/ios-verification.md)、[証跡とPR](docs/review-evidence.md) |
| AIでSimulatorの動作・外観を確認する | [観測データの確認](docs/simulator-inspection.md)。原本を保存し、要素情報と必要な領域の画像を読む |
| 外部の制約・未確認条件を調べる | [OSの境界](docs/reference/platform.md)、[保存と検索](docs/reference/storage.md)、[保護と公開](docs/reference/security.md)、[検証範囲](docs/testing.md#検証範囲と制約) |
| サポート・プライバシーの公開ページを管理する | [Webサイトの構成と公開手順](marketing/README.md) |
| 本人向けに配布する | [TestFlight手順](docs/testflight.md) |

## アプリの構成

コードの配置と依存関係は[アーキテクチャ](docs/architecture/README.md)、資料の責務は[開発ガイド](CONTRIBUTING.md#文書の責務)を参照してください。

| 配置 | 内容 |
| --- | --- |
| `app/` | 本体、共有拡張、固定文キーボード、共有モデル・保存層、製品回帰と保持する制作資産 |
| `runtime/rive/` | 保持するRive制作・検証基盤。現製品では使用しない |
| `scripts/` | ビルド・検証・証跡・配布のCLIと回帰テスト |
| `validation/` | 実行基盤のVerificationApp、保存層の測定harness、OS連携の入力fixture |
| `tools/ui-design/` | 製品に依存しない設計照合ツール |
| `marketing/` | Firebase Hostingで配信するサポート・プライバシー・問い合わせページ |
| `docs/` | 仕様、構成、UI設計、開発・検証手順、外部仕様の参照 |
| `artifacts/` | Git管理外の実行結果・ログ・媒体 |

## セットアップ

Intel Macではtree-sitter-language-packが未対応のためNix環境全体の検査は成立しない。Linux arm64は構成評価と実行確認を区別し、CIの実行対象はUbuntu x86_64とする。

補助ツールは[flake.nix](flake.nix)に宣言し、[flake.lock](flake.lock)で固定します。ローカルとCIは同じlockを使います。Xcode・Apple Swift・SDK・Simulator runtime・署名情報はローカルMacで管理します。

| 環境 | 用途 |
| --- | --- |
| macOS（Apple Silicon） | Nix共通検査。製品ビルドにはmacOS 26以上、対応するXcodeと対象runtimeが必要 |
| Linux x86_64 | Ubuntu CIでNix共通検査。ARM64は構成評価のみで実行は未確認 |
| iOSの確認環境 | Xcode 27.0、Apple Swift 6.4、Swift language mode 6、Simulator SDK 27.0 |
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

以降はリポジトリルートで実行します。初回はlockで固定した依存を取得します。`nix develop`はGitのhook設定が未設定なら`.githooks/pre-commit`を登録し、コミット前に[共通のスタイル検査](scripts/check_swift_style.sh)を実行します。既存の`core.hooksPath`設定は維持します。開発シェルにはPython 3、PyYAML、markdown-it-py、tree-sitter-language-pack、actionlint、ShellCheck、Git、GitHub CLI、hamio、SwiftLint、SwiftFormatが入り、macOSではsim-use 0.14.0も使えます。画像加工はmacOS付属のsipsを使います。Homebrew・pipでの個別導入は不要です。開発シェルは`exit`で終了できます。

| 共通検査 | 確認する内容 |
| --- | --- |
| `workflow-policy` | runner方針、workflow構文、埋め込みシェル |
| `nix-format` | Nix定義の書式 |
| `ios-tooling` | driver、証跡、画面要素の解析、画像加工の拒否・失敗契約、CLI入出力、PR、文書、Swift規約のPython回帰テスト |
| `swift-library-policy` | 所有するSwiftソースの依存方向・禁止API・タスク開始・View比較・型とファイルによるView構成の境界 |
| `swift-style` / `swift-build-settings` | SwiftLint・SwiftFormatの規則と、Swift・Clang警告をエラーにするビルド設定 |
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

iOSを検証するMacに[Xcode](https://developer.apple.com/xcode/)をインストールし、一度起動してライセンス確認と追加コンポーネントの導入を完了します。確認環境はXcode 27.0です。Settings → Locations → Command Line Toolsで使うXcodeを選び、確認します。

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
| swift-app-macros | 0.3.0 | 本体・共有拡張・KeyboardのViewの比較境界 |
| swift-syntax | 603.0.2 | Mac上でAppMacrosのマクロを構築する間接依存 |

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

通常のセットアップでは共有lockを使用し、全マクロの検証を無効にする設定は使いません。ライセンスと依存構成の見直し条件は[実装規約](docs/library-policy.md#採用理由と更新条件)を参照してください。


### 5. 専用Simulatorで製品を実行する

[ローカルiOS検証](docs/ios-verification.md)で環境と計画の準備事項を確認します。通常の検証ではコマンドがiOS 26.5の専用Simulatorを作成し、終了時に削除します。

```sh
python3 scripts/verify.py run --base origin/main --temporary-device
python3 scripts/verify.py status --result artifacts/verify/対象ID/result.json
```

結果ファイルのパスは`run`のstdoutから取得します。`status`で成否、未開始工程、端末の削除結果を確認します。

通常回帰は`--scope regression`、製品は`--scope product`で選べます。性能測定は目的と条件、対象の工程を[性能手順](docs/performance-verification.md)で確認します。

製品の期待動作は[製品仕様・要件](docs/product-specification.md)、操作とVerificationAppの実行は[共通手順](docs/ios-verification.md)を参照します。

専用端末のUDIDを`NIBBLE_SIMULATOR`に設定した後、製品を起動できます。

```sh
python3 scripts/ios.py run --project-config app/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
```

### 6. 証跡を確認してPRへ記載する

[観測データの確認](docs/simulator-inspection.md)で操作の状態を要素情報から読み、外観は全体画像と必要な細部を開いて確認します。[証跡とPRの手順](docs/review-evidence.md)で、実行ソース・原本媒体・観測記録を照合します。文書だけの変更は[共通検査](CONTRIBUTING.md#実行と検査)とPR本文の確認を行い、撮影が不要な理由を記載します。

### Moletta

[Moletta](https://github.com/9uiLe/moletta)は、必要な能力の調査、方式の比較、実物の検証を支援するAI開発ハーネスです。重要な設計や不確かな変更に使い、明確な小変更は短い手順で進めます。nibbleの製品仕様、権限、検証手順は引き続き[エージェント向け入口](AGENTS.md)に従います。

ソースは`flake.nix`の`moletta-source`と`flake.lock`で固定し、開発シェルの`NIBBLE_MOLETTA_SOURCE`から参照します。リポジトリルートのNixシェルで、worktreeごとに次を実行します。

```sh
python3 "$NIBBLE_MOLETTA_SOURCE/scripts/install.py" "$PWD" --mode copy &&
  for skill in moletta moletta-explore moletta-compare moletta-verify moletta-learn; do
    chmod -R u+w ".agents/skills/$skill" ".claude/skills/$skill"
  done
```

Codexの`.agents/skills/`とClaude Codeの`.claude/skills/`へ、相互参照とruntimeを含む5技能をコピーします。コピー方式はソースディレクトリのsymlinkを拒否する検査に適合し、Nix storeの回収後も利用できます。生成した10ディレクトリだけをGit管理外とし、既存の技能とClaude Codeの権限設定を保持します。installerは既存項目を上書きしません。

導入後は対象プロジェクトの新しいセッションで、Codexでは`$moletta`、Claude Codeでは`/moletta`に目的と必須条件を添えて依頼します。技能の自動選択も利用できます。追加APIやモデル、常駐サーバーの設定は不要です。

構造化記録が必要な作業では、エージェントが`init`の保存先を`artifacts/moletta/<作業ID>`へ明示します。たとえば、依頼原文を保存したファイルを指定して次のように初期化します。

```sh
python3 .agents/skills/moletta/scripts/moletta.py init artifacts/moletta/task-id \
  --brief artifacts/request.md --goal '達成したい成果'
```

記録はGit管理外の作業資料として保持し、iOSの検証・証跡には既存の[nibble検証手順](docs/ios-verification.md)を使います。

更新は`nix flake update moletta-source`で行い、新しいNixシェルに入り直します。両ホストの導入済み5技能を確認して`artifacts/`へ退避した後、上のコピー導入を再実行します。Moletta以外の技能や設定は退避対象に含めません。更新後も新しいセッションから利用します。
