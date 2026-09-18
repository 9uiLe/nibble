# TestFlight配布の検証記録

## キーボードを含む署名済みIPA

2026-09-18、対象ソース`0e401c19cd75c429dcc135e17aafb37b0e7cf242`から`0.1.0 (202609181309)`の署名付きarchiveとIPAを生成した。配布担当者から`nibble.9uiLe.com.keyboard`の登録完了の報告を受け、レビュー済みの配布スクリプトで確認した。

| 工程 | 結果 |
| --- | --- |
| `scripts/deploy-testflight.sh --check-config` | 成功。値・鍵の内容を非表示で設定の利用可否を確認 |
| `scripts/deploy-testflight.sh --dry-run` | 共通検査、依存解決、Release archive、署名したIPAの書き出しが成功 |
| 同梱構成 | 本体`nibble.9uiLe.com`、共有拡張`nibble.9uiLe.com.share`、キーボード`nibble.9uiLe.com.keyboard`の3 bundleを検査 |
| 実行記録 | `artifacts/testflight/202609181309/manifest.json`。`destination: export`、`stage: export`、`completed: true` |
| TestFlight・実機 | 未送信。Apple側の処理、本人用グループへの反映、実機操作は未確認 |

環境はXcode 26.5、iPhoneOS SDK 26.5、最低iOS 26.0、Release。認証設定・秘密鍵・Keychain・生ログを直接参照せず、スクリプトの工程結果と公開manifestを確認した。Xcodeによるprovisioning更新と署名・exportが成立したことと、実機でのApp Group読み取り・挿入・コピーが成立することは別の検証である。Simulatorの評価は[キーボードの検証](keyboard-validation.md)を参照する。

## 初期配布の確認範囲

2026-09-16に確認した、nibbleのローカルビルド・署名・TestFlight内部配布の結果を記録する。[配布設計](decisions/0003-testflight-distribution.md)が定義する各工程について、実行したソースと観測条件を対応付ける。操作方法は[配布手順](testflight.md)を参照する。

| 確認対象 | 結果 | 対象・条件 |
| --- | --- | --- |
| 配布スクリプトと共通検査 | Nix全5 check、Python85テスト成功。うち配布スクリプト20テスト | 下記「配布スクリプトの自動検査」のソース |
| 署名と送信 | IPA生成、App Store Connectへのアップロード成功 | 0.1.0、build `202609161351` / `202609161356` |
| Apple側の処理と配布 | アップロード処理「終了」、内部ビルド「テスト中」 | build `202609161356` |
| 内部グループ | 「本人用」、Xcodeビルドを自動配信、テスター1人・ビルド1個 | App Store Connectの画面で確認 |
| インストール状況 | 「インストール済み」と表示 | iPhone 17、iOS 26.6.1、build `202609161356` |
| 製品テスト | Releaseで42件成功、失敗・skipなし | iOS 26.5 Simulator、下記「製品テストと共有保存」のソース |
| 本体と共有拡張の連携 | Safariからの共有保存、本体での表示・コピー、本文のUTF-8完全一致 | iOS 26.5 Simulator |
| iOS 26.5実機での受け入れ | 未実施 | 起動・編集・コピー・共有保存の実機操作は未確認 |

App Store Connectのインストール表示は、エージェントによる実機操作の結果ではない。自動配信設定後の新規アップロードは未実施であり、次のビルドが自動配信される一連の経路は未確認である。

## 対象ソースと環境

| 用途 | 対象コミット |
| --- | --- |
| 製品のReleaseテスト、Simulator共有保存、署名なしarchive | `f0ff5063ef42fd09742accb00699a7f306772ecd` |
| 配布スクリプトの認証検査、署名したIPA、アップロード | `3746af2c79be8e8e24ed015909781e08dfa752b2` |
| 自動配信の完了案内を含む配布スクリプトの共通検査 | `eb2b51bb8d3404d97f61a75ee7025a666cbd2306`の非Markdown入力 |

