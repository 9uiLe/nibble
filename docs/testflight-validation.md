# TestFlight配布の検証記録

## 初回の署名とアップロード

2026-09-16、対象コミット`3746af2c79be8e8e24ed015909781e08dfa752b2`から、レビューした配布スクリプトを実行した。Release、iPhoneOS SDK 26.5、最低iOS 26.0、固定SPM lockで、本体`nibble.9uiLe.com`と共有拡張`nibble.9uiLe.com.share`をarchiveした。

| 実行 | 結果 | 記録 |
| --- | --- | --- |
| `--dry-run`、0.1.0 (202609161351) | 共通検査・依存解決・署名付きarchive・IPA書き出し成功。アップロードなし | `artifacts/testflight/202609161351/manifest.json` |
| 引数なし、0.1.0 (202609161356) | 共通検査・依存解決・署名付きarchive・App Store Connectへのアップロード成功 | `artifacts/testflight/202609161356/manifest.json` |

両manifestの`completed`は`true`で、実行ソースは同じ。認証値・API秘密鍵・Keychain・保護された生ログはエージェントから直接参照していない。署名と送信はXcodeが担当し、スクリプトから返された工程の成否と公開メタデータを確認した。

App Store Connectで、0.1.0 (202609161356)のアップロード処理「終了」、内部専用ビルドの状態「テスト中」を確認した。本人1名への配布後、テスター画面には同じビルドが「インストール済み」と表示された。表示された端末はiPhone 17、iOS 26.6.1。これはApple側のインストール状況の観測であり、エージェントによる実機操作や、受け入れ対象のiOS 26.5での検証ではない。実機での起動・編集・共有保存の操作確認は未実施。

初回は輸出コンプライアンスの回答待ちだったが、その後「テスト中」になったことを確認した。本人が入力した回答内容は参照しておらず、スクリプトにも申告を追加していない。

## 本人への自動配信設定

2026-09-16、App Store Connectで内部グループ「本人用」を作成し、作成時の「自動配信を有効にする」を有効にした。本人のアカウント1件だけを追加し、設定画面の「Xcodeビルドを自動配信」、テスター1人、ビルド1個を確認した。既存のビルドは、グループへ手動追加せずに反映された。

- 自動配信グループ：`3e31bd4b-7759-42fe-852f-8354d905b295`。
- 既存の手動配信グループ`bc6371d5-32e8-4d5b-a1ac-0095d91bcdf8`は「本人用（手動）」へ改名し、ビルド・テスター・履歴を保持した。

作成画面では配信設定を後から変更できないと案内され、既存グループの設定にも変更操作がなかったため、新規グループを使用した。以後のローカルXcodeアップロードを自動配信する設定は完了したが、設定後の新しいビルドはまだアップロードしていない。Apple側の処理や輸出コンプライアンスが未完了の場合、配信可能になるまで待つ必要がある。

配布コマンドの成功案内と手順書を自動配信に合わせた。署名・アップロードの処理、認証処理、製品ソースは変更していない。Nixの全5 checkとPython回帰テスト85件が成功した。ログは`artifacts/testflight/automatic-distribution-nix-check.log`。

## 共通の設定書式の検証

2026-09-16、num-pathの追跡対象スクリプトと設定例（`bcab35964391d104c93ba33c85a40d5615b2ffd9`）に合わせ、先頭の`export`と追加変数を含む代入を受け付けるようにした。nibbleは必須4項目だけを使用し、追加の値を保存・出力したり、子プロセスの環境変数へ反映したりしない。設定をshellとして実行せず、変数名の重複・必須項目の不足・コマンド置換・指定外の鍵パスは拒否する。

ダミー設定による配布スクリプトの20テストと、Nixの全5 checkが成功した。Python回帰テストは85件。追加変数にPATH・DEVELOPER_DIRを含めてもプロセス環境が変わらず、必須項目の代わりにならず、値が出力へ含まれないことを確認した。ログは`artifacts/testflight/credential-compatibility-nix-check.log`。

修正後の`--check-config`は「認証設定: 利用可能」で成功した。認証値・秘密鍵の内容・生ログは直接参照していない。これは設定の利用可否であり、Appleへの接続・署名・配布の成功ではない。以下の認証診断は互換修正前の観測、iOS実行は明記した製品ソースの記録である。

