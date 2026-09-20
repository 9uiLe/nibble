# nibbleのUI設計

UIは、保存した内容を見つけ、対象を取り違えずに利用し、編集中の入力を保持して戻れることを目的とする。本体・共有拡張・キーボードを対象に、日本語、iOS 26.0以上、固定した表示設定で設計する。実行評価はiOS 26.5 Simulatorで行う。

## 設計資料と識別子

| 正本 | ID | 定義すること |
| --- | --- | --- |
| [共通原則](foundations.md) | F | 色・文字・余白・操作領域・状態・動きの共通判断 |
| [画面構成](screens.md) | S | 目的、到達と終了、読み順、固定/スクロール、画面固有の評価 |
| [部品台帳](components.md) | C | 要素の責務、配置理由、代替案の利点と負担、受入条件 |
| [根拠](../../research/06-interface-design-evidence.md) | R | 外部指針と確認範囲、製品への適用限界 |
| [評価課題](audit.md) | G | 実装との照合で確認する点と未完了の評価 |

IDは意味を表し、Swiftの型と一対一である必要はない。同じ責務は同じIDを使う。全画面で同じ規則はF、画面全体の導線はS、要素固有の理由はCに置き、同じ仕様を複数の表へ転記しない。

日本語UIは、[F09の語彙・文体・表記](foundations.md#f09-文言とデータ)を共通規則とし、[文言設計](copy.md)で一覧・編集・共有・キーボードの操作と具体的な表現を対応させる。[検証記録](../copy-validation.md)は対象ソースと観測範囲を示す。

## 採用判断

| 判断書 | 内容 |
| --- | --- |
| [操作・識別・回復](decisions/0001-library-actions.md) | 可視の管理入口、下書きの表示予算、明示的な編集終了 |
| [表示設定](decisions/0002-fixed-interface.md) | 文字・太字・コントラスト・演出の固定とOS所有部分 |
| [使用回数順](decisions/0003-usage-order.md) | 使用の定義、並び順、未使用の補足、使用記録の失敗 |
| [完了通知](decisions/0004-result-notices.md) | 内容を動かさない通知層、取り消し、滞在と期限 |
| [Keyboard](../decisions/0005-snippet-keyboard.md) | 入力・全文・権限・共有DB・入力先の寿命 |
| [説明イラスト](../decisions/0004-rive-presentation.md) | 説明の意味、配置、再生方針、ホストとRMLの分担 |

情報構造や操作の意味を選ぶ際は[共通ひな形](../../tools/ui-design/templates/decision.md)を使う。規定内の調整は対象IDの理由へ記す。外部指針、製品判断、効果の仮説、実測した観測は区別する。一般の設計工程は[共通手順](../../tools/ui-design/workflow.md)に従う。

## 設計基盤の構成

[共通ツールキット](../../tools/ui-design/README.md)がIDと入力照合の処理を提供する。nibbleは[policy.json](policy.json)でパス・除外・registryを定義し、[Adapter](../../scripts/check_ui_design.py)がその設定を選ぶ。共通Moduleから製品のコードやパスを参照しない。

[review.json](review.json)は確認した入力hash、判断要約、確認文書を持つ。設定が列挙する入力と内容が異なれば未確認変更として失敗する。記録からファイル名を除いて検査範囲を狭めることはできない。自動検査はID・形式・hashを確認し、理由の妥当性や画面の品質は判断しない。

## 変更時の手順

1. 変更をF・S・Cへ対応させ、実装・採用仕様・根拠を照合する。未解決の評価はGへ残す。
2. [開発ガイド](../../CONTRIBUTING.md#実行と検査)で必要なテスト・実操作を選び、観測はソースと条件を持つrunへ記録する。
3. 実際に確認した文書と判断を指定して照合記録の候補を生成する。

```sh
nix develop --command python3 scripts/check_ui_design.py snapshot   --summary '実装と仕様を照合した判断'   --reference docs/design/screens.md   --reference docs/design/components.md   > artifacts/ui-design-review.json
diff -u docs/design/review.json artifacts/ui-design-review.json
```

4. 判断・参照文書・対象ファイル集合の差分をレビューして候補を反映し、共通検査を行う。

```sh
cp artifacts/ui-design-review.json docs/design/review.json
nix flake check --no-update-lock-file --print-build-logs
```

diffの終了コード1は差分ありを表す。snapshot生成は設計の承認や確認を代行しない。CIは読取検査だけを行い、自動更新しない。設定・台帳・照合記録は同じPRでレビューする。
