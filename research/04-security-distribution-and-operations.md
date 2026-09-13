# セキュリティ・プライバシー・配布・運用

調査日：2026-09-13。対象：iOS 26.0 以上。アプリと Xcode プロジェクトは未作成。

**読み方：**「確認した事実」は引用元で確認した仕様・要件、「設計への示唆」は nibble への提案、「未確認」は実機・実装・審査で確認すべき事項。ここでは技術や配布方式の採用を決定しない。Apple の現行 Web 文書は更新されるため、公開前にも再確認する。

## 先に押さえること

- 保存データの暗号化、端末ロック中のアクセス制御、クリップボードへの持ち出し、ログへの露出は別の問題として扱う。Data Protection の既定クラスだけで「ロックすれば読めない」とは判断できない。[^S06][^S13]
- キーボード拡張には App Review 独自の要件がある。API で可能に見える操作でも、審査上許されるとは限らない。[^S01]
- ローカル処理のみのデータは App Privacy 回答の「収集」に該当しないが、全アプリにプライバシーポリシーへのリンクが必要。Privacy Manifest と App Privacy 回答も別々に確認する。[^S01][^S02][^S03]
- Nix の補助ツール、Xcode / SDK、アプリの Swift Package 依存は別の管理対象になる。アプリの依存は `Package.resolved` も共有する。[^S11]

## 1. データの境界を設計する

### 確認した事実

Apple の Data Protection はファイル単位の保護クラスと鍵階層でアクセス可能な状態を制御する。サードパーティアプリのデータにも適用される。`NSFileProtectionComplete` と `NSFileProtectionCompleteUntilFirstUserAuthentication` は挙動が異なり、後者は初回認証後に端末を再ロックしてもクラス鍵をメモリから除去しない。特に指定されないサードパーティアプリのデータは後者が既定である。[^S06][^S13]

Keychain services はパスワード・鍵などの小さな秘密情報を暗号化されたデータベースに保存する API である。`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` はアンロック中だけアクセスでき、別端末へのバックアップ復元では移行されない。安全性だけでなく復元時の体験にも影響するため、この属性を全データへ機械的に適用する根拠にはならない。[^S04][^S05]

### 設計への示唆

スニペットは定型挨拶から個人情報まで含み得る。ユーザーが何を保存するかをアプリ側で完全には予測できないため、次のコピー先も含めたデータフロー図を最初に作る。

| 境界 | 決めること | 確認方法 |
| --- | --- | --- |
| 本体の保存領域 | DB・関連ファイル・添付・索引の保護クラス、バックアップ対象 | ロック前後・再起動後・復元後に読み書きする |
| App Group | どの extension にどのデータを見せるか。共有用スナップショットを作るか | Full Access の有無とファイル・DB の読み書きを別々に確認 |
| クリップボード・挿入先アプリ | 明示操作、他端末へのコピー、期限、持ち出しの説明 | [呼び出し導線の調査](01-invocation-and-platform.md) の貼り付け条件で確認 |
| 検索・Shortcuts・ロック画面 | 本文まで表示するか、利用時に認証が必要か | ロック状態・通知や候補表示での露出を確認 |
| エクスポート・バックアップ・同期先 | 書式、暗号化の有無、読み戻し、削除後の残存データ | 移行・削除・復元の往復試験 |
| ログ・クラッシュ資料・PR の画像 | 本文・検索語・貼り付け先が混入しないか | ダミーデータでログと画像を検査 |

これは脅威モデルを作るための提案であり、各境界での実装済み保護を示すものではない。DB とバックアップ方式の選択は [データとアーキテクチャ](02-data-and-architecture.md) と合わせて判断する。

**未確認：** App Group 内の DB、本体と extension の同時アクセス、WAL 等の付随ファイル、ロック画面からの Intent 実行における保護クラスの実効性。端末ロックによる読取失敗を「データが存在しない」と解釈して空データで上書きしない設計が必要。

## 2. ログと画面にもデータが残る

### 確認した事実

Apple の unified logging は、動的文字列や複雑な動的オブジェクトを既定で伏せる一方、整数・浮動小数・真偽値は既定では伏せない。Apple は自分で定義した静的文字列・数値にログを抑え、機微な値には明示的な privacy 指定を行うよう案内している。[^S17]

UIKit はバックグラウンド遷移時の delegate 処理後に UI のスナップショットを取り、アプリスイッチャーなどに表示する。Apple はパスワード等の機微な内容をバックグラウンド移行時に隠すよう説明している。また、アプリは通常バックグラウンドで継続実行されず、追加実行時間は個別の用途・能力に依存する。[^S18]

### 設計への示唆

