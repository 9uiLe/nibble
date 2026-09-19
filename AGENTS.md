# エージェント向け開発ルール

作業前に[開発ガイド](CONTRIBUTING.md)を読む。このファイルは判断基準と作業の入口を定義する。規約の詳細は開発ガイド、実装上の契約は[ライブラリ規約](docs/library-policy.md)、実行・証跡・CI・レビューの責務は[検証基盤の設計](docs/decisions/0001-local-ios-verification.md)を正とする。

## プロダクトの判断基準

- nibbleはiOS 26.0以上向けのスニペットツール。素早い呼び出し、迷わない作成・編集・削除、シンプルさ、描画・応答性能を優先する。
- 1 PRは単一の目的とし、無関係なリファクタリング・依存更新を混ぜない。
- 本体とextensionのdeployment targetは26.0。実行検証はiOS 26.5のみ、MVPでは実機検証を含めない。
- 技術はOS/API制約、性能、保守・運用、移行容易性で選ぶ。研究の候補を採用済みと扱わない。

## UIの設計判断

[nibbleのUI設計](docs/design/README.md)に従い、画面・部品の目的、構成、配置理由、代替案、評価条件を定義する。共通原則・画面・部品・根拠・監査課題はIDで対応させる。外部指針、製品判断、仮説、観測は区別して記録する。

- 採用する仕様と設計理由は製品の台帳、対象実装の不足と改善候補は監査、実験条件と結果は検証記録へ置く。
- [共通ツールキット](tools/ui-design/README.md)は設計手順・ひな形・照合処理を所有する。nibble固有の仕様と検査範囲は製品側に置き、共通Moduleから製品コードやパスを参照しない。
- `docs/design/policy.json`が検査範囲を定め、`check_docs.py`が文書・設計IDと未確認変更を検査する。理由の妥当性と網羅性はレビュー、動作と見た目はローカルiOS検証で確認する。
- 実装と設計を照合した結果を、判断要約と確認文書付きで`docs/design/review.json`へ記録する。照合記録は確認後に更新し、検査を通す目的だけで再生成しない。

文字サイズ・太字・コントラスト・独自演出は[製品の表示方針](docs/design/decisions/0002-fixed-interface.md)に従い固定する。OS設定への追従を画面ごとに追加しない。

## 実装の責務

| 対象 | 契約 |
| --- | --- |
| モデルの操作 | 受理した処理と結果反映を完了まで待つ`async` API。同期メソッド・setterの隠れた開始や、タスク開始直後に戻る操作APIは禁止 |
| UIのタスク所有 | `startTask`の境界とswift-taskingの`ViewTaskStore` / `TaskSlot`で、所有者・寿命・重複方針を定義 |
| アニメーション | SwiftUIの表示変化はswift-scoped-animationの`AnimationScope` / `animationBarrier`、説明イラスト内の時間と状態はRMLで定義 |
| Viewの比較 | 自作Viewは`@Equatable`を宣言。値表示は`@MainActor EquatableBodyView`で全入力を比較。親入力を持つ通常のViewは生成ごとの比較用UUID（`inputRevision`）で接続先の差し替えを反映。状態の寿命はSwiftUIのidentityで管理 |

