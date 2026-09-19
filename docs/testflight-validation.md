# TestFlight配布の検証記録

[配布設計](decisions/0003-testflight-distribution.md)に対し、対象ソース、ビルド番号、工程、観測範囲を記録する。操作方法は[配布手順](testflight.md)を参照する。別の日付・ビルドの結果を、現在のビルドの実行結果として扱わない。

## Issue #26の上部通知を採用した更新配布

2026-09-19（JST）、コミット`29eb253f0c3230943e6258fe717e2d24fd4020ce`のcleanな作業ツリーから、`NIBBLE_UI_FORMAT=json scripts/deploy-testflight.sh`を実行した。バージョンは**0.1.0 (202609191251)**。

ユーザーの「上部で良い」という選択に基づき、一覧・検索の操作完了通知を上部へ統一した。通知によるTab Bar accessoryの有効・無効の切り替えを除き、タブと作成ボタンの再配置を解消する。上部領域の表示中は一覧内容が下へ移動する。採用理由と契約は[通知の設計](design/decisions/0004-tab-accessory-notices.md)を参照する。

| 確認対象 | 結果 |
| --- | --- |
| 共通検査・依存解決 | Nix全checkと共有lockに基づくSwift Packageの解決が成功 |
| archive・署名・メタデータ | Release、iPhoneOS SDK 26.5 / 最低iOS 26.0で成功。本体・共有拡張・キーボードの識別子、バージョン、Privacy Manifest、輸出申告のBoolean falseを検査 |
| アップロード | 成功。配布スクリプトの終了コード0 |
| 公開記録 | `artifacts/testflight/202609191251/manifest.json`。`destination: upload`、`stage: upload`、`completed: true`、対象commitとversion・buildの一致を確認 |
| Simulatorの操作記録 | darkのrun `20260919T123747Z-notice-ui-1c837c`でコピー・取り消し・検索入力保持・離脱復帰・タブと作成ボタンの位置不変・末尾コピー後の位置復帰を確認 |
| 製品テスト | run `20260919T124140Z-test-81095f`で116件（パラメーター展開後136件）が成功。失敗・skipは0件 |
| 配布ソースとの照合 | 上記UI・製品テストの両runで、配布commitへの`check_evidence.py --integrity-only`が成功 |
| Apple側の処理・グループ配信・実機操作 | 配布担当者が確認する。エージェントは未確認 |

