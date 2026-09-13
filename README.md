# nibble

nibble は、さまざまな作業シーンから素早く呼び出せる iOS 向けスニペットツールです。
スニペットの作成・編集・削除を少ない操作で行え、日々の作業を妨げないことを目指します。

- **対応 OS：iOS 26.0 以上**
- **優先する価値：使いやすさ、シンプルさ、描画と応答の速さ**
- **開発方針：モダンな技術を検討し、保守・運用を含めた長期的な適性で判断する**

現在は開発ルール、設計の調査資料、ローカルの iOS 検証基盤を用意しています。検証用の Xcode プロジェクトはありますが、アプリ本体と技術スタックの最終決定はまだありません。

## セットアップ

補助ツールは Nix で構築し、`flake.lock` で固定します。Python や検査ツールを Homebrew・pip で個別に導入する必要はありません。

### 1. Git と Nix を用意する

macOS または Linux の環境で、Git と [Nix](https://nixos.org/download/) をインストールしてください。Nix のインストール後はターミナルを開き直し、次のコマンドで利用できることを確認します。

```sh
git --version
nix --version
```

Nix の `nix-command` / `flakes` を有効にします。まだ有効でない場合は `~/.config/nix/nix.conf` を作成または編集し、次の設定を追加してください。既存の `experimental-features` 設定がある場合は、既存の機能を残して値を統合します。

```conf
experimental-features = nix-command flakes
```

補助ツールは Apple Silicon / Intel の macOS と、ARM64 / x86_64 の Linux に対応しています。iOS アプリの開発・動作確認には Mac と Xcode が必要です。

### 2. リポジトリを取得する

```sh
git clone https://github.com/9uiLe/nibble.git
cd nibble
```

以降のコマンドは、リポジトリルートで実行します。

### 3. 開発環境を起動する

```sh
nix develop
```

初回は lock に固定された依存を取得します。開発シェルでは Python 3・PyYAML・actionlint・ShellCheck が利用でき、macOS では `sim-use` 0.14.0 も利用できます。シェルを終了するときは `exit` を実行してください。

### 4. セットアップを検証する

```sh
nix flake check --no-update-lock-file --print-build-logs
```

このコマンドは開発シェルの内外から実行できます。`workflow-policy`・`nix-format`・`ios-tooling` が成功すれば、補助ツールのセットアップは完了です。runner 方針、workflow の構文・シェル、Nix 定義の書式と、iOS 検証 driver の失敗処理を検査します。Apple SDK や Simulator は起動しません。

GitHub Actions も `ubuntu-24.04` 上で同じ lock とコマンドを使います。macOS runner は使用しません。

### 5. iOS 開発用の Xcode を準備する

iOS 開発を行う Mac では、[Xcode](https://developer.apple.com/xcode/) の正式版をインストールして一度起動し、初期設定と追加コンポーネントの導入を完了してください。iOS 26.0 以降の SDK を含む Xcode が必要です。プロジェクトで採用する Xcode・Swift の具体的なバージョンは、アプリ作成時に決定します。

Xcode の Settings → Locations → Command Line Tools で使用する Xcode を選択し、次のコマンドで選択先と SDK を確認します。

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
```

アプリの検証に向けて、iOS 26.0 と検証対象の最新正式版を実行できる Simulator または実機を用意します。必要な Simulator runtime は Xcode の設定から追加してください。Xcode・Apple の Swift ツールチェーン・iOS SDK・Simulator・署名情報はローカル Mac 側で管理します。

続いて [ローカル iOS 検証](docs/ios-verification.md) に従い、環境確認、専用 Simulator の作成、検証用アプリのビルド・テスト・動作確認を行います。現在の検証環境は Xcode 26.5、Swift language mode 6、scheme `VerificationApp`、deployment target 26.0 です。

```sh
nix develop --command python3 scripts/ios.py doctor
nix develop --command python3 scripts/ios.py devices
```

対象の UDID を `NIBBLE_SIMULATOR` に設定したら、次のコマンドでテストと操作・画面記録を実行できます。作成手順と成果物の確認方法は上記ガイドに記載しています。

```sh
nix develop --command python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py smoke --device "$NIBBLE_SIMULATOR"
```

## よく使うコマンド

| 操作 | コマンド |
| --- | --- |
| 開発シェルを起動 | `nix develop` |
| CI と同じ検証 | `nix flake check --no-update-lock-file --print-build-logs` |
| runner 方針だけを検査 | `nix develop --command python3 scripts/check_workflows.py` |
| Nix 定義を整形 | `nix fmt flake.nix` |

依存を更新する場合は [開発ツールの管理](CONTRIBUTING.md#開発ツールの管理) に従ってください。セットアップ時に lock を更新する必要はありません。

## 開発ルール

開発・レビュー時は [開発ガイド](CONTRIBUTING.md) を参照してください。iOS のビルド・テスト・画面・性能の検証はローカルで行い、結果と必要な画像・動画を PR に記録します。

AI エージェント向けの入口は [AGENTS.md](AGENTS.md)、PR の記載形式は [PR テンプレート](.github/pull_request_template.md) にあります。

## 設計のための調査資料

呼び出し導線、データ保存・共有、UI/UX・性能、セキュリティ・配布に関する論文・一次資料の調査は [research](research/README.md) にまとめています。技術選定の前に、確認した仕様と実機検証が必要な点を参照してください。