- パフォーマンス計測は処理名・時間・件数を中心にし、本文、検索語、URL、ホストアプリで入力中の文字列をログに含めない。
- 「削除に失敗した理由」の記録にも本文を埋め込まない。問い合わせ時のログ収集や画面録画にも同じ規則を適用する。
- 機密扱いのスニペットを提供するなら、アプリスイッチャー、検索候補、Intent の表示、コピー後の説明を一緒に設計する。独自のアプリ内ロックだけを保護範囲の説明にしない。
- CRUD の保存完了条件を明確にし、後でバックグラウンド処理が必ず動いて保存・削除を完了することに依存しない。

**未確認：** SwiftUI の scene 変化と実際のスナップショットのタイミング、編集中テキストの復元、extension 終了直前の保存。スクリーンショット禁止や、持ち出したテキストの完全な回収を保証するものではない。

## 3. キーボードとスニペット機能の審査上の境界

### 確認した事実

App Review Guidelines 2.5.1 は公開 API の使用と意図された用途を、2.5.2 は指定されたコンテナ外の読書きや機能を変更するコードのダウンロード・実行等の制約を定める。2.5.16 は widget / extension 等とアプリ機能の関連性を求める。スニペットを保存・貼り付けることと、スニペットをアプリ内で実行して機能を変えることは区別して検討する。[^S01]

4.4 は extension の内容をマーケティング文で正確に説明することを求め、extension 内の広告・マーケティング・アプリ内購入を認めていない。4.4.1 はキーボード拡張に次を求める。[^S01]

- 文字入力などのキーボード入力機能を提供する。
- 次のキーボードへ移る方法を提供する。
- Full Access やフルネットワークアクセスを要求せずに機能する。
- ユーザーの活動を収集する場合、端末上のキーボード拡張の機能向上という目的に限定する。
- Settings 以外の別アプリを起動しない。キーボードのキーを別の意図の操作に転用しない。

### 設計への示唆

「キーボードで選択し、編集時は URL scheme で本体へ移動する」を標準導線として確定しない。キーボード内で提供する最低限の機能、設定での有効化、権限拒否時の挙動を小さな試作で先に検証する。Full Access なしの共有領域読取については、旧アーカイブより現行 UIKit 資料を優先する。[^S01] 読取専用キーボード案の根拠と実機で残る不確実性は [呼び出し導線](01-invocation-and-platform.md) に記載する。

**未確認：** スニペット選択・挿入に絞ったキーボードが「入力機能」の要件をどの構成で満たすか、初回審査で求められる説明や実演。公式文書の読解で将来の審査結果を保証することはできない。

## 4. プライバシーの3つの成果物

| 成果物 | 確認した要件 | nibble で決めること |
| --- | --- | --- |
| プライバシーポリシー | 全アプリで App Store Connect とアプリ内の分かりやすい位置にリンクが必要。収集・利用・共有・保持・削除等を説明する。[^S01] | 本文を端末外へ送るか、問い合わせ・診断で何を受け取るか、同期や削除の扱い |
| App Privacy の回答 | 自分と組み込んだ第三者の収集を確認する。端末内でのみ処理されるデータは「収集」に含まれない。[^S02] | 「収集なし」を希望で選ばず、SDK・同期・診断を含む実際のデータフローから回答する |
| `PrivacyInfo.xcprivacy` | 収集内容、tracking、required reason API の利用等を宣言する。対象となる SDK にも固有の要件がある。[^S03][^S12][^S14] | 本体・extension・Swift Package / SDK を点検し、使用 API と利用理由を照合する |

Required reason API を使う各 executable / dynamic library について、その bundle が理由を報告する manifest を含む必要がある。第三者 SDK の利用理由をホストアプリの manifest だけに委ねてよいわけではない。理由は実際の用途と一致し、Apple が承認したものから選ぶ。対象 API と理由の一覧は更新される。[^S12]

Privacy Manifest は target の resources に含める。Swift Package ではファイルを置くだけでなく resource として明示する必要がある。不正な manifest は App Store Connect の提出拒否につながる。[^S03][^S14]

**設計への示唆：** 最初のローカル CRUD・呼び出し検証に、アカウントや分析 SDK を必須にしない。Apple は重要なアカウント機能がなければログインなしで利用可能にすることを求め、アカウント作成を提供するならアプリ内のアカウント削除も求める。[^S01] クラウド同期や外部 AI によるスニペット加工は、データフロー・同意・保存・削除を再評価してから検討する。第三者 AI への個人データ共有にも明示的な説明と許可の要件がある。[^S01]

**未確認：** nibble が実際に使う required reason API の種類と理由コード、採用 SDK の manifest、診断・同期を含めた最終的な App Privacy 回答。API をまだ実装していない段階で完成済みとは扱わない。

## 5. 開発環境とテストの責務

### 確認した事実