ビルド環境はXcode 26.5（17F42）、Swift 6.3.2、macOS 26.2（25C56）、arm64。構成はRelease、iPhoneOS SDK 26.5、最低対応OSは26.0、Swift Packageは共有`Package.resolved`で固定した。

| 対象 | 識別子 |
| --- | --- |
| 本体 | `nibble.9uiLe.com` |
| 共有拡張 | `nibble.9uiLe.com.share` |
| App Group | `group.nibble.9uiLe.com` |

製品・テストと配布スクリプトの実行ソースは表のとおり異なる。Simulator runのソース照合は製品テストの対象コミットに対する結果であり、配布スクリプトを含む任意の後続コミットに対するiOS再実行を示さない。

## 署名したIPAとアップロード

対象ソース`3746af2c79be8e8e24ed015909781e08dfa752b2`のcleanな作業ツリーから、配布スクリプトを実行した。

| 実行 | 結果 | 公開メタデータの記録 |
| --- | --- | --- |
| `--check-config` | 「認証設定: 利用可能」 | 工程名と成否だけを確認 |
| `--dry-run`、0.1.0 (202609161351) | 共通検査・依存解決・署名付きarchive・IPA書き出し成功 | `artifacts/testflight/202609161351/manifest.json` |
| 引数なし、0.1.0 (202609161356) | 共通検査・依存解決・署名付きarchive・アップロード成功 | `artifacts/testflight/202609161356/manifest.json` |

両manifestの`completed`は`true`で、destinationはそれぞれ`export`と`upload`。archiveの公開メタデータは本体・共有拡張の識別子、version・build、最低iOS 26.0、SDK 26.5を示している。

認証設定・API秘密鍵・Keychain・保護された生ログはエージェントから直接参照していない。署名と送信はXcodeが担当し、スクリプトが返した工程の成否とmanifestを確認した。生ログは配布担当者が管理する認証ディレクトリにあり、この記録に含めない。

## App Store Connectと内部配信

0.1.0 (202609161356)について、App Store Connectのアップロード処理「終了」、内部ビルドの状態「テスト中」を確認した。テスター画面には同じビルドの「インストール済み」、端末iPhone 17、iOS 26.6.1が表示された。輸出コンプライアンスの回答内容は参照しておらず、スクリプトにも申告を設定していない。

内部グループの設定と登録状況は次のとおり。

| グループ | ID | 配信設定・登録状況 |
| --- | --- | --- |
| 本人用 | `3e31bd4b-7759-42fe-852f-8354d905b295` | 「Xcodeビルドを自動配信」、配布担当者1人、ビルド1個 |
| 本人用（手動） | `bc6371d5-32e8-4d5b-a1ac-0095d91bcdf8` | 手動配信、配布担当者1人、ビルド1個。定常の自動配信先には使用しない |

「本人用」は作成時に自動配信を有効にし、設定画面で保存された状態を確認した。配布済みビルドはこのグループへ手動追加せずに反映された。新規アップロードに対する自動配信と端末側の自動インストールは未検証。

## 配布スクリプトの自動検査

Nixの全5 checkとPython回帰テスト85件が成功した。うち20件が配布スクリプトを対象とし、使い捨てのダミー設定・鍵ファイルとApple CLIのmockを使用する。

