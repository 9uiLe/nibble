# TestFlightで内部配布する

## 実行するコマンド

ローカルMacで、commit済みのnibbleを署名し、本人の内部テスターへ配布する。初回設定を済ませ、リポジトリのルートで実行する。

```sh
scripts/deploy-testflight.sh --check-config
scripts/deploy-testflight.sh --dry-run
scripts/deploy-testflight.sh
```

| モード | 処理と完了条件 |
| --- | --- |
| `--check-config` | 設定の書式・所有者・ファイル権限・鍵ファイルの存在を確認する。鍵の内容を読まず、Appleには接続しない |
| `--dry-run` | 共通検査、依存解決、Release archive、署名したIPAの書き出し。Developer Portalへの接続・provisioning更新は許可するが、buildをアップロードしない |
| 引数なし | 同じ検査とarchiveを経て、XcodeからApp Store Connectへアップロードする |

画面には工程名と成否、完了時のversion・buildだけを表示する。認証設定の失敗時は、固定した検査工程名（ファイルの存在・所有者・権限、4項目の書式、識別子の書式、鍵の配置規則）を返す。入力値・実際のパス・例外詳細は表示しない。送信成功後、Apple側の処理完了と内部グループへの追加をApp Store Connectで確認する。実施済みの範囲は[検証記録](testflight-validation.md)を参照する。

## 秘密情報の管理

開発と配布は同じmacOSユーザーで行う。API鍵、認証設定、署名の秘密鍵、生ログをGit管理しない。認証設定とAPI鍵は`~/.appstoreconnect/`、署名の秘密鍵は本人が管理するKeychainに保持する。

AIエージェントは、認証ディレクトリ・Keychain・秘密鍵・生ログを直接参照せず、配布コマンドの結果だけを受け取る。設定値やログ全文を会話へ貼らない。初回設定と失敗時の生ログ確認は本人が行う。

これは同一ユーザー内の運用上の制限であり、OSによるアクセス分離ではない。[AGENTS.md](../AGENTS.md)でエージェントの行動を定め、Claude Codeには[deny設定](../.claude/settings.json)も適用する。この設定はCodexなど別のエージェントへ自動適用されず、同一ユーザーの任意のシェル操作を完全には遮断しない。厳密な技術的隔離が必要になった場合は、[配布設計](decisions/0003-testflight-distribution.md)を見直す。

## 1. Apple側の識別子とCapabilityを登録する

Apple DeveloperのCertificates, Identifiers & Profilesで、次の構成を登録する。識別子を変更する場合は、製品のentitlements・project・配布検査をまとめて更新する。

| 対象 | 識別子 | Capability |
| --- | --- | --- |
| 本体のExplicit App ID | `nibble.9uiLe.com` | App Groups |
| Share ExtensionのExplicit App ID | `nibble.9uiLe.com.share` | App Groups |
| 共有App Group | `group.nibble.9uiLe.com` | 本体とShare Extensionの両方へ関連付ける |

共有拡張のBundle IDは本体のBundle IDと`.`を先頭に含む必要がある。本体`nibble.9uiLe.com`に対して、拡張は`nibble.9uiLe.com.share`とする。

共有保存に必要なのは**両方のApp IDのApp Groups**。共有拡張は別のApp IDとprovisioning profileを持つ。Push Notifications・iCloud・Associated Domains・Sign in with Appleは現在の製品には不要。

