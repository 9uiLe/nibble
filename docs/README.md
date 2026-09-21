# nibbleの設計と開発資料

nibbleは、端末内に保存した文章やURLを探し、コピーまたはキーボードで再利用するiOSアプリです。入力途中の下書きと利用する保存済み項目を分け、原文を保持します。

## 読む順序

1. [README](../README.md)で基本操作とセットアップを確認する。
2. [製品仕様・要件](product-specification.md)で提供範囲、データの意味、操作の成立条件を理解する。
3. [アーキテクチャ](architecture/README.md)で入口、依存関係、コードの配置を確認する。
4. [UI設計](design/README.md)で画面・部品・表示規則と設計理由を確認する。
5. [開発ガイド](../CONTRIBUTING.md)から変更対象に必要な規約と検査へ進む。

## 文書の責務

| 場所 | 定義する内容 |
| --- | --- |
| [製品仕様](product-specification.md) | 目的、要件、原文・保存・操作・回復の契約 |
| [architecture](architecture/README.md) | 構成、責務、依存、OSと保存層の境界 |
| [design](design/README.md) | 画面、部品、文字・色・配置・通知、評価課題 |
| [library-policy.md](library-policy.md) | Swift、タスク所有、View比較、ライブラリの規約 |
| [testing.md](testing.md) | 保証を置く場所、回帰の選択、未確認条件 |
| [ios-verification.md](ios-verification.md) | ローカルでビルド・テスト・実操作するコマンド |
| [review-evidence.md](review-evidence.md) | ソース・実行・画像・録画・レビューの照合 |
| [script-tooling.md](script-tooling.md) | CLIの入出力、表示、失敗処理 |
| [performance-verification.md](performance-verification.md) | 性能測定の条件、補助予算、適用限界 |
| [testflight.md](testflight.md) | 署名・アップロード、配布担当者の確認、秘密情報 |
| [reference](reference/README.md) | 外部仕様・一次資料の確認範囲と適用限界 |

採用仕様、外部資料、未解決の評価課題、実行結果は異なる情報です。設計の定義は上表の文書に置き、特定ソースの成否・画面・測定値はGit管理外の`artifacts/`へ記録します。検査コマンドの存在や設計台帳の記載は、あるビルドで検証を完了したという申告ではありません。
