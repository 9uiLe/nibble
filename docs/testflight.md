# TestFlightで本人へ配布する

## 配布の流れ

コミット済みのnibbleをローカルMacでビルド・署名し、App Store Connectへ送信する。内部テストグループ「本人用」には、Apple Developerアカウントと配布端末を管理する開発者1名を登録する。この開発者を「配布担当者」と呼ぶ。アップロードした各ビルドは、Apple側で利用可能になると「本人用」へ自動配信される。

配布スクリプトは各工程の成否を実行記録（manifest）へ保存し、公開可能な工程名と結果を[共通表示Adapter](script-tooling.md)でstderrへ出力する。AIからの実行では`NIBBLE_UI_FORMAT=json`を指定する。表示を受け取れなかった場合も、manifestの完了状態とApple側の送信状況を確認してから次の操作を決める。

エージェントは署名・アップロードの成功と公開manifestを確認し、version・build番号を報告する。Apple側の処理完了と「本人用」への配信状態は配布担当者が確認する。通常の配布依頼ではエージェントによるブラウザー確認を行わず、そのためのサインインも依頼しない。送信結果が不明な場合のApple側の確認も配布担当者が行う。

[配布設計](architecture/distribution.md)が構成と責務を定義する。以下の初回設定を済ませ、リポジトリのルートでコマンドを実行する。

## 秘密情報の取り扱い

開発と配布は同じmacOSユーザーで行う。認証設定とAPI秘密鍵は`~/.appstoreconnect/`、署名の秘密鍵は配布担当者のKeychainで管理する。認証設定・秘密鍵・生ログはGitに保存せず、会話へ貼らない。