XCTest の現行資料は、新しい単体テストに Swift Testing の使用を検討し、UI と performance test には XCTest を継続利用するよう案内している。両者を同一 target に置けるが、1つのテスト内で API を混ぜない。WWDC24 の説明では Swift Testing は Linux を含む複数プラットフォームを対象とする。これは iOS の UI / SDK テストが Linux で可能になるという意味ではない。[^S07][^S08]

Xcode のアプリ依存では、解決した Git commit とバイナリ依存の checksum を含む `Package.resolved` を Git に含め、チーム内で同じ解決結果を使うよう案内されている。[^S11]

### nibble の開発ルールへの対応

以下の責務は [CONTRIBUTING.md](../CONTRIBUTING.md) で既に決定済み。今回の調査で新しい CI やテストを実装したものではない。

| 検証対象 | 担当 | 将来追加する条件 |
| --- | --- | --- |
| workflow 方針・構文・Nix 書式 | Ubuntu CI とローカルで `nix flake check` | 現在の flake / lock を使用 |
| 純粋なデータ処理・移行ロジック | まずローカル。Apple SDK から独立した部分のみ将来 Linux も検討 | 実際に portable な module とテストができてから導入 |
| アプリ・extension の build、署名、SDK 統合 | ローカル Mac / Xcode | 本体・extension の各 target と共有コードを確認 |
| UI・性能・権限・OS連携 | Simulator と実機。性能の基準は実機の Release 構成 | 実際の導線、最低対応 OS、最新正式版、データ量を記録 |
| 配布物・復元・更新 | ローカルで archive、TestFlight で確認 | 既存データからの更新、移行、権限拒否の検証 |

**設計への示唆：** Xcode の版、SDK、Swift language mode、deployment target、scheme、端末 / runtime、データセットを記録する。補助ツールを固定する `flake.lock` と、アプリ依存の `Package.resolved` を混同しない。証明書・署名鍵・実スニペットを公開 Git / CI ログへ入れない。プロジェクト生成ツールや追加 lint ツールは、必要性と保守コストを確認してから Nix 管理へ追加する。

## 6. ベータ配布から公開後まで

### 確認した事実

Xcode は archive を作り、Organizer から Validate App、TestFlight / App Store への配布・署名処理を行う。Validate App は限定的な自動初期検証であり、審査や実機試験の代替ではない。診断用 symbol のアップロードも配布設定に含まれる。[^S15]

TestFlight はテスター・ビルド・フィードバックを管理できる。ビルドは最長90日利用でき、外部テスターへの配布には review が必要になる場合がある。最初に group に追加するビルドは review に送られる。公開リポジトリの外部投稿禁止と、招待した利用者によるベータテストは別の運用判断である。[^S09]

調査時点の Upcoming Requirements は、2026-04-28 以降の App Store Connect アップロードに Xcode 26 以降と iOS 26 等の SDK を要求している。**SDK の提出条件とアプリの最低対応 OS は別**であり、nibble の deployment target 26.0 はプロジェクトの方針として扱う。提出直前に最新の要件を再確認する。[^S16]

### 設計への示唆

1. **最初の配布前：** bundle ID・App Group・署名・privacy manifest・ポリシー URL・対応 OS・保存移行を確認する。キーボード等の初期設定と制約をレビュー担当者へ説明できる状態にする。
2. **ベータ：** 少数の協力者に実際の貼り付け先で使ってもらい、呼び出し成功率、操作数、遅延、保存失敗、権限拒否からの復帰を記録する。テスト用テキストを使い、個人の入力内容の収集を前提にしない。
3. **更新：** 古い保存データからの移行と export / import を先に確認する。アプリの版だけ戻せば DB も戻ると考えず、スキーマ変更とデータ復旧の手順を組にする。
4. **公開後：** App Store / TestFlight の診断と、必要性を検討した最小限のアプリ計測を使う。問い合わせのためだけに全員の本文を収集する設計を避ける。

課金は未決定。導入する場合は Guideline 3.1 の現行条件と提供地域を確認する。買い切り / subscription / 無料の選択は、同期等の継続費用とユーザーへの継続価値を見積もってから行う。[^S01]

## 7. 公開コードとライセンス

GitHub が運営する Choose a License は、license を付けないコードは既定の著作権の対象であり、Public repository にすることで GitHub の規約に基づく閲覧・fork 等の権利は生じるが、一般的な再配布・変更許諾とは別だと説明している。[^S10]

**設計への示唆：** nibble のコード公開、外部 contribution の受付、アプリの配布、コードの再利用許諾を別々に決める。第三者依存を採用する際はその license と配布時の通知義務を確認する。この調査では新しい license や contribution 受付方針を追加しない。

## 実装前に解消する問い

