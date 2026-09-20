# データ保護と公開の条件

製品は端末内のSQLiteへ本文を保存し、同期・アカウント・分析を提供しない。[製品仕様・要件](../docs/product-specification.md)と[TestFlight手順](../docs/testflight.md)が実装と配布の正本である。以下の外部要件は2026-09-13に確認した判断材料で、提出時の最新要件や審査結果の保証ではない。

## データの露出と復旧

通常のスニペットは秘密情報専用の保管庫ではない。コピー、共有元・入力先、アプリ切替画面、ログは別々の露出経路である。検証・画像・ログにはダミーデータを使い、本文や認証値を診断へ出さない。Data Protectionの指定があることと実機のロック中に読めないことは別で、Simulatorでは実機の暗号化・再ロック後の挙動を確認できない。[^S06][^S13][^S17][^S18]

共有DBの読み取り・移行に失敗した場合は元ストアを残す。画面から削除したことをバックアップやペースト先も含む完全消去とは説明しない。配布用の秘密情報と生ログはリポジトリ外で担当者が管理し、エージェントは配布コマンドの公開結果だけを読む。

## Keyboardの公開条件

確認したApp Review Guidelines 4.4.1は、入力機能、次のキーボードへの切り替え、Full Accessやネットワークなしでの機能を求め、Settings以外の別アプリ起動を禁止する。[^S01] このため、製品は権限なしの挿入を基礎にし、本体を開く編集ボタンをKeyboardへ置かない。スニペット挿入に限定した構成が審査で受理されるかは未確認。

## プライバシーの3つの成果物

| 成果物 | 確認する内容 |
| --- | --- |
| プライバシーポリシー | 実際の収集・共有・保持・削除とアプリ内/ストアの参照先 [^S01] |
| App Privacy回答 | 自分と第三者SDKのデータフロー。端末内処理と外部への収集を区別 [^S02] |
| Privacy Manifest | 各bundleの使用API・理由・収集・tracking、SDKとSwift Packageのresource配置 [^S03][^S12][^S14] |

RiveRuntimeを含む第三者依存を採用している。SDKの存在だけから収集の有無を決めず、完成したarchiveと実際のAPI・通信・用途を点検する。manifestファイルがあるだけではApp Privacy回答やプライバシーポリシーの確認を代替できない。最終archiveの用途と理由コード、採用SDKの申告、公開時の回答・ポリシーの整合は未確認で、公開担当者が提出前に確認する。

## 7. 公開コードとライセンス

GitHub が運営する Choose a License は、license を付けないコードは既定の著作権の対象であり、Public repository にすることで GitHub の規約に基づく閲覧・fork 等の権利は生じるが、一般的な再配布・変更許諾とは別だと説明している。[^S10]

nibbleのリポジトリはコード公開用とし、外部からの投稿は受け付けない。[開発ガイド](../CONTRIBUTING.md#コード公開の運用) の方針に従ってGitHubの権限を管理する。Public repositoryでの閲覧・fork等と、コードの一般的な再利用許諾は区別する。[^S10]

第三者依存の採用時は、ライセンスと配布時の通知義務を確認する。[ThirdPartyNotices](../app/Shared/ThirdPartyNotices.txt)のMIT許諾文は著作権表示・許諾文の保持を要求するため、全文を維持する。製品の配布方法とコードの再利用許諾は、それぞれの条件を明示して判断する。


## 出典

[^S01]: Apple, **App Review Guidelines**, 現行版、確認 2026-09-13。[本文](https://developer.apple.com/app-store/review/guidelines/)。閲読：2.5.1–2.5.2、2.5.16、3.1、4.4–4.4.1、5.1.1–5.1.2 の関連節。審査の個別結果や将来の改定は保証しない。
[^S02]: Apple, **App privacy details on the App Store**, 現行版、確認 2026-09-13。[本文](https://developer.apple.com/app-store/app-privacy-details/)。閲読：Data collection、第三者 SDK、Privacy policy、Additional guidance の on-device / CloudKit / diagnostics の関連説明。個別アプリの最終回答を確定する資料ではない。
[^S03]: Apple, **Privacy manifest files**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)。閲読：概要、ファイル名、target resources、各キーの説明。
[^S06]: Apple, **Apple Platform Security — Data Protection overview**, 公開日 2026-08-03。[本文](https://support.apple.com/guide/security/data-protection-overview-secf6276da8a/web)。閲読：Implementation。macOS 固有の記述を iPhone へそのまま適用しない。
[^S10]: GitHub / Choose a License, **No License**, 確認 2026-09-13。[本文](https://choosealicense.com/no-permission/)。閲読：license がない場合と GitHub 公開時の権利の説明。個別依存の license 文そのものは採用時に別途読む。
[^S12]: Apple, **Describing use of required reason API**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。閲読：Overview、bundle ごとの宣言、承認された理由、更新方針。各理由コードの選択は未実施。
[^S13]: Apple, **Apple Platform Security — Data Protection classes**, 公開日 2024-12-19。[本文](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)。閲読：Class A–D、Protected Until First User Authentication。実機での nibble の保存属性は未確認。
[^S14]: Apple, **Adding a privacy manifest to your app or third-party SDK**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)。閲読：manifest validation、app / framework / Swift Package の配置。製品の署名済みarchiveの検査は未実施。研究用のunsigned archiveはE19に記録する。
[^S17]: Apple, **Generating Log Messages from Your Code**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code)。閲読：Redact Sensitive User Data from a Log Message。システム側の伏字機能だけで安全と判断しない。
[^S18]: Apple, **Preparing your UI to run in the background**, 現行 DocC、確認 2026-09-13。[本文](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background)。閲読：deactivation、resource release、app snapshot、background events。SwiftUI 実装への適用と遷移タイミングは実機検証が必要。
