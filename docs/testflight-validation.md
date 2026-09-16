# TestFlight配布の検証記録

## 現在の確認結果

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

性能に関わる処理の変更はなく、性能の比較測定は実施していない。最低対応iOS 26.0への適合と、iOS 26.5での実行評価を区別する。配布署名・Apple側の処理・TestFlightからの実機インストール・実機での共有保存は、初回設定後に別途確認する。

## 旧構成の観測記録

以下は対象ソースや条件が異なる観測で、現在の識別子での配布実績には使用しない。

- 製品ソース`76ebf8256441fc434b1c07f7e27aaef4fb1e2903`では、本体`dev.nibble.app`、共有拡張`dev.nibble.app.share`の署名なしRelease archiveが成功した。成果物は`artifacts/testflight/Nibble-unsigned.xcarchive`、ログは`unsigned-archive.log`、検査結果は`archive-check.json`と`archive-check-same-user.json`。配布アイコンは1024×1024、alphaなしだった。
- 旧archiveのコピーのInfo.plistだけを変更し、Xcode 26.5の`embeddedBinaryValidationUtility`で識別子を検査した。拡張`nibble.share.9uiLe.com`は親Bundle IDのprefix不一致で終了コード1、`nibble.9uiLe.com.share`は終了コード0だった。再ビルドや署名の代用にはしていない。
- 同一ユーザーの配布スクリプトの初期検査は`artifacts/testflight/nix-check-same-user.log`、ShellCheckを含む検査は`nix-check-same-user-final.log`に保存した。`boundary-tests.log`は別ユーザーサービスの実験記録であり、現在のスクリプトの検証結果には使用しない。

## 配布手順の参照実装

num-pathの`bcab35964391d104c93ba33c85a40d5615b2ffd9`にある`docs/testflight.md`、`scripts/deploy-testflight.sh`、`.claude/settings.json`のpermissionsを確認した。認証設定・秘密鍵・署名情報の実体は参照していない。

参照実装は、リポジトリ外の認証設定、ClaudeのRead/Bash deny、`xcodebuild archive`と`-exportArchive`による配布を組み合わせる。文書は、同一OSユーザーのため完全な技術的遮断ではないことと、DeveloperロールのAPI鍵にはローカルの配布証明書・profileの事前準備が必要なことを明記している。

nibbleは同じユーザーでの配布、外部の認証設定、直接参照の禁止、署名資産の事前準備を採用する。設定は固定した4項目として解釈し、`source`しない。`-skipMacroValidation`と生ログ末尾の返却は採用しない。実際の署名準備・API接続は未実施であり、参照実装の成功をnibbleの配布実績として扱わない。