## 認証設定の診断（互換修正前）

2026-09-16、認証設定の検査を、固定した工程名と成否だけを返す診断にした。設定値・実際のパス・例外詳細は返さず、API秘密鍵の内容を開かない。ファイルの存在・所有者・権限、設定と識別子の書式、鍵の配置規則を区別する。

配布スクリプトの18テストが成功した。15種類の使い捨ての失敗fixtureで、返却する工程名が固定され、入力値や秘密鍵の内容が出力されないことを検査した。分類できない例外も、固定メッセージだけを返す。実際の認証情報を使った自動テストではない。

Nixの全5 checkも成功し、Python回帰テストは83件。ログは`artifacts/testflight/credential-diagnostics-nix-check.log`。診断変更は配布スクリプト・回帰テスト・説明文書に限り、製品・Xcode設定・SPM lock・Simulator driverは変更していない。下記のiOS実行記録は記載したコミットに対する結果であり、診断変更後の再実行とは扱わない。

修正したスクリプトの`--check-config`は「nibble.envの4項目の書式」で失敗した。認証ディレクトリと設定ファイルの検査・読み取りは通過したが、識別子の値・鍵の配置・Appleへの接続は未確認。設定内容の直接参照は行っておらず、本人による書式の確認・修正が必要。

## 配布識別子の確認結果

2026-09-16、対象コミット`f0ff5063ef42fd09742accb00699a7f306772ecd`で、配布識別子を使った署名なし実機archive、Releaseテスト、Simulatorの共有保存を確認した。本体は`nibble.9uiLe.com`、共有拡張は`nibble.9uiLe.com.share`、App Groupは`group.nibble.9uiLe.com`。

| 確認 | 結果 |
| --- | --- |
| 共通検査 | Nixの全5 check成功。Python回帰テスト81件、Swiftソース29件、文書・workflow・Nix書式・配布launcherのShellCheckを含む |
| 実機向けRelease archive | 署名なしで成功。本体・共有拡張とも0.1.0 (1)、最低iOS 26.0、iPhoneOS SDK 26.5 |
| 製品テスト | iOS 26.5 SimulatorのReleaseで42件成功、失敗・skipなし |
| 共有拡張と本体の連携 | Safariから共有・保存・共有元への復帰、本体の表示・コピーを確認。本文のUTF-8完全一致に成功 |
| ソースと媒体の照合 | テストと共有操作の両runで`check_evidence.py --integrity-only`成功 |
| 画像・録画 | ローカルPNGと録画の3抽出フレームを確認。全編再生・PR添付・アップロード先の閲覧確認は未実施 |
| 認証設定の利用可否 | `scripts/deploy-testflight.sh --check-config`は終了コード1。「認証設定は利用できません」の固定メッセージ。値・鍵の内容・詳細な原因は参照していない |
| Apple側の登録・署名・アップロード | 未実施。App ID・App Group・Teamの登録照合、署名したIPA、Appleへの認証・接続は未確認 |
| TestFlightの処理完了・端末への配布 | 未実施。内部グループ、実機インストールと実機での共有保存は未確認 |

認証と署名の初回準備は、本人が[配布手順](testflight.md)に従って行う。Simulatorの共有保存や署名なしarchiveの成功をTestFlight配布の完了として扱わない。

## 実行環境とソース

Xcode 26.5（17F42）、Swift 6.3.2、macOS 26.2（25C56）、arm64で実行した。各runの開始時は上記コミットで作業ツリーがcleanだった。テスト・共有操作の開始時と終了時の検証入力は同じで、対象コミットとの照合に成功した。記録文書だけを更新した場合も最終HEADと再照合する。

Simulatorは専用のiPhone 17 Pro「nibble Distribution IDs 26.5」、UDID `FE82EC12-56CF-4DEC-A6DC-9DE61A5C4AA2`。runtimeは`com.apple.CoreSimulator.SimRuntime.iOS-26-5`、iOS 26.5（23F77）。新規端末を使い、旧識別子のアプリ・保存データがない状態から検証した。

