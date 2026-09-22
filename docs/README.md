# nibbleの設計と開発資料

nibbleは、端末内に保存した文章やURLを探し、コピーまたはキーボードで再利用するiOSアプリです。入力途中の下書きと利用する保存済み項目を分け、原文を保持します。

## 資料の選び方

初めて参加するときは[README](../README.md)で基本操作とセットアップを確認する。作業を始めるときは[開発ガイド](../CONTRIBUTING.md#作業の進め方)から、変更対象に対応する正本と検査を選ぶ。各文書の責務は下表に示す。確認済みの資料は、内容の変更または作業範囲の拡大に応じて再確認する。

## 文書の責務

| 場所 | 定義する内容 |
| --- | --- |
| [製品仕様](product-specification.md) | 目的、要件、原文・保存・操作・回復の契約 |
| [architecture](architecture/README.md) | 構成、責務、依存、OSと保存層の境界 |
| [design](design/README.md) | 画面、部品、文字・色・配置・通知、評価課題 |
| [library-policy.md](library-policy.md) | Swift、タスク所有、View比較、ライブラリの規約 |
| [Rive描画基盤](../runtime/rive/README.md) | ネイティブ描画のスレッド・寿命、固定入力とビルド |
| [testing.md](testing.md) | 保証を置く場所、回帰の選択、未確認条件 |
| [ios-verification.md](ios-verification.md) | ローカルでビルド・テスト・実操作するコマンド |
| [review-evidence.md](review-evidence.md) | ソース・実行・画像・録画・レビューの照合 |
| [script-tooling.md](script-tooling.md) | CLIの入出力、表示、失敗処理 |
| [performance-verification.md](performance-verification.md) | 性能測定の条件、補助予算、適用限界 |
| [testflight.md](testflight.md) | 署名・アップロード、配布担当者の確認、秘密情報 |
| [reference](reference/README.md) | 外部仕様・一次資料の確認範囲と適用限界 |

採用仕様、外部資料、未解決の評価課題、実行結果は異なる情報です。設計の定義は上表の文書に置き、特定ソースの成否・画面・測定値はGit管理外の`artifacts/`へ記録します。検査コマンドの存在や設計台帳の記載は、あるビルドで検証を完了したという申告ではありません。