| 契約 | 検査内容 |
| --- | --- |
| 設定の解釈 | 必須4項目、任意の先頭`export`、追加変数。重複・不足・不正な識別子・コマンド置換・指定外の鍵パスを拒否 |
| ファイル保護 | 所有者以外への権限やsymlinkを拒否。PythonによるAPI秘密鍵の内容の読み取りを検出 |
| 出力の限定 | 認証エラーは固定した工程名と案内。15種類の失敗条件と分類できない例外でも、値・鍵の内容・例外詳細が出力されない |
| 環境の制御 | 設定内の追加変数PATH・DEVELOPER_DIRを環境へ反映しない。追加変数で必須項目を補えない |
| archive | 識別子・versionの不一致、Simulator用成果物、Privacy Manifestの欠落を拒否 |
| 実行の管理 | 未コミットの変更、Git管理された署名ファイル、同じbuild番号、同時実行、実行中のソース変更を拒否 |
| Apple CLIの呼び出し | dry-runとuploadの区別、内部専用export、固定SPM lock、マクロ検証、子プロセス環境、IPA欠落時の失敗、エラー・timeout時の生ログ非表示 |

ログは`artifacts/testflight/credential-compatibility-nix-check.log`と`artifacts/testflight/automatic-distribution-nix-check.log`。前者は`3746af2c79be8e8e24ed015909781e08dfa752b2`、後者は`eb2b51bb8d3404d97f61a75ee7025a666cbd2306`の非Markdown入力に対応する。mockによる成功を実際の署名やAppleによる受理の証拠には使用しない。

## 製品テストと共有保存

対象コミット`f0ff5063ef42fd09742accb00699a7f306772ecd`で、Releaseテスト42件と本体・共有拡張の連携を確認した。専用SimulatorはiPhone 17 Pro「nibble Distribution IDs 26.5」、UDID `FE82EC12-56CF-4DEC-A6DC-9DE61A5C4AA2`。runtimeは`com.apple.CoreSimulator.SimRuntime.iOS-26-5`、iOS 26.5（23F77）で、製品の保存データがない状態から実行した。

| 記録 | 保存先 |
| --- | --- |
| Releaseテスト | `artifacts/ios/20260916T123912Z-test-ef3f0a/` |
| 共有操作 | `artifacts/ios/20260916T124600Z-distribution-share-662caf/` |
| 共通検査 | `artifacts/testflight/identifiers-nix-check.log`。当該ソースでNix全5 check、Python81テスト成功 |
| 署名なし実機archive | `artifacts/testflight/Nibble-identifiers-unsigned.xcarchive` |
| archiveログ・メタデータ検査 | `artifacts/testflight/identifiers-unsigned-archive.log`、`identifiers-archive-check.json` |

テストと共有操作の各runは開始時の作業ツリーがcleanで、開始・終了時の検証入力が一致し、対象コミットに対する`check_evidence.py --integrity-only`が成功した。媒体hash、ツール・端末情報、実行コマンドをrunに保存している。共有操作では補助driver本体とそのSHA-256も保存した。

### 共有保存の操作と結果

共有操作のrun内でReleaseをビルド・インストール・起動した。本体と共有拡張のInfo.plistは対象Bundle IDを持ち、両targetの`*-Simulated.xcent`には`group.nibble.9uiLe.com`が含まれていた。

1. 空のライブラリを確認する。
2. Safariで`validation/MVPHost.html`を開き、ダミー本文を共有する。
3. 共有先のnibbleを選び、共有拡張へ本文が渡ったことを確認する。
4. タイトル`共有ID検証-49ef0768`を入力して保存し、Safariへ戻ることを確認する。
5. 本体で項目を表示し、本文をコピーする。
6. pasteboardと入力元のUTF-8を照合する。

保存したUUIDは`B3725DD3-C424-4692-B5DE-F96CF2560A9F`。本文はPython表記で`'  ご確認ありがとうございます。\n日本語 か\u3099 👩🏽‍💻  '`。前後の空白、改行、結合文字、絵文字を含めて完全一致した。日本語はペースト入力であり、IME変換の検証は含めない。

### 画像・録画

`initial-library.png`、`share-options-still.png`、`share-editor.png`、`shared-in-library.png`で、空の一覧、共有先、入力済み編集画面、保存後の項目とコピー通知を目視確認した。`share-source.png`では共有元のダミー本文を確認した。画像は1206×2622。

