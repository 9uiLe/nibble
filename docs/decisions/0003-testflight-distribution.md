# TestFlight内部配布の設計

## 目的と適用範囲

nibbleの開発者が、コミット済みのアプリをローカルMacでビルドし、自分の端末へTestFlightで継続的に配布する。Apple Developerアカウントと配布端末を管理する開発者を、この文書では「配布担当者」と呼ぶ。内部テストグループ「本人用」には配布担当者1名を登録し、各ビルドを自動配信する。

設計状態は採用、判断日は2026-09-16。最低対応OSはiOS 26.0、ビルド環境はXcode 26.5 / iPhoneOS SDK 26.5、配布の受け入れ検証はiOS 26.5実機を対象とする。構築と運用は[配布手順](../testflight.md)、実施済みの確認と未確認条件は[検証記録](../testflight-validation.md)に定義する。

## 構成と責務

開発と配布は1台のMacの同じmacOSユーザーで行う。[配布コマンド](../../scripts/deploy-testflight.sh)がNixのPythonから[配布処理](../../scripts/testflight.py)を起動し、Appleの`xcodebuild`に認証・署名・アップロードを委ねる。App Store Connectがビルドを処理し、「本人用」へ配信する。

| 担当 | 責務 |
| --- | --- |
| 配布担当者 | Appleの契約、識別子、Capability、署名資産、API鍵の管理。輸出コンプライアンスの申告内容の確認、保護されたログの確認、実機での受け入れ |
| AIエージェント | ソースと配布コードの編集・検証、レビューした配布コマンドの実行、工程の成否と公開メタデータの確認 |
| 配布スクリプト | ソースの固定、共通検査、依存解決、archiveの生成・メタデータ検査、Xcodeの呼び出し、実行記録と出力の制御 |
| Xcode | API鍵を使ったAppleへの認証、provisioning更新、署名、IPAの書き出し・送信 |
| App Store Connect | アップロードしたビルドの処理、TestFlightの内部グループへの自動配信 |
| GitHub Actions | `ubuntu-24.04`で共通検査を実行 |

ローカルのAppleツールを利用することで、署名処理とSDKの管理をMacへ集約する。補助ツールはNixのlock、Swift Packageは共有`Package.resolved`で固定する。APIのJWT生成やアップロード処理を独自実装せず、Appleが提供する認証・配布経路を使う。

## アプリの識別と共有保存

| 対象 | 識別子 | 必要な設定 |
| --- | --- | --- |
| 本体 | `nibble.9uiLe.com` | Explicit App ID、App Groups |
| Share Extension | `nibble.9uiLe.com.share` | 独立したExplicit App ID、App Groups |
| Keyboard Extension | `nibble.9uiLe.com.keyboard` | 独立したExplicit App ID、App Groups |
| 共有保存領域 | `group.nibble.9uiLe.com` | 本体・Share Extension・Keyboard Extensionへ関連付ける |

