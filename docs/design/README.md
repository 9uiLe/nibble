# nibbleのUI設計

UIは、保存した内容を見つけ、対象を取り違えずに利用し、編集中の入力を保持して戻れることを目的とする。本体・共有拡張・キーボードを対象に、日本語、iOS 26.0以上、固定した表示設定で設計する。実行評価はiOS 26.5 Simulatorで行う。

## 操作と表示の方針

| 利用場面 | 設計と正本 |
| --- | --- |
| 項目を探して利用する | 一つの作業画面で一覧と検索を扱い、設定へは右上から階層移動する。検索語を消すと直前の集合へ戻る。[C01〜C12](components.md#ナビゲーションと一覧) |
| 入力を始めて終える | 下部の「新規作成」から共通エディターを開く。検索入力は検索欄のタップで開始する。保存と下書き保持を区別し、終了操作は文字の「閉じる」「保存」で示し、編集の補足入口は「入力と保存について」と表示する。[S02・S03・S07](screens.md)、[操作の理由](rationale/library-actions.md) |
| 結果を確認して続ける | 高コントラストの全幅通知を内容の上に重ね、出現と消去を補間する。入力と一覧の配置を維持する。[C18・C19](components.md#検索と状態表示)、[通知の契約](rationale/result-notices.md) |
| 設定と情報を見る | Pro・キーボード案内・削除一覧・製品情報への行に用途の短い補足と遷移矢印を付け、操作を持たないバージョンを区切り線なしの末尾に表示する。[S04](screens.md#s04-設定) |
| 本体以外から使う | 共有拡張は共通エディター、キーボードは原文を挿入する専用表示を使う。[S07・S09](screens.md) |

画面の状態、業務処理、外部作用を分け、View型と共通Modifierで構成する。[実装規約](../library-policy.md#viewの構成とレイアウト)と[責務の配置](../architecture/README.md)が、すべての入口で同じ設計を維持する境界を定める。

## 設計資料と識別子

| 正本 | ID | 定義すること |
| --- | --- | --- |
| [共通原則](foundations.md) | F | 色・文字・余白・操作領域・状態・動きの共通判断 |
| [画面構成](screens.md) | S | 目的、到達と終了、読み順、固定/スクロール、画面固有の評価 |
| [部品台帳](components.md) | C | 要素の責務、配置理由、制約、受入条件 |
| [根拠](evidence.md) | R | 外部指針と確認範囲、製品への適用限界 |
| [評価課題](audit.md) | G | 実装との照合で確認する点と未完了の評価 |

IDは意味を表し、Swiftの型と一対一である必要はない。同じ責務は同じIDを使う。全画面で同じ規則はF、画面全体の導線はS、要素固有の理由はCに置き、同じ仕様を複数の表へ転記しない。

日本語UIは、[F09の語彙・文体・表記](foundations.md#f09-文言とデータ)を共通規則とし、[文言設計](copy.md)で一覧・編集・共有・キーボードの操作と具体的な表現を対応させる。対象ソースと観測範囲は[証跡手順](../review-evidence.md)に従いrunへ記録する。

## 採用判断

| 判断書 | 内容 |
| --- | --- |
| [操作・識別・回復](rationale/library-actions.md) | 可視の管理入口、下書きの表示予算、明示的な編集終了 |
| [表示設定](rationale/fixed-interface.md) | 文字・太字・コントラスト・演出の固定とOS所有部分 |
| [使用回数順](rationale/usage-order.md) | 使用の定義、並び順、未使用の補足、使用記録の失敗 |
| [完了通知](rationale/result-notices.md) | 内容を動かさない通知層、取り消し、滞在と期限 |
| [編集とMarkdown](../architecture/editing.md) | 原文の保持、入力とプレビュー、解析・フォーカス・保存の寿命 |
| [Keyboard](../architecture/keyboard.md) | 入力・全文・権限・共有DB・入力先の寿命 |
| [説明イラスト](../architecture/presentation.md) | 説明の意味、配置、再生方針、ホストとRMLの分担 |

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