`recording.mp4`は136.393秒で、2.558秒の共有メニュー、70.702秒の共有拡張、111.787秒の本体ライブラリを抽出フレームで確認した。全編の連続再生は未実施。録画にはdriverの待機が含まれるため、アプリの応答時間として使用しない。

観測と閲覧条件はrun内の`review.json`に記録した。[PR #12](https://github.com/9uiLe/nibble/pull/12)に次の原本を添付し、2026-09-17（JST）にChromeでGitHubリポジトリ所有者としてログインした状態で確認した。

| 媒体 | 公開先と確認結果 |
| --- | --- |
| 保存前 | [空のライブラリ](https://github.com/user-attachments/assets/0f9e2df4-be00-4b15-91b0-0d64ba9755a2)、1206×2622で読み込み成功 |
| 共有拡張 | [入力済み編集画面](https://github.com/user-attachments/assets/2a45c2a1-5089-40cb-a4ce-6d62a6d9c8d8)、1206×2622で読み込み成功 |
| 保存後 | [本体での表示・コピー](https://github.com/user-attachments/assets/13e3deb0-49be-4de2-a72c-96b722ddf038)、1206×2622で読み込み成功 |
| 録画 | [共有保存とコピー](https://github.com/user-attachments/assets/ebfcb2fc-fb25-42bf-9e7c-a15bb8cab08a)、videoのreadyStateは4、errorなし、1206×2622 |

ブラウザーが表示した動画時間は135.366667秒で、原本の136.393333秒と区別して記録した。確認方法は原本の抽出フレームと公開先での読み込みであり、全編再生・匿名閲覧は未実施。

### 署名なしarchive

`app/Nibble.xcodeproj` / `Nibble` / Release / `generic/platform=iOS`、iPhoneOS 26.5（23F73）でarchiveが成功した。`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空の`CODE_SIGN_IDENTITY`・`DEVELOPMENT_TEAM`、`ENABLE_TESTABILITY=NO`を指定し、Apple認証とprovisioning更新は行っていない。

本体・共有拡張とも0.1.0 (1)、最低iOS 26.0で、配布スクリプトのメタデータ検査に成功した。両targetではAppIntents.frameworkへの依存がないためメタデータ抽出をskipする警告が出た。このarchiveは実機向けコンパイルの確認であり、配布署名の検証には使用しない。

## 失敗した検証の記録

失敗した実行は成功runと別に保存している。

| 対象 | 結果と確認範囲 |
| --- | --- |
| `f0ff5063ef42fd09742accb00699a7f306772ecd`の認証設定確認 | 終了コード1、「認証設定は利用できません」。認証値・秘密鍵・詳細原因は直接参照していない |
| `f670d6228404bbb284d2fb7b27486c9733b8b5d9`の認証設定確認 | 「nibble.envの4項目の書式」で失敗。当該パーサーは必須項目以外の変数を拒否する実装だった |
| `20260916T124424Z-distribution-share-7ece72` | 補助driverがSimulatorのcodesign出力からApp Groupsを取得できず、共有操作前に停止。出力は空の辞書だった |

共有操作の成功run`20260916T124600Z-distribution-share-662caf`は、Xcode生成の`*-Simulated.xcent`からSimulator向けentitlementsを検査するdriverを使用している。失敗runのdriverと結果は上書きしていない。

## 未確認事項

- 自動配信設定後の新規アップロードから「本人用」への配信までの確認。
- iOS 26.5実機での起動・編集・コピー・共有保存と、端末側の自動インストール。
- 記録した共有操作以外の製品導線の再検証。製品操作全体の記録は[SPM構成の検証](spm-validation.md)で対象ソースと条件を確認する。
- 録画の全編再生と、添付媒体の匿名での閲覧。
- 実機の性能・ロック時保護、外部テスト、App Store審査。配布処理から性能改善を主張する測定は行っていない。