本体と各拡張は同じDeveloper Teamで署名する。拡張のBundle IDは本体のBundle IDと`.`を先頭に持つ。3 targetのprovisioning profileに同じApp Groupを含め、[製品の保存設計](0002-mvp-app.md#保存形式と接続)で定めるSQLiteへアクセスできるようにする。App Store Connectへ登録するアプリは本体1件である。

## 秘密情報と実行の境界

認証設定とAPI秘密鍵はリポジトリ外の`~/.appstoreconnect/`、署名の秘密鍵は配布担当者のKeychainで管理する。認証ファイルは所有者だけが利用できる権限とし、Gitへ保存しない。

エージェントは認証設定・秘密鍵・Keychain・生ログを直接参照しない。別のコマンドやコード変更による迂回も禁止する。許可する利用経路は、レビューした配布スクリプトによる設定確認・archive・署名・アップロードである。[AGENTS.md](../../AGENTS.md)に行動規約を定義し、Claude Codeには[読み取りと実行のdeny設定](../../.claude/settings.json)を併用する。

この境界は同一macOSユーザー内の運用規約である。同じユーザー権限のプロセスはファイルへアクセスできるため、エージェントから技術的に読み取れないことは保証しない。Claude Codeのdeny設定も他のエージェントには適用されない。配布スクリプト、ビルドスクリプト、マクロ、依存コードを信頼する実行モデルとしてレビューする。OSによる厳密なアクセス分離が必要な運用では、専用ユーザーまたは専用環境と限定された実行サービスを設計する。

### 認証設定の解釈

`nibble.env`は変数の代入を表すテキストとして解析し、shellとして実行しない。必須項目は`ASC_KEY_ID`・`ASC_ISSUER_ID`・`ASC_KEY_PATH`・`ASC_TEAM_ID`。任意の先頭`export`と追加変数を受け付けるが、追加変数は認証設定として採用せず、環境変数やXcodeの引数にも反映しない。

設定ファイルの所有者・権限・書式、必須項目、識別子の書式、鍵ファイルの配置を検査する。秘密鍵の内容はXcodeだけが読み、Pythonは検査済みのパスを渡す。子プロセスの環境はホームディレクトリ、標準PATH、言語設定、実行環境で指定された`DEVELOPER_DIR`に限定する。

API鍵はDeveloperロールを基本とし、配布に必要な証明書・秘密鍵・profileを事前に準備する。Team API keyの権限はアプリ1件に限定できない。スクリプトによる対象アプリの固定と、Apple側で与える権限は別々に管理する。

### 出力と保存

エージェントへ返す情報は工程名、成否、version・build番号、archiveの公開メタデータに限定する。認証エラーはコードで定義した検査工程名と固定メッセージで伝え、入力値・実際の認証パス・例外詳細を出力しない。

XcodeとNixの生ログ、Team IDを含むExportOptionsは認証ディレクトリ内へ保存する。配布担当者が内容を調べ、秘密情報を除いた原因だけを共有する。Git管理外の`artifacts/testflight/<build>/manifest.json`には対象コミット、工程、完了フラグ、公開メタデータを記録する。

## ビルドと送信の契約

- 未コミットの変更がないソースを使用し、対象コミットを記録する。共通検査・依存解決・archiveの各工程後にもソースの一致を確認する。
- 認証・署名ファイルのGit追跡を検出した場合は停止する。ファイル名による検査なので、リポジトリへ秘密情報を保存しない運用も必要になる。
- iPhoneOS SDK 26.5でReleaseをarchiveする。3 targetの識別子、version・build番号、最低OS、実行ファイル、Privacy Manifest、拡張とアイコンの設定、輸出コンプライアンスの申告を検査する。
- 同一checkoutの実行をロックで直列化する。build番号ごとの実行記録を上書きせず、結果不明の送信を自動再試行しない。
- `--dry-run`は署名済みIPAの書き出しまで実行する。Appleへの認証とprovisioning更新を伴うが、ビルドはアップロードしない。
- アップロードは内部テスト専用の`testFlightInternalTestingOnly`を指定する。外部テスト・App Store公開は別の配布設計とビルドを必要とする。

## 輸出コンプライアンスの申告

本体・共有拡張・キーボードの`Info.plist`に`ITSAppUsesNonExemptEncryption = false`を保存し、免除対象外の暗号化を使用しないことをビルドで申告する。nibbleの保存にはApple同梱SQLite、ファイル保護にはiOSのData Protectionを使い、製品とリンクする依存ライブラリに独自の暗号化実装を含めない。構成と申告値をGitで管理し、暗号化機能や依存の変更時に配布担当者が適合性を再確認する。

配布スクリプトは、完成したarchiveの3つのInfo.plistがBooleanの`false`を持つことをexport・upload前に検査し、公開メタデータへ記録する。検査は設定の欠落や型の誤りを検出するもので、実装から法的な分類を自動判定するものではない。詳細とAppleの仕様は[配布手順](../testflight.md#輸出コンプライアンス)を参照する。

## 配信と完了条件

「本人用」はXcodeビルドの自動配信を有効にし、配布担当者1名だけを登録する。ローカルXcodeからアップロードした各ビルドは、Apple側で利用可能になるとグループへ配信される。輸出コンプライアンスの申告はビルドに含め、追加情報を求められた場合は配布担当者が対応する。端末への自動インストールはTestFlightアプリ側の設定に従う。

| 状態 | 確認する内容 |
| --- | --- |
| 設定利用可能 | ファイルの所有者・権限・書式・鍵の配置がスクリプトの検査を通過した |
| IPA生成済み | dry-runが成功し、署名したIPAが存在する |
| アップロード成功 | Xcodeの送信コマンドが成功した |
| 配信可能 | App Store Connectで処理が完了し、「本人用」にビルドが反映され、テスト可能になった |
| インストール済み | 端末でTestFlightから対象ビルドをインストールした |
| 受け入れ完了 | iOS 26.5実機で起動・編集・コピー・共有保存を確認した |

manifestの`completed: true`は指定したexportまたはuploadの工程完了を示す。Apple側の処理、グループ配信、実機での利用成立はそれぞれ確認する。Simulatorの結果は実機での受け入れを代替しない。

## 設計を見直す条件

複数の配布担当者、外部テスター、無人・遠隔配布、秘密情報の技術的なアクセス分離を必要とする場合は、権限と実行環境を再設計する。Apple CLI/API仕様、SDK、マクロ、署名資産、鍵の変更時は、設定確認とdry-runで対応する経路を検証する。
