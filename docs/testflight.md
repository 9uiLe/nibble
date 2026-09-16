# TestFlightの内部配布

nibbleの配布対象はiPhoneアプリ`Nibble`と共有拡張`NibbleShare`。初回は自分の端末を内部テスターとして登録する。最低対応OSは26.0、ビルド環境はXcode 26.5、実機の確認対象はiOS 26.5とする。

配布には、実機向けアーカイブ、Appleの署名、App Store Connectへのアップロード、Apple側の処理完了、内部グループへの追加、TestFlightからのインストールが必要になる。署名なしarchiveやSimulatorテストの成功は、これらの完了を意味しない。確認結果は[配布の検証記録](testflight-validation.md)に記録する。

## 必要なApple側の登録

| 対象 | 現在の識別子 | 設定 |
| --- | --- | --- |
| 本体の明示的App ID | `dev.nibble.app` | App Groupsを有効にし、下記グループを割り当てる |
| 共有拡張の明示的App ID | `dev.nibble.app.share` | 本体と同じApp Groupを割り当てる |
| App Group | `group.dev.nibble.app` | 本体と共有拡張のSQLite保存先 |
| App Store Connectのアプリ | 本体のBundle IDを選択 | iOSアプリとして作成。拡張用の別アプリレコードは作らない |