App Store Connectでは本体のBundle IDでiOSアプリを1件作成する。共有拡張を別アプリとして登録しない。登録と契約への同意は本人が行う。詳細はAppleの[Capability設定](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)と[App Group登録](https://developer.apple.com/help/account/identifiers/register-an-app-group)を参照する。

## 2. Xcodeの署名を準備する

1. Xcode 26.5を選択し、[開発環境](../README.md#セットアップ)を準備する。固定したAppMacros revisionをXcodeで個別に承認する。一括でmacro検証を無効にしない。
2. 本人がXcodeのAccountsでApple Developerアカウントへサインインする。
3. 対象TeamのApple Distribution証明書と対応する秘密鍵を、本人のKeychainに用意する。本体と共有拡張の配布profileに、同じApp Groupが含まれることを確認する。
4. 署名資産が不足する場合は、本人がXcodeのOrganizer等で配布準備を完了する。DeveloperロールのAPI鍵で、配布証明書の新規発行まで自動的に成立すると想定しない。

スクリプトはTeamを実行時に指定するため、個人のTeam IDやアカウントをXcode projectへ保存する必要はない。Appleの[cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)にはロール・権限の条件がある。認証に失敗しても、エージェントがAPI鍵の権限を引き上げない。

## 3. API認証設定を本人が配置する

App Store ConnectのUsers and Access / IntegrationsでTeam API keyを作成する。アップロード用にはDeveloperロールを基本とし、必要な権限を確認する。Team API keyは対象アプリ1件だけに限定できないため、他のアプリにも及ぶ権限として管理する。詳しくはAppleの[API key作成](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)を参照する。

同じTeamの既存のTeam API keyに必要な権限があれば共用できる。`nibble.env`から既存の鍵ファイルを参照し、秘密鍵を複製しない。共用した鍵を失効・交換すると、その鍵を使う他の配布処理にも影響する。

本人が、リポジトリ外に次のファイルを配置する。ダウンロード直後の秘密鍵をエージェントに操作・表示させない。

| パス | 内容 | 権限 |
| --- | --- | --- |
| `~/.appstoreconnect/` | 認証情報のディレクトリ | 所有者は実行ユーザー、`0700` |
| `~/.appstoreconnect/AuthKey_<KEY_ID>.p8` | Appleから取得した秘密鍵 | `0600`、通常ファイル |
| `~/.appstoreconnect/nibble.env` | 下記の4項目 | `0600`、通常ファイル |

`nibble.env`の書式例。山括弧の部分は本人がローカルで実際の値に置き換える。このファイルの内容は会話へ貼らない。

```text
ASC_KEY_ID=<10文字のKEY_ID>
ASC_ISSUER_ID=<IssuerのUUID>
ASC_KEY_PATH="$HOME/.appstoreconnect/AuthKey_<KEY_ID>.p8"
ASC_TEAM_ID=<10文字のTEAM_ID>
```

設定はshellとして実行しない。4項目の代入、空行、コメントのみを受け付け、`export`・コマンド置換・任意パスを許可しない。鍵の場所では`$HOME/`・`${HOME}/`・`~/`を利用できる。symlink・hard linkは使用しない。秘密鍵の内容はXcodeが読み、配布スクリプトは読み込まない。

`--check-config`が成功しても、鍵の有効性・ロール・Appleへの接続・署名は未確認。続けて`--dry-run`でIPAまでの経路を確認する。

## 4. ビルド番号と配布結果を扱う

作業ツリーがcleanであることを要求し、対象commitを実行記録に残す。Nixの全check、iPhoneOS 26.5 SDK、共有`Package.resolved`を使い、本体と共有拡張を同じbuild番号でarchiveする。検査・依存解決・archiveの終了時にもソースが変わっていないことを確認する。同じcheckoutからの配布処理は同時実行しない。

build番号は既定でUTCの`YYYYMMDDHHmm`。明示する場合は、App Store Connectで未使用かつ現在より新しい番号を指定する。

```sh
scripts/deploy-testflight.sh --build-number 202609170900
```

同じbuild番号の実行記録がある場合は上書きしない。dry-run直後に同じ分内でアップロードする場合も、次の番号を指定する。中断やtimeoutの後は、本人がApp Store Connectで受理状況を確認してから新しい番号で実行する。送信を自動再試行しない。

| 保存先 | 内容・扱い |
| --- | --- |
| `artifacts/testflight/<build>/manifest.json` | commit、工程、完了フラグ、archiveの公開メタデータ |
| `artifacts/testflight/<build>/Nibble.xcarchive` | 実機向けarchive。Git管理外 |
| `artifacts/testflight/<build>/export/` | dry-runのIPA等。Git管理外 |
| `~/.appstoreconnect/logs/nibble-<build>-<識別子>/` | Xcode・Nixの生ログとExportOptions。ディレクトリ`0700`、ファイル`0600`。本人だけが内容を確認する |

失敗メッセージは工程名と固定の案内のみで、コマンド引数・例外詳細・ログ末尾を返さない。本人がログを調べ、秘密情報を除いた原因だけをエージェントに伝える。共有する証跡にはmanifestを使い、archive・IPA・ログをPRへ添付しない。

## 5. 本人の端末へ配布する

1. 引数なしでアップロードし、App Store ConnectのTestFlightでbuildの処理完了を確認する。アップロード成功と処理完了は別の状態。
2. 暗号化の輸出コンプライアンスについて、本人が実装に基づいて回答する。スクリプトは未確認の申告を自動設定しない。
3. 自分だけの内部テストグループを作り、初回は自動配布を無効にして対象buildを追加する。
4. iOS 26.5の自分の端末でTestFlightからインストールし、起動・作成・編集・コピー・共有拡張からの保存・本体での表示を確認する。

buildは`testFlightInternalTestingOnly`で送信する。外部テストやApp Store公開には使用せず、別の配布判断とbuildを用意する。Appleの[buildアップロード](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)、[内部テスター](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)、[輸出コンプライアンス](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)も確認する。