| 記録 | 保存先 |
| --- | --- |
| 共通検査 | `artifacts/testflight/identifiers-nix-check.log` |
| Releaseテスト | `artifacts/ios/20260916T123912Z-test-ef3f0a/` |
| 共有操作 | `artifacts/ios/20260916T124600Z-distribution-share-662caf/` |
| 署名なし実機archive | `artifacts/testflight/Nibble-identifiers-unsigned.xcarchive` |
| archiveのログと検査結果 | `artifacts/testflight/identifiers-unsigned-archive.log`、`identifiers-archive-check.json` |

生成物はGit管理外。各Simulator runには実行コマンド、ツール・端末情報、ソースと媒体のhash、成否を保存した。共有操作は補助driverを使い、実行した`driver.py`とそのSHA-256も同じrunに保存した。

## 署名なし実機archive

`app/Nibble.xcodeproj` / `Nibble` / Release / `generic/platform=iOS`、iPhoneOS 26.5（23F73）で実行した。`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空の`CODE_SIGN_IDENTITY`と`DEVELOPMENT_TEAM`、`ENABLE_TESTABILITY=NO`を指定した。provisioning更新やApple認証は行っていない。

共有`Package.resolved`のバージョンのみを使用し、自動解決・更新を無効にした。依存のsource cacheは取得済みのローカルcheckoutを再利用した。Xcodeの結果は`ARCHIVE SUCCEEDED`で、配布スクリプトのメタデータ検査も成功した。

本体と共有拡張には、AppIntents.frameworkへの依存がないためメタデータ抽出をskipする警告が出た。ビルド失敗ではなく、App Intentsの動作確認済みという意味でもない。このarchiveには配布署名がなく、Appleによる検証・受理を示さない。

## 共有保存の操作と観測

同じrun内でReleaseをビルド・インストール・起動し、本体と共有拡張のInfo.plistのBundle IDを確認した。両targetのXcode生成物`*-Simulated.xcent`には、同じ`group.nibble.9uiLe.com`が含まれていた。これはSimulator向けの設定確認であり、Appleの配布profileや署名の確認ではない。

1. 空の本体ライブラリを確認する。
2. ローカルの検証ページ`validation/MVPHost.html`をSafariで開き、ダミー本文を共有する。
3. 共有メニューのnibbleを選び、共有拡張の編集画面に本文が入ることを確認する。
4. タイトル`共有ID検証-49ef0768`を入力して保存し、編集画面が閉じてSafariへ戻ることを確認する。
5. 本体で同じタイトルと本文の項目を確認し、コピーする。
6. pasteboardの本文を入力元とUTF-8で比較する。

保存した項目のUUIDは`B3725DD3-C424-4692-B5DE-F96CF2560A9F`。本文はPythonの表記で`'  ご確認ありがとうございます。\n日本語 か\u3099 👩🏽‍💻  '`で、前後の空白、改行、結合文字、絵文字を含めて完全一致した。日本語はペースト入力であり、IME変換の再検証ではない。

### 画像・録画の確認範囲

`initial-library.png`、`share-options-still.png`、`share-editor.png`、`shared-in-library.png`で、空のライブラリ、共有先、本文と入力済みタイトル、保存後の項目とコピー通知を目視確認した。画像は1206×2622。`share-source.png`では共有元のダミー本文を確認した。

録画`recording.mp4`は136.393秒。抽出した2.558秒の共有メニュー、70.702秒の共有拡張、111.787秒の本体ライブラリを確認した。録画には操作と読取の待機が含まれるため、録画時間からアプリの応答性能を評価しない。全編を連続再生した確認ではない。

観測はrun内の`review.json`に記録し、外部URLとブラウザー閲覧欄は未記入としている。ローカル確認と整合性検査の成功だけで、レビュー担当者向けの添付が完了したとは扱わない。

### 中断した補助検証

`20260916T124424Z-distribution-share-7ece72`では、ビルド・インストール・起動後、補助driverがApp Groupsをcodesignの署名plistから取得しようとして失敗した。実際の出力は空の辞書で、共有操作の前に停止した。

Simulator向けのentitlementsはXcode生成の`*-Simulated.xcent`を確認するよう補助driverを修正し、別runで上記の成功を得た。製品コードは変更していない。失敗runと当時のdriverを保存し、成功扱いにはしていない。

## 配布スクリプトの自動検査

81件のPython回帰テストのうち16件が配布スクリプトを対象とする。使い捨てのダミー設定・鍵ファイルとApple CLIのmockを使用し、実際の秘密情報は使用しない。

設定の重複・未知の項目・shell式・指定外の鍵パス・広いfile permission・symlinkを拒否し、設定読取時に秘密鍵の内容を開かないことを確認する。設定確認の出力に認証設定の値や例外詳細が含まれないことも検査する。

archiveについて、別のbundle ID、versionの不一致、Simulator用成果物、Privacy Manifestの欠落を検査する。配布について、未commitの変更・Git管理された署名ファイル・同じbuild番号での再実行・同時実行・実行中のソース変更を拒否する。

Apple CLIのmockではdry-runとuploadの区別、内部専用export設定、IPAがない場合の失敗、固定SPM lock、macro検証の維持、子プロセスの環境変数、失敗・timeout時に生ログを出力しないことを確認する。実際に署名したIPAを生成した証拠や、Appleに受理された証拠ではない。

## 変更の影響範囲と未確認条件

配布識別子の変更に対して、本体・共有拡張・共有保存先の対応を検証した。既存の製品操作全体の確認は[SPM構成の検証](spm-validation.md)に対象ソースと条件を記録している。今回の共有操作で全導線を再検証したとは扱わない。

性能に関わる処理の変更はなく、性能の比較測定は実施していない。最低対応iOS 26.0への適合と、iOS 26.5での実行評価を区別する。署名・アップロードとApple側の配布・インストール表示は冒頭に記録した。実機での共有保存と、iOS 26.5実機での受け入れ検証は未実施。

## 旧構成の観測記録

以下は対象ソースや条件が異なる観測で、現在の識別子での配布実績には使用しない。

- 製品ソース`76ebf8256441fc434b1c07f7e27aaef4fb1e2903`では、本体`dev.nibble.app`、共有拡張`dev.nibble.app.share`の署名なしRelease archiveが成功した。成果物は`artifacts/testflight/Nibble-unsigned.xcarchive`、ログは`unsigned-archive.log`、検査結果は`archive-check.json`と`archive-check-same-user.json`。配布アイコンは1024×1024、alphaなしだった。
- 旧archiveのコピーのInfo.plistだけを変更し、Xcode 26.5の`embeddedBinaryValidationUtility`で識別子を検査した。拡張`nibble.share.9uiLe.com`は親Bundle IDのprefix不一致で終了コード1、`nibble.9uiLe.com.share`は終了コード0だった。再ビルドや署名の代用にはしていない。
- 同一ユーザーの配布スクリプトの初期検査は`artifacts/testflight/nix-check-same-user.log`、ShellCheckを含む検査は`nix-check-same-user-final.log`に保存した。`boundary-tests.log`は別ユーザーサービスの実験記録であり、現在のスクリプトの検証結果には使用しない。

## 配布手順の参照実装

num-pathの`bcab35964391d104c93ba33c85a40d5615b2ffd9`にある`docs/testflight.md`、`scripts/deploy-testflight.sh`、`.claude/settings.json`のpermissionsを確認した。認証設定・秘密鍵・署名情報の実体は参照していない。

参照実装は、リポジトリ外の認証設定、ClaudeのRead/Bash deny、`xcodebuild archive`と`-exportArchive`による配布を組み合わせる。文書は、同一OSユーザーのため完全な技術的遮断ではないことと、DeveloperロールのAPI鍵にはローカルの配布証明書・profileの事前準備が必要なことを明記している。

nibbleは同じユーザーでの配布、外部の認証設定、直接参照の禁止、署名資産の事前準備を採用する。設定から必須4項目だけを取り出し、追加変数と先頭`export`も代入として扱う。`source`は実行しない。`-skipMacroValidation`と生ログ末尾の返却は採用しない。nibble自身の署名・送信結果は冒頭に記録しており、参照実装の成功をnibbleの配布実績として扱わない。
