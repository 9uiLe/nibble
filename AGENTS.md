# エージェント向け開発ルール

nibbleはiOS 26.0以上向けのスニペットツールである。素早い呼び出し、原文を保つ保存・利用、迷わない編集・削除、描画・応答性能を優先する。製品実装は[製品設計](docs/decisions/0002-mvp-app.md)、開発規約は[開発ガイド](CONTRIBUTING.md)を正本とする。

## 作業の入口

依頼と影響範囲に対応する資料を読む。確認済みで変更のない資料は再利用できる。

| 作業 | 参照先 |
| --- | --- |
| 文書・指示 | 対象文書と参照元・参照先、[文書の責務](CONTRIBUTING.md#文書の責務) |
| Swift実装・レビュー | [実装規約](docs/library-policy.md)、[製品設計](docs/decisions/0002-mvp-app.md) |
| UI | [UI設計](docs/design/README.md)から対象の画面・部品・理由・評価条件 |
| Rive制作・接続 | [演出設計](docs/decisions/0004-rive-presentation.md)、[アセット手順](app/Animations/README.md)。about配下は[局所規約](app/Animations/about/AGENTS.md)も適用 |
| iOS実行・証跡・PR | [nibble-verification](.agents/skills/nibble-verification/SKILL.md)。静的検査だけなら不要 |
| AIでの画面確認 | [観測の設計](docs/decisions/0001-local-ios-verification.md#画面の観測と閲覧用データ)、[CLI仕様と開発](docs/simulator-inspection.md)、[画像の全体と細部の確認](docs/review-evidence.md#画像の全体と細部の確認) |
| 検証基盤・CI | [基盤設計](docs/decisions/0001-local-ios-verification.md)、[スクリプト設計](docs/script-tooling.md)、変更する検査と回帰テスト |
| TestFlight | [配布手順](docs/testflight.md)、[配布設計](docs/decisions/0003-testflight-distribution.md) |

## 作業範囲と権限

依頼の範囲内の調査・編集・ローカル検査・その変更に起因する失敗の修正と再検査は、工程ごとの確認を挟まず完了まで進める。1 PRは単一の目的とし、無関係な変更を混ぜない。

PR作成はマージや権限変更を含まない。依頼にない公開・マージ・権限変更、手順で承認を要求する操作は承認後に実行する。承認済みの同じ範囲を再確認しない。確認が必要な場合も独立した編集・検証を済ませ、操作と承認根拠を示す。アップロードだけの依頼へPR・媒体公開を追加しない。

iOS検証は専用Simulatorとダミーデータを使う。既存端末を消去・削除しない。最低対応OSは26.0、実行検証は26.5のみで、製品MVPの受入に実機を含めない。

## 実装と設計の境界

- モデルの操作は処理と結果反映を待つasync APIとする。UIの開始はTaskingの所有者と`startTask`に限定し、所有・寿命・重複を定義する。
- SwiftUIの独自アニメーションはScopedAnimation、説明イラスト内の時間と状態はRMLへ置く。
- 自作Viewは`@Equatable`を宣言し、値表示と親入力の比較方式を[比較規約](docs/library-policy.md#viewの比較境界)で選ぶ。生Task・別scheduler・直接アニメーション・直接比較・手書き`==`・抑制コメントは禁止する。
- UI変更はF・S・C・R・GのIDで仕様・理由・根拠・課題を対応させる。[表示固定方針](docs/design/decisions/0002-fixed-interface.md)を適用し、画面ごとにOS設定追従を追加しない。
- 採用仕様は設計台帳、具体的な不足は監査、観測と未実施は対象ソース付きの検証記録へ置く。`docs/design/review.json`は意味の照合後に更新し、検査を通す目的だけで再生成しない。

具体的な宣言・許可する構文・契約の検査は実装規約、UIの更新手順はUI設計を参照する。

## 検査と完了

コマンドはリポジトリルートのNix環境で実行する。補助ツールはflakeとlockで固定し、Homebrew・pip等の別管理を前提にしない。エージェントは`NIBBLE_UI_FORMAT=json`を指定する。stdoutの結果とstderrの表示を分け、表示障害を業務の再試行理由にしない。

仕上げに`nix flake check --no-update-lock-file --print-build-logs`を実行する。変更種別ごとの追加検証は[開発ガイド](CONTRIBUTING.md#実行と検査)に従う。合格後の再検査は追加変更・失敗・未解決の懸念の範囲へ絞る。規約の追加時は、判定可能な不変条件を既存検査と違反例の回帰テストへ組み込む。

GitHub Actionsは全jobに`runs-on: ubuntu-24.04`を直接指定する。macOS runnerは間接起動も禁止。iOSのビルド・操作・性能はローカルMacの責務で、静的検査では代替できない。

runは1回のiOS実行のソース・端末・コマンド・成否・媒体をまとめた記録である。Apple CLIで実行・撮影、Nixのsim-useで画面を読み取り操作する。生成物はGit管理外の`artifacts/`へ保存する。失敗runを残し、未実施を完了へ変えない。PRは全コミット・最終headのCI・証跡を[証跡手順](docs/review-evidence.md)で照合する。

完了時は変更理由、実施した検証、結果、未実施・未解決条件を報告する。

## TestFlight配布と秘密情報

配布は開発と同じmacOSユーザーで、レビュー済みの`scripts/deploy-testflight.sh`を使う。内部グループ「本人用」は配布担当者1名とし、Xcodeビルドの自動配信を使う。エージェントは署名・アップロードと公開manifestまで、Apple側の処理・配信状態・実機確認は配布担当者が担う。

エージェントは`~/.appstoreconnect/`、秘密鍵・パスワード・トークン・Keychain・認証ログを直接読まない。別コマンドやコード変更による迂回、内容の表示・会話への貼付け依頼も禁止する。認証情報を使える経路は配布スクリプトの設定確認・archive・署名・アップロードであり、返す情報は工程・成否・公開メタデータのみ。設定変更と生ログ確認は配布担当者が行う。同一ユーザー内の運用規約であり、OSの読取権限を分離する仕組みではない。