生のTask生成・別scheduler・直接アニメーション・直接比較ゲート・手書き`==`は禁止。`@SkipEquatable`は、同じViewで`inputRevision`を比較する不変`let`の親入力に限る。具体的な宣言と適用範囲は[Viewの比較規約](docs/library-policy.md#viewの比較境界)に従う。構造化されたasync/await・task group・SwiftUI `.task`・協調用Task API、値型・enumの標準Equatable合成は許可する。抑制コメントを使わず、依存はexact versionと共有`Package.resolved`で固定する。

操作テストはAPIを直接awaitし、戻った時点の状態・永続化を検査する。重複・キャンセルは所有者を検査し、Viewは入力の変更・復元と、同一入力での環境更新を検査する。構文Lint、compiler、テスト、画面の確認にはそれぞれ異なる保証範囲がある。

説明イラストは[演出設計](docs/decisions/0004-rive-presentation.md)に従う。RivePresentationが読み込みと表示、ホストがSessionの寿命・配色・再生方針・説明文、RMLが図形と演出を所有する。制作ソース、生成済み`.riv`、manifestを一組で管理し、[アセット手順](app/Animations/README.md)で再生成と検証を行う。

## 機械検査とマージ条件

補助ツールは`flake.nix`と`flake.lock`で固定する。ローカルとCIで同じlockを使い、Homebrew・pip等による別管理を前提にしない。1回の検証実行をrunと呼び、対象ソース・端末・コマンド・成否・媒体をひとまとまりの記録として扱う。

| 検査 | コマンド・入口 |
| --- | --- |
| 共通の静的検査・回帰テスト | `nix flake check --no-update-lock-file --print-build-logs` |
| Swiftの禁止API・開始・比較境界 | `scripts/check_swift_policy.py`。本体・拡張・テスト・研究・基盤用Swiftを検査 |
| 文書リンク・Skill・Swift例・UI設計のIDと未確認変更 | `scripts/check_docs.py`。共通検査の`documentation`に含む |
| iOSの端末・成否・実行中のソース変化 | `scripts/ios.py`。専用UDIDとiOS 26.5を要求し、開始・終了時のファイルを照合 |
| runとコミット、媒体、レビュー申告の一致 | `scripts/check_evidence.py`。使用方法は[証跡とPRの検査](docs/review-evidence.md) |
| PR本文と実際の全コミット | `scripts/check_pr.py`。PRイベントのCIでも検査し、本文編集で再実行 |

スクリプトの進捗・結果は[共通表示Adapter](docs/script-tooling.md)からhamioへ渡す。エージェントは`NIBBLE_UI_FORMAT=json`を指定し、stdoutの結果データとstderrの表示を分ける。表示障害を業務の再試行理由にせず、秘密情報・生ログをAdapterへ渡さない。

規約の追加時は、判定できる不変条件を既存の検査へ組み込み、違反例を拒否する回帰テストを用意する。構文やファイル配置だけでは判断できない事項を、自動検査済みと報告しない。

GitHub Actionsの各ジョブは`runs-on: ubuntu-24.04`を直接指定する。macOS runnerはself-hosted・再利用workflow・別ジョブの間接起動を含め禁止。iOSのビルド・テスト・UI/UX・性能はローカルMacの責務であり、クラウド静的検査で代替しない。

mainの[ruleset](.github/main-ruleset.json)はGitHub Actionsの`workflow-policy`成功とbaseへの追従を必須とし、バイパスを設けない。宣言JSONだけではGitHub設定は変わらないため、ジョブ名やマージ条件の変更時は宣言と[実効ルール](docs/review-evidence.md#githubの必須チェック)をそろえる。

## 検証対象と参照先

| 対象 | 責務 | 設定と手順 |
| --- | --- | --- |
| `Nibble` / `NibbleShare` / `NibbleKeyboard` | 製品MVPのデータ・画面・操作 | `app/project.json`、[製品手順](docs/mvp.md) |
| `VerificationApp` | 入力・操作・テスト・撮影の成立を試験するfixture | `validation/project.json`、[共通手順](docs/ios-verification.md) |
| `ResearchProbe` | 保存・検索・復旧・UI・OS連携の比較実験 | `validation/research-project.json`、[研究手順](validation/RESEARCH.md) |

製品は`app/Nibble.xcodeproj`、shared schemeは`Nibble`。基盤・研究用は`validation/<対象名>.xcodeproj`と同名scheme。`ios.py smoke`はVerificationApp専用、研究の画面操作は`validation/check-research-ui.py`を使う。

製品の採用構成は[製品設計](docs/decisions/0002-mvp-app.md)、追加の判断は[研究と検証計画](research/README.md)、共通基盤の責務は[基盤設計](docs/decisions/0001-local-ios-verification.md)を参照する。新しいtargetには設定・手順・期待結果を用意する。

## TestFlight配布と秘密情報

[TestFlight手順](docs/testflight.md)に従い、開発と同じmacOSユーザーで`scripts/deploy-testflight.sh`を実行する。配布先は、Apple Developerアカウントと端末を管理する配布担当者1名を登録した内部グループ「本人用」。App Store ConnectでXcodeビルドの自動配信を有効にする。

エージェントの配布作業は、署名・アップロードの成功と公開manifestの確認までとする。Apple側の処理完了・グループへの配信状態・実機での確認は配布担当者が行う。通常の配布依頼では、エージェントによる配信状態のブラウザー確認や、そのためのサインイン依頼は不要。

認証設定とAPI鍵はリポジトリ外の`~/.appstoreconnect/`で配布担当者が管理する。エージェントはこのディレクトリ・秘密鍵・パスワード・トークン・Keychain・認証ログを直接読まず、内容の表示や会話への貼り付けも依頼しない。別コマンドやコード変更で直接参照の禁止を迂回しない。

認証情報を使用できる経路は、レビューした配布スクリプトによる設定確認・archive・署名・アップロード。エージェントへ返すのは工程・成否・公開メタデータのみ。設定の登録・変更と生ログの確認は配布担当者が行う。これは同一ユーザー内の運用規約であり、OSの読取権限を分離しない。Claude Codeのdeny設定も補助として扱う。詳細は[配布設計](docs/decisions/0003-testflight-distribution.md)を参照する。

## 検証とPRの進め方

ローカルiOS検証・証跡整理・PR作成や更新では、共有Skill [nibble-verification](.agents/skills/nibble-verification/SKILL.md)を読む。Apple CLIでビルド・実行管理・撮影し、Nixのsim-useで画面を読み取り操作する。生成物はGit管理対象外の`artifacts/`へ保存する。

- UI/UXの変更は画像、操作・遷移・応答の変更は録画でも確認する。対象コミット・端末・OS・手順を記録し、画像・動画をPRへ添付する。
- 自動実行の成功、動画デコード、抽出フレームの確認、全編再生、アップロード、ブラウザーでの閲覧を区別する。観測と閲覧条件は`review.json`に記載し、証跡検査後の`REVIEW.md`を共有に使う。未実施を完了へ変えない。
- PRは目的・背景、アウトカム、全コミット表、画像・動画、検証結果を記載する。対象外も理由付きで欄を残し、追加コミットと本文を照合する。
- 検証結果の再利用はファイル照合で判断し、コミット名やcacheの存在から推定しない。失敗runは保存し、最終headのCIと閲覧可能な証跡を確認する。
- 設計資料は新規参加者へ向け、目的・構成・責務・契約・制約を定義する。用語と判断理由は文書内で説明し、実験条件・観測・失敗・未実施の記録は対象ソースを明記した検証文書に置く。