- 「機密スニペット」を機能として扱うか。扱うならロック画面・検索・キーボード・export を含め、何を保護できると説明するか。
- Full Access なしで利用できるキーボードの最小機能は何か。編集・保存の権限がない場合にも価値を提供できるか。
- 同期・アカウント・分析を最初から必要とする利用シーンはあるか。
- 最初の配布形態、問い合わせ先、ポリシー URL、復元手段を誰が保守するか。
- App Store 審査の要件、提出 SDK、Privacy Manifest の対象一覧をリリース時に誰が更新確認するか。

## 出典台帳

下記は一次情報。DocC は Apple が配信する JSON 本文を読み、リンクは通常の文書ページに戻している。HTML 文書は記載した関連節を読解した。動画は録画を視聴したという意味ではなく、公開 transcript を読んだ。URL を知っているだけの資料は根拠に含めていない。

[^S01]: Apple, **App Review Guidelines**, 現行版、確認 2026-09-13。[本文](https://developer.apple.com/app-store/review/guidelines/)。閲読：2.5.1–2.5.2、2.5.16、3.1、4.4–4.4.1、5.1.1–5.1.2 の関連節。審査の個別結果や将来の改定は保証しない。
[^S02]: Apple, **App privacy details on the App Store**, 現行版、確認 2026-09-13。[本文](https://developer.apple.com/app-store/app-privacy-details/)。閲読：Data collection、第三者 SDK、Privacy policy、Additional guidance の on-device / CloudKit / diagnostics の関連説明。個別アプリの最終回答を確定する資料ではない。
[^S03]: Apple, **Privacy manifest files**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)。閲読：概要、ファイル名、target resources、各キーの説明。
[^S04]: Apple, **Keychain services**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/security/keychain-services)。閲読：Overview。一般スニペット全件を Keychain に保存すべきという推奨ではない。
[^S05]: Apple, **kSecAttrAccessibleWhenUnlockedThisDeviceOnly**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)。閲読：属性の説明・移行制約。実装時には用途に応じた他の属性と比較する。
[^S06]: Apple, **Apple Platform Security — Data Protection overview**, 公開日 2026-08-03。[本文](https://support.apple.com/guide/security/data-protection-overview-secf6276da8a/web)。閲読：Implementation。macOS 固有の記述を iPhone へそのまま適用しない。
[^S07]: Apple, **XCTest**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/xctest)。閲読：Overview の Swift Testing / UI / performance の使い分け。
[^S08]: Stuart Montgomery / Apple, **Meet Swift Testing**, WWDC24, 2024。[動画・transcript](https://developer.apple.com/videos/play/wwdc2024/10179/)。閲読：17:35 以降の XCTest との関係と open source / cross-platform の説明。UI・性能計測の現行可否は S07 と照合。
[^S09]: Apple, **TestFlight overview**, 現行 App Store Connect Help、確認 2026-09-13。[本文](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。閲読：upload、invite、test、feedback、finish testing。提出時の具体的な審査要否は App Store Connect で確認する。
[^S10]: GitHub / Choose a License, **No License**, 確認 2026-09-13。[本文](https://choosealicense.com/no-permission/)。閲読：license がない場合と GitHub 公開時の権利の説明。個別依存の license 文そのものは採用時に別途読む。
[^S11]: Apple, **Adding package dependencies to your app**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)。閲読：要件指定と Coordinate package versions across your team。Xcode のアプリ依存が対象。
[^S12]: Apple, **Describing use of required reason API**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。閲読：Overview、bundle ごとの宣言、承認された理由、更新方針。各理由コードの選択は未実施。
[^S13]: Apple, **Apple Platform Security — Data Protection classes**, 公開日 2024-12-19。[本文](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)。閲読：Class A–D、Protected Until First User Authentication。実機での nibble の保存属性は未確認。
[^S14]: Apple, **Adding a privacy manifest to your app or third-party SDK**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)。閲読：manifest validation、app / framework / Swift Package の配置。最終 archive の検査は未実施。
[^S15]: Apple, **Distributing your app for beta testing and releases**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)。閲読：archive、Validate App、distribution、signing、symbols、beta / App Store の関連節。配布操作はしていない。
[^S16]: Apple, **Upcoming Requirements**, 確認 2026-09-13。[本文](https://developer.apple.com/news/upcoming-requirements/)。閲読：SDK minimum requirements（2026-04-28 以降）。提出時には再確認する。
[^S17]: Apple, **Generating Log Messages from Your Code**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)。閲読：Redact Sensitive User Data from a Log Message。システム側の伏字機能だけで安全と判断しない。
[^S18]: Apple, **Preparing your UI to run in the background**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background)。閲読：deactivation、resource release、app snapshot、background events。SwiftUI 実装への適用と遷移タイミングは実機検証が必要。
