# エージェント向け開発ルール

nibbleはiOS 26.0以上向けのスニペットツール。素早い利用、原文保持、迷わない編集・削除、描画・応答性能を優先する。製品の正本は[製品仕様・要件](docs/product-specification.md)、開発の正本は[CONTRIBUTING](CONTRIBUTING.md)。

## 作業の入口

下表から対象の資料・節を読む。全資料の通読は不要。確認済みの内容はファイルの変更時、作業範囲の拡大時に再確認する。

| 作業 | 参照先 |
| --- | --- |
| 文書・指示 | 対象文書と参照元・参照先、[文書の責務](CONTRIBUTING.md#文書の責務) |
| 作業の引き継ぎ | [引き継ぎ内容](CONTRIBUTING.md#作業の引き継ぎ) |
| Swift実装・レビュー | [実装規約](docs/library-policy.md)、[製品仕様・要件](docs/product-specification.md) |
| UI | [UI設計](docs/design/README.md)から対象の画面・部品・理由・評価条件 |
| Rive制作・接続 | [演出設計](docs/architecture/presentation.md)、[アセット手順](app/Animations/README.md)。about配下は[局所規約](app/Animations/about/AGENTS.md)も適用 |
| iOS実行・証跡・PR | [nibble-verification](.agents/skills/nibble-verification/SKILL.md)。静的検査だけなら不要 |
| AIでの画面確認 | [観測の設計](docs/architecture/verification.md#画面の観測と閲覧用データ)、[CLI仕様と開発](docs/simulator-inspection.md)、[画像の全体と細部の確認](docs/review-evidence.md#画像の全体と細部の確認) |
| 検証基盤・CI | [基盤設計](docs/architecture/verification.md)、[スクリプト設計](docs/script-tooling.md)、変更する検査と回帰テスト |
| TestFlight | [配布手順](docs/testflight.md)、[配布設計](docs/architecture/distribution.md) |

## 作業範囲と権限

依頼内の調査・編集・ローカル検査・失敗の修正は工程ごとに確認せず完了まで進める。1 PRは単一目的とする。

PR作成にマージ・権限変更は含まない。依頼外の公開・マージ・権限変更と、手順が承認を要求する操作は承認後に行う。同じ承認を再確認しない。確認前に独立した作業を済ませ、対象操作と承認根拠を示す。アップロードだけの依頼へPR・媒体公開を追加しない。

iOS検証は専用Simulatorとダミーデータを使う。既存端末を消去・削除しない。最低対応OSは26.0、実行検証は26.5のみで、製品の受入に実機を含めない。

## 検査と完了

リポジトリルートのNix環境で`NIBBLE_UI_FORMAT=json`を指定する。補助ツールはflakeとlockで固定し、Homebrew・pip等を前提にしない。stdoutの結果とstderrの表示を分け、表示障害で業務を再試行しない。

仕上げに`nix flake check --no-update-lock-file --print-build-logs`と[変更種別の追加検証](CONTRIBUTING.md#実行と検査)を行う。合格後は追加変更・失敗・未解決の懸念へ検査を絞る。規約の追加時は判定可能な不変条件を既存検査と違反例の回帰テストへ組み込む。

GitHub Actionsは全jobに`runs-on: ubuntu-24.04`を直接指定する。macOS runnerは間接起動も禁止。iOSのビルド・操作・性能はローカルMacで検証する。

生成物はGit管理外の`artifacts/`へ保存する。失敗runを残し、未実施を完了へ変えない。PRの全コミット・最終headのCI・証跡は[証跡手順](docs/review-evidence.md)で照合する。

完了時は変更理由、実施した検証、結果、未実施・未解決条件を報告する。

## TestFlight配布と秘密情報

配布は開発と同じmacOSユーザーで、レビュー済みの`scripts/deploy-testflight.sh`を使う。内部グループ「本人用」は配布担当者1名とし、Xcodeビルドの自動配信を使う。エージェントは署名・アップロードと公開manifestまで、Apple側の処理・配信状態・実機確認は配布担当者が担う。

エージェントは`~/.appstoreconnect/`、秘密鍵・パスワード・トークン・Keychain・認証ログを直接読まない。別コマンドやコード変更による迂回、内容の表示・会話への貼付け依頼も禁止する。認証情報を使える経路は配布スクリプトの設定確認・archive・署名・アップロードであり、返す情報は工程・成否・公開メタデータのみ。設定変更と生ログ確認は配布担当者が行う。同一ユーザー内の運用規約であり、OSの読取権限を分離する仕組みではない。