DeveloperのCertificates, Identifiers & Profilesで[App Groupを登録](https://developer.apple.com/help/account/identifiers/register-an-app-group)し、両方のApp IDに[割り当てる](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)。共有拡張の種類はInfo.plistで定義する。URL schemeの`nibble`もInfo.plistに設定済みである。

現在必要なCapabilityはApp Groups。本体と共有拡張のentitlementsは同じグループを要求する。DBのファイル保護は`FileProtectionType.complete`で設定している。登録する識別子を変える場合は、Xcode project、両entitlements、`SnippetStore.groupID`、`app/project.json`をそろえ、共有からの保存と本体からの読取を再検証する。

Team ID、Bundle ID、App Group ID、App Store Connectの数値のApple IDは秘密情報ではない。API秘密鍵、署名秘密鍵、パスワード、認証トークンは公開・Git管理・会話への貼り付けをしない。

## 秘密情報と実行権限

1台のMacで、通常の開発ユーザーと配布専用の標準ユーザー`nibble-release`を使う。AIエージェントは開発ユーザーで実行する。配布ユーザーにはAIエージェントを起動しない。

| 配置 | 所有者・役割 |
| --- | --- |
| 開発checkout | エージェントがコードの編集・検証を行う。Appleの秘密情報を置かない |
| 配布ユーザーのprivate home | 人がレビューした固定commitのサービス、Xcode認証、署名情報、API鍵を保持する |
| `~/testflight-private/`（配布ユーザー） | `config.json`、`AuthKey_<Key ID>.p8`、`release.xcarchive`、アップロード試行記録 |
| `/Users/Shared/nibble-testflight/control.sock` | 同じMacの依頼窓口。接続元のOSユーザーIDをカーネルから取得して認可する |

`.gitignore`は誤登録防止の補助であり、読取権限を分離する機構ではない。秘密情報はリポジトリの外に置き、配布homeとstate directoryは`0700`、API鍵と設定は`0600`にする。アクセスを広げるACL・共有・同期を設定しない。

分離は通常の別ユーザー間のアクセス制御を前提にする。エージェントにroot、配布ユーザーへの`sudo`・パスワード・ログイン権限、配布セッションの画面操作権限を与えない。管理者権限での侵入やOSの脆弱性に耐える仕組みとは位置付けない。

### サービスが受理する操作

`scripts/testflight.py`はクライアントとサービスの両方を提供する。クライアントは秘密情報を読み込まない。

| 操作 | 入力と制限 | 返却する情報 |
| --- | --- | --- |
| `status` | private設定で固定した1アプリを照会 | 最新10件のbuild番号・処理状態・期限切れフラグ、準備したarchiveの公開メタデータとhash |
| `upload` | 準備したarchiveのSHA-256だけを受理 | アップロードコマンドの成功、version・build。失敗時は固定メッセージ |

任意のURL・コマンド・ファイルパス・JWT署名要求は受理しない。クライアントの申告UIDを信用せず、Unix socketのpeer UIDを確認する。クライアントも配布ユーザーのUIDを照合する。HTTP接続先はAppleの固定ホストで、redirect・環境変数のproxyを使用しない。

APIの照会トークンはES256で生成し、有効期間を2分、scopeを照会するGETに限定する。鍵・トークン・APIの生レスポンス・例外の詳細をクライアントへ返さない。暗号処理にはNixで固定する`cryptography`を使う。[AppleのJWT仕様](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests)

アップロードは配布ユーザーの`xcodebuild -exportArchive`で実行する。API鍵はプロセス内またはApple CLIからのみ使用する。署名済みarchiveをprivate領域に複製し、同じhashであることを確認してから送る。試行開始を先に記録し、同じarchiveを自動再送しない。出力を失った場合やtimeoutの場合もApp Store Connectで状態を確認する。

ソースからのビルドはサービスに依頼できない。配布ユーザーが固定commitをレビューしてからビルドする。これにより、エージェントが変更できるcheckoutやビルドスクリプトを、秘密情報のある権限で自動実行しない。サービス更新も人が別途レビューして適用する。

## 初回の設定（人が行う）

以下はエージェントのターミナル・画面操作を使わず、Macを操作する本人が実施する。

### 1. 配布ユーザーと依頼窓口

システム設定 → ユーザとグループで、標準ユーザー`nibble-release`を作る。パスワードは会話やリポジトリへ記録しない。通常ユーザーのターミナルで次を実行し、出力された数値を`client_uid`として控える。

```sh
id -u
sudo install -d -o nibble-release -g staff -m 0755 /Users/Shared/nibble-testflight
```

配布ユーザーにログインする。XcodeやCLI Toolsは同じMacのインストールを使う。Nixをこのユーザーからも使えるようにする。homeの共有アクセスを解除し、state directoryを作る。

```sh
chmod -N "$HOME"
chmod 700 "$HOME"
mkdir -m 700 "$HOME/testflight-private"
```

### 2. レビューしたコードとApple認証

配布ユーザーのhomeへこのリポジトリをcloneし、レビュー済みの40桁commitを指定してcheckoutする。開発ユーザーが書き換えられるworktreeを直接実行しない。配布checkoutの自動更新も行わない。

```sh
git clone https://github.com/9uiLe/nibble.git "$HOME/nibble-release-code"
cd "$HOME/nibble-release-code"
git checkout --detach 'レビュー済みの40桁commit'
nix develop
```

XcodeのAccountsでApple Accountを追加する。Apple Developerの契約、Team、本体・共有拡張のApp Groupsを確認する。[セットアップ](../README.md#3-xcodeとswift-packageを準備する)に従い、固定したAppMacrosのrevisionだけを承認する。

App Store ConnectのUsers and Access → Integrationsで**Team API key**を作成する。照会・ビルド送信・provisioningに必要な権限を持つDeveloperロールを用い、Account Holder/Adminの鍵を初期値にしない。Team keyはApple側では全アプリに適用されるため、本サービスのアプリ限定とは別の権限範囲である。Individual keyはProvisioning endpointsに対応しないため、この構成では使用しない。[AppleのAPI key仕様](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)

鍵を配布ユーザーのブラウザーでダウンロードし、`~/testflight-private/AuthKey_<Key ID>.p8`へ移す。通常ユーザーのDownloads・共有フォルダー・clipboard・会話を経由させない。本人が配布ユーザーのターミナルで対象ファイルを`chmod 600`にする。不要なダウンロード元の複製を残さない。

`~/testflight-private/config.json`を本人が作成し、`chmod 600`にする。値は次の形。`app_id`はアプリ情報に表示される数値のApple IDで、Apple Accountのメールアドレスではない。JSONに秘密鍵やパスワードを記載しない。

```json
{
  "client_uid": 501,
  "team_id": "ABCDEFGHIJ",
  "key_id": "KLMNOPQRST",
  "issuer_id": "00000000-0000-0000-0000-000000000000",
  "app_id": "1234567890",
  "bundle_id": "dev.nibble.app",
  "extension_bundle_id": "dev.nibble.app.share"
}
```

例のUIDとApple識別子は自分の値に置き換える。秘密情報を置いた後の確認をエージェントへ依頼しない。

### 3. 署名済みアーカイブ

配布checkoutでNix共通検査を実行する。配布前のSimulator検証は[製品検証](mvp.md)に従う。Team IDと未使用のbuild番号は公開情報として指定する。本体・共有拡張のbuild番号を一緒に更新し、同じversion/buildを再利用しない。

```sh
nix flake check --no-update-lock-file --print-build-logs
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages

export NIBBLE_TEAM_ID='自分のTeam ID'
export NIBBLE_BUILD_NUMBER='1'
xcodebuild archive \
  -project app/Nibble.xcodeproj -scheme Nibble -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$HOME/testflight-private/release.xcarchive" \
  -derivedDataPath artifacts/distribution/DerivedData \
  -clonedSourcePackagesDirPath artifacts/SourcePackages \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$NIBBLE_TEAM_ID" CURRENT_PROJECT_VERSION="$NIBBLE_BUILD_NUMBER" \
  ENABLE_TESTABILITY=NO
```

これは配布ユーザーが署名情報を使用するコマンドである。Keychainの確認は本人が行う。API秘密鍵と署名秘密鍵は別物であり、API鍵だけで署名準備が完了するわけではない。両targetのprovisioning profileで同じApp Groupが許可されることをXcodeから確認する。Xcodeは条件を満たす場合に[クラウド管理対象証明書](https://developer.apple.com/help/account/certificates/cloud-managed-certificates)で配布署名を行う。

アーカイブを差し替えるときはサービスを止め、前のarchive・配布記録をprivate領域に保存してから次のbuildを準備する。ビルド中のarchiveをサービスへ渡さない。

### 4. サービスを起動

配布checkoutで起動し、このターミナルは動かしたままにする。Fast User Switchingで通常ユーザーへ戻れる。配布ユーザーをログアウトするとサービスは利用できなくなる。初期実装は自動起動daemonをインストールしない。

```sh
nix develop --command python3 -I scripts/testflight.py serve \
  --config "$HOME/testflight-private/config.json"
```

別ユーザー・private home・コードの所有者・stateの権限を満たさなければ起動を拒否する。通常ユーザーがservice fileやAPI鍵を直接読めない状態を本人が確認する。socketが残った場合は、旧サービスを終了したことを確認した本人が配布ユーザーで削除する。

## 通常ユーザーからアップロード

通常の開発checkoutで実行する。`status`が返した準備済みarchiveのversion・build・SHA-256を、配布する対象として確認する。

```sh
nix develop --command python3 scripts/testflight.py status
nix develop --command python3 scripts/testflight.py upload --release '確認した64桁のSHA-256'
```

アップロードは内部テスト専用で、build番号をXcodeに自動変更させない。このbuildを外部TestFlightやApp Storeへ転用することはできない。外部配布は別buildと配布方針の見直しが必要になる。[内部テスト専用buildの制約](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

送信成功後もAppleで処理が続く。`status`で`VALID`になったことを確認する。失敗・timeout・接続切断時は自動再送せず、配布ユーザーがApp Store Connectで受信済みbuildを確認する。API本文やXcodeの認証を含む生ログをエージェントへ渡さない。サービスの試行記録を解除する判断は配布ユーザーが行う。

## 内部グループと実機確認

App Store Connect → nibble → TestFlightで、本人だけを含む内部グループを作る。初回は自動配布を無効にし、処理済みbuildを明示的に追加する。内部テスターはアプリへのアクセス権を持つApp Store Connectユーザーである。

輸出コンプライアンスの質問には実装と利用地域に基づいて本人が回答する。現在のコードはOSのファイル保護を使用し、独自暗号処理・通信機能を実装していない。免除の判定とAppleでの回答はまだ完了していないため、`ITSAppUsesNonExemptEncryption`の宣言は固定していない。[Appleの確認手順](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)

「テストする内容」には次の操作を記載する。

- 作成、保存、日本語検索、編集、原文のコピー。
- 編集途中で閉じる、下書き再開、破棄。
- ピン留め、削除、取り消し。
- Safariの共有シートからテキスト・URLを保存し、本体で表示する。

本人のiOS 26.5端末でTestFlightからインストールし、ダミーデータで上記を確認する。TestFlightのversion/build、端末・OS、操作結果を記録する。アプリの起動と共有先からの保存が両方成立して初回配布を完了とする。実機性能、ロック時の保護、全アクセシビリティ条件をこれだけで検証済みにしない。

## 秘密情報を使わない事前確認

開発ユーザーは`xcodebuild archive`に`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=`を指定し、`-allowProvisioningUpdates`を付けずに実機向けビルドを確認できる。未署名archiveは配布ユーザーの署名済みarchiveと別に保存する。

```sh
nix develop --command python3 scripts/testflight.py archive-check \
  artifacts/testflight/Nibble-unsigned.xcarchive
```

この検査は本体・共有拡張の同梱、識別子、version/build、iOS/SDK、Privacy Manifestとアイコン設定の存在を確認する。実際の署名・profileのentitlements、Appleのvalidation、端末インストールは検査しない。GitHub Actionsは既存のUbuntu共通検査だけを使い、Appleの秘密情報を登録しない。