認証設定・秘密鍵・Keychain・保護された生ログは直接参照していない。画像と抽出フレームの閲覧範囲、通知中の末尾「その他」操作などの未確認条件は[通知の検証](notice-validation.md#上部配置の採用)に記録する。この配布記録の追加はアップロード後であり、配布ソースへ含めない。

## Issue #26の通知配置の評価用配布

2026-09-19（JST）、コミット`f306ed3b1c6883829898e1f2d93c04bb731f68d7`のcleanな作業ツリーから、`NIBBLE_UI_FORMAT=json scripts/deploy-testflight.sh`を実行した。バージョンは**0.1.0 (202609191149)**。

一覧のTab Bar accessory通知と削除取り消し、検索入力中だけ上部に通知を置く試作を含む。ユーザーからTestFlightでの確認依頼を受けた評価用配布であり、検索入力中の配置の正式採用を意味しない。[G13の評価条件](design/audit.md#g13-b--検索入力中の通知配置)に従って判断する。

| 確認対象 | 結果 |
| --- | --- |
| 共通検査・依存解決 | Nix全checkと共有lockに基づくSwift Packageの解決が成功 |
| archive・署名・メタデータ | Release、iPhoneOS SDK 26.5 / 最低iOS 26.0で成功。本体・共有拡張・キーボードの識別子、バージョン、Privacy Manifest、輸出申告のBoolean falseを検査 |
| アップロード | 成功。配布スクリプトの終了コード0 |
| 公開記録 | `artifacts/testflight/202609191149/manifest.json`。`destination: upload`、`stage: upload`、`completed: true`、対象commitとversion・buildの一致を確認 |
| Simulatorの操作記録 | run `20260919T111823Z-notice-ui-f0a627`を配布commitへ照合し、`check_evidence.py --integrity-only`が成功。画像・動画の閲覧範囲は[通知の検証](notice-validation.md)を参照 |
| Apple側の処理・グループ配信・実機操作 | 配布担当者が確認する。エージェントは未確認 |

認証設定・秘密鍵・Keychain・保護された生ログは直接参照していない。上部配置追加前の`980fd6d`で製品テスト116件が成功しているが、配布候補での全製品テスト再実行は未実施。ダーク、通知中の末尾「その他」の操作、VoiceOver音声と触覚の体感も未確認として残す。この配布記録の追加はアップロード後であり、配布ソースへ含めない。

## タイトル中心の一覧と全文操作の内部配布

2026-09-19（JST）、コミット`3c91f027a2c4ef6f0ec219473177e0030c59f255`のcleanな作業ツリーから、`NIBBLE_UI_FORMAT=json scripts/deploy-testflight.sh`を実行した。バージョンは**0.1.0 (202609190447)**。

対象は行タップによる挿入、独立した「…」からの全文確認、コピー・ピン操作、短い結果表示。文字サイズ・太字・コントラストを標準値に固定する本体・共有拡張・キーボードを含むReleaseビルドである。

| 確認対象 | 結果 |
| --- | --- |
| 共通検査・依存解決 | Nix checkと共有lockに基づくSwift Packageの解決が成功 |
| archive・署名・メタデータ | iPhoneOS SDK 26.5 / 最低iOS 26.0で成功。3ターゲットの識別子・バージョン・Privacy Manifest・輸出申告のBoolean falseを確認 |
| アップロード | 成功。配布スクリプトの終了コード0 |
| 公開記録 | `artifacts/testflight/202609190447/manifest.json`。`destination: upload`、`stage: upload`、`completed: true` |
| Apple側の処理・グループ配信・実機操作 | 配布担当者が確認する。エージェントは未確認 |

認証設定・秘密鍵・Keychain・保護された生ログは直接参照していない。App Store Connectの画面確認は、Chrome接続の無応答と内蔵ブラウザーの未ログインにより成立していない。エージェントの確認範囲は署名・アップロードと公開manifestであり、Apple側の処理・配信状態は配布担当者が確認する。責務は[配布手順](testflight.md)に定義する。

配布対象コミットはReleaseの96テスト、Simulator操作と証跡のソース照合に成功している。確認した条件と未確認事項は[行タップ・全文・ピン操作の検証](keyboard-readability-validation.md)を参照する。

## キーボードのデザインと入力操作を確認する内部配布

2026-09-19（JST）、コミット`53ac97488418b58d15f9439dfc58b93b20e9b831`のcleanな作業ツリーから、`NIBBLE_UI_FORMAT=json scripts/deploy-testflight.sh`を実行した。バージョンは**0.1.0 (202609181612)**。ビルド番号はUTCの実行日時に基づく。

対象は、標準キーボードの背景、余白、フィルターに合わせた表示と、スニペットの挿入操作を示す「入力」ラベル。本体・共有拡張・キーボードを含むReleaseビルドである。

| 確認対象 | 結果 |
| --- | --- |
| 共通検査・依存解決 | Nixの全7 checkと、共有lockに基づくSwift Packageの解決が成功 |
| archive・署名・メタデータ | Xcode 26.5 / iPhoneOS SDK 26.5 / 最低iOS 26.0で成功。3ターゲットの識別子、version・build、Privacy Manifest、輸出申告のBoolean falseを確認 |
| TestFlight向けアップロード | 成功。配布スクリプトの終了コード0 |
| 公開記録 | `artifacts/testflight/202609181612/manifest.json`。`destination: upload`、`stage: upload`、`completed: true` |
| Apple側の処理・グループ配信・実機操作 | 未確認。配信先は自動配信を設定した内部グループ「本人用」。ブラウザー確認は行っていない |

認証設定、秘密鍵、Keychain、保護された生ログは直接参照せず、配布スクリプトの工程結果と公開manifestだけを確認した。

Simulatorでは、ソース`eb0ebdb461fd3e06dc6df3dfb10385e866a7ecc9`のReleaseビルドで、ラベルと本文領域からの挿入、UTF-8完全一致、Full Access無効時のコピー案内、キーボードの表示切り替え、ライト・ダーク表示を確認した。配布ソースとの差分は検証記録・手順・UIレビュー記録で、製品コード、構成、依存は同一である。画像・録画の確認範囲と未実施項目は[キーボードの検証](keyboard-validation.md)に記録する。このビルドの配布工程は、製品テスト全体の再実行と実機操作を含まない。

## キーボードを含む内部配布

2026-09-18、Xcode 26.5 / iPhoneOS SDK 26.5 / Release / 最低iOS 26.0で、3ターゲットの署名とTestFlight向け送信を確認した。

| 実行 | 対象ソース | ビルド・結果 |
| --- | --- | --- |
| `scripts/deploy-testflight.sh --check-config` | `0e401c19cd75c429dcc135e17aafb37b0e7cf242` | 設定の利用可否を値・鍵の内容を表示せず確認し、成功 |
| `scripts/deploy-testflight.sh --dry-run` | `0e401c19cd75c429dcc135e17aafb37b0e7cf242` | 0.1.0 (202609181309)。共通検査、依存解決、Release archive、署名したIPAの書き出しが成功 |
| `NIBBLE_UI_FORMAT=json scripts/deploy-testflight.sh` | `96edc861282173a5378ea4607e61698794f3b2f8` | 0.1.0 (202609181319)。共通検査、依存解決、Release archive、メタデータ検査、アップロードが成功。終了コード0 |

両ソース間の差分は検証記録のMarkdownのみで、アプリ・配布コードと依存は同一である。

| 公開記録 | 完了した工程 |
| --- | --- |
| `artifacts/testflight/202609181309/manifest.json` | `destination: export`、`stage: export`、`completed: true` |
| `artifacts/testflight/202609181319/manifest.json` | `destination: upload`、`stage: upload`、`completed: true` |

同梱する本体`nibble.9uiLe.com`、共有拡張`nibble.9uiLe.com.share`、キーボード`nibble.9uiLe.com.keyboard`の存在と識別子、version・build、最低OS、SDK、輸出申告のBoolean falseを確認した。認証設定・秘密鍵・Keychain・保護された生ログは直接参照せず、スクリプトの工程結果と公開manifestを確認した。

配信先は内部グループ「本人用」で、Apple側の処理後に自動配信する設定である。このビルドのApple側の処理完了、グループ反映、実機インストール・操作は未確認で、ブラウザー確認は行っていない。署名と送信の成功は、実機でのApp Group読み取り・挿入・コピーの成功を示さない。Simulatorの評価は[キーボードの検証](keyboard-validation.md)を参照する。

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