AIエージェントはこれらを直接参照せず、レビューした配布コマンドが返す工程・成否・公開メタデータだけを確認する。設定ファイルの作成・変更と生ログの確認は配布担当者が行う。これは同一ユーザー内の運用規約であり、OSによるアクセス分離ではない。適用する行動規約と技術的な限界は[秘密情報と実行の境界](architecture/distribution.md#秘密情報と実行の境界)を参照する。

## 初回設定

### 1. Appleの識別子とApp Groups

Apple DeveloperのCertificates, Identifiers & Profilesで次の構成を登録する。App Groupsは本体・共有拡張・キーボードが同じ保存領域を使うためのCapabilityである。

| 対象 | 識別子 | 設定 |
| --- | --- | --- |
| 本体のExplicit App ID | `nibble.9uiLe.com` | App Groupsを有効化 |
| 共有拡張のExplicit App ID | `nibble.9uiLe.com.share` | App Groupsを有効化 |
| キーボードのExplicit App ID | `nibble.9uiLe.com.keyboard` | App Groupsを有効化 |
| 共有App Group | `group.nibble.9uiLe.com` | 3つのApp IDへ関連付ける |

本体と各拡張は独立したApp IDとprovisioning profileを持ち、すべてのprofileに同じApp Groupを含める。拡張のBundle IDは、本体のBundle IDと`.`を先頭に持つ。製品が必要とするCapabilityはApp Groupsである。

App Store Connectでは本体のBundle IDでiOSアプリを1件作成する。共有拡張とキーボードは本体に含めて配布する。

キーボードの追加とフルアクセスは端末の利用者が設定する。Appleへの登録と契約への同意は配布担当者が行う。詳細はAppleの[Capability設定](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)と[App Group登録](https://developer.apple.com/help/account/identifiers/register-an-app-group)を参照する。

### 2. Xcodeと署名資産

1. [開発環境のセットアップ](../README.md#セットアップ)に従い、NixとXcode 26.5 / iPhoneOS SDK 26.5を準備する。
2. 固定したAppMacros revisionをXcodeで個別に承認する。マクロ検証を一括で無効にしない。
3. 配布担当者がXcodeのAccountsでApple Developerアカウントへサインインする。
4. 対象TeamのApple Distribution証明書と秘密鍵をKeychainに用意する。本体・共有拡張・キーボードの配布profileとApp Groupの対応を確認する。
5. 署名資産が不足する場合は、配布担当者がXcodeのOrganizer等で準備する。

Team IDは配布スクリプトが実行時に指定する。個人のTeam IDやアカウントをXcode projectへ保存しない。DeveloperロールのAPI鍵だけで配布証明書の新規発行まで成立するとは限らない。Appleの[cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)の権限条件を確認し、エージェントが鍵の権限を自動昇格しない。

### 3. API認証設定

App Store ConnectのUsers and Access / IntegrationsでTeam API keyを準備する。Developerロールを基本とし、アップロードに必要な権限を確認する。Team API keyはアプリ1件だけに限定できない。同じTeamの鍵を他の配布処理と共用する場合、その鍵の失効・交換はすべての利用先へ影響する。詳細はAppleの[API key作成](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)を参照する。

配布担当者が次のファイルを配置する。所有者は配布コマンドを実行するmacOSユーザーとし、symlink・hard linkを使わない。既存の鍵を共用する場合は、そのファイルを参照する。

| パス | 内容 | 権限 |
| --- | --- | --- |
| `~/.appstoreconnect/` | 認証ディレクトリ | `0700` |
| `~/.appstoreconnect/AuthKey_<KEY_ID>.p8` | Appleから取得したAPI秘密鍵 | `0600`、通常ファイル |
| `~/.appstoreconnect/nibble.env` | 必須4項目を含む認証設定 | `0600`、通常ファイル |

`nibble.env`の書式は以下のとおり。山括弧は配布担当者がローカルで実値へ置き換える。

```text
ASC_KEY_ID=<10文字のKEY_ID>
ASC_ISSUER_ID=<IssuerのUUID>
ASC_KEY_PATH="$HOME/.appstoreconnect/AuthKey_<KEY_ID>.p8"
ASC_TEAM_ID=<10文字のTEAM_ID>
```

設定はshellとして実行しない。変数の代入、任意の先頭`export`、空行、コメントを受け付ける。追加変数も記述できるが、配布処理が使うのは必須4項目だけである。追加変数を環境変数やXcodeの引数へ反映しない。

変数名の重複、必須項目の不足、不正な識別子、コマンド置換、指定外の鍵パスはエラーになる。鍵パスの先頭には`$HOME/`・`${HOME}/`・`~/`を使える。Pythonは秘密鍵の内容を開かず、Xcodeへパスを渡す。

### 4. 内部グループ「本人用」

App Store ConnectのTestFlightで内部グループ「本人用」を作成し、作成時に「自動配信を有効にする」を選ぶ。配布担当者のアカウント1件だけを追加する。設定画面の「Xcodeビルドを自動配信」と、テスター1人を確認する。

配信設定はグループ作成後に変更できないため、作成時に確定する。自動配信の対象はローカルXcodeからアップロードするビルドである。Xcode Cloudのビルドは手動追加が必要になる。詳細はAppleの[内部テスターの設定](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)を参照する。

### 5. 設定と署名を確認する

```sh
scripts/deploy-testflight.sh --check-config
scripts/deploy-testflight.sh --dry-run
```

| モード | 確認する範囲 |
| --- | --- |
| `--check-config` | 設定の書式・所有者・ファイル権限・鍵の配置。鍵の内容を読まず、Appleには接続しない |
| `--dry-run` | 共通検査、依存解決、Release archive、署名したIPAの生成。Appleへの認証とprovisioning更新を伴う |

`--check-config`は鍵の有効性や署名を検証しない。`--dry-run`はIPAを生成するが、App Store Connectへビルドを送信しない。

## 輸出コンプライアンス

本体と両拡張の`Info.plist`へ保存した`ITSAppUsesNonExemptEncryption`の申告を、完成したarchiveで検査してから送信する。申告の理由と依存変更時の再確認は[配布設計](architecture/distribution.md)に従う。エージェントやスクリプトは申告を推測して書き換えない。

## 毎回の配布

1. 配布する変更と共有SPM lockをコミットし、作業ツリーに未コミットの変更がない状態にする。
2. 次のコマンドを実行する。

   ```sh
   scripts/deploy-testflight.sh
   ```

3. App Store ConnectのTestFlightで対象buildの処理完了を確認する。ビルドに含めた輸出コンプライアンスの申告が受理されたことを確認する。追加情報を求められた場合は配布担当者が対応する。
4. 「本人用」に対象buildが自動反映され、テスト可能になったことを確認する。
5. 自分の端末のTestFlightからインストールする。端末への自動インストールはTestFlightアプリ側の設定に従う。

コマンドはNixの全check、固定したSwift Packageの解決、Release archive、メタデータ検査、署名・送信を順に実行する。輸出コンプライアンスは、製品のInfo.plistに保存した申告をXcode経由で送信する。Appleの[buildアップロード](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)と[輸出コンプライアンス](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)も参照する。

### ビルド番号

既定値は実行時点のUTC日時`YYYYMMDDHHmm`。本体・共有拡張・キーボードに同じ番号を設定する。番号を明示する場合は、App Store Connectで未使用かつ配布済みビルドより新しい値を指定する。

```sh
scripts/deploy-testflight.sh --build-number 202609170900
```

スクリプトはApp Store Connectの既存番号を照会しない。同じ番号のローカル実行記録がある場合は上書きせず停止する。dry-run直後に同じ分内で送信する場合も、新しい番号が必要になる。同一checkoutからの配布は直列に実行する。

### 配布の受け入れ

配布の成立は、署名・送信、Apple側の処理とグループ配信、実機の動作を順に確認する。受け入れ検証はiOS 26.5実機で、起動・作成・編集・コピー・共有拡張からの保存・本体での表示・キーボードからの挿入とコピーを対象とする。対象ビルド、端末とOS、操作、結果を記録する。キーボードは[操作検証](ios-verification.md#キーボードの操作検証)に従い、フルアクセスなしの挿入・コピー拒否と、許可時のコピーを別々に確認する。

ビルドは内部テスト専用の`testFlightInternalTestingOnly`で送信する。外部テスト・App Store公開には、それぞれの配布判断とビルドを用意する。

## 結果と失敗への対応

画面には工程名と成否、完了時のversion・build番号を表示する。認証エラーは、ファイルの存在・所有者・権限、代入書式・必須項目、識別子の書式、鍵の配置規則のいずれかを固定メッセージで示す。入力値・実際の認証パス・例外詳細・ログ末尾は返さない。

| 保存先 | 内容 |
| --- | --- |
| `artifacts/testflight/<build>/manifest.json` | 対象commit、工程、完了フラグ、archiveの公開メタデータ |
| `artifacts/testflight/<build>/Nibble.xcarchive` | 実機向けarchive |
| `artifacts/testflight/<build>/export/` | dry-runで生成したIPA等 |
| `~/.appstoreconnect/logs/nibble-<build>-<識別子>/` | Xcode・Nixの生ログとExportOptions。ディレクトリ`0700`、ファイル`0600` |

生成物はGit管理外とする。共有する実行記録にはmanifestを使い、archive・IPA・生ログをPRへ添付しない。manifestの`completed: true`はexportまたはuploadの工程完了を表す。グループへの配信や実機の動作確認は別に記録する。

失敗時は配布担当者が保護されたログを調べ、秘密情報を除いた原因だけをエージェントへ伝える。中断やtimeoutで送信結果が不明な場合はApp Store Connectの受理状況を確認し、必要な場合だけ新しい番号で実行する。自動再試行は行わない。
