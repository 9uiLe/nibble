# nibbleのUI設計

UIは、文章の準備・発見・完成文確認・利用・回復をつなぐ。OS標準の日本語入力を本体で使い、保存済み文章と途中作業を分ける。最低対応はiOS 26.0、実行評価はiOS 26.5の専用Simulatorである。

## 操作と表示の方針

| 利用場面 | 構成と理由 |
| --- | --- |
| 作る・取り込む | 本体の作成と共有取り込みを同じエディターへつなぐ。保存まで利用対象を変えず、閉じた作業は再開できる |
| 探して選ぶ | 名前・本文の検索とすべて／ピン留めを一画面へ置く。行は識別、行の選択後は全文確認、管理メニューは編集と整理を担当 |
| 今回の内容を完成させる | 必要な文章だけ差し替えを明示的に有効にし、ひな型を変えずOS標準入力で今回の値を用意する。完成文は文字どおりの全文を示す。Markdownの描画切替を設けない |
| 他アプリで使う | 本体で明示コピーした後、入力先へ戻ってOSでペーストする。任意のKeyboardはピン留め固定文だけを全文確認して挿入 |
| 中断・誤操作から戻る | 編集と準備の作業を保存済み一覧から分けて示す。削除は回復可能なごみ箱移動で、作業中の入力を巻き込まない |
| 結果を理解する | 実際に完了した処理だけを伝える。コピー済みと片付け失敗を区別し、再試行でコピー・挿入を自動重複しない |

本体は標準のNavigationStack・List・Form・文字スタイルとDynamic Typeを使う。Keyboardの独自入力、課金・広告・Riveは製品の構成へ含めない。採用構成、効果の仮説、実物の観測を区別し、これらの選択だけで速度や使いやすさの改善を断定しない。

## 設計資料と識別子

| 正本 | ID | 定義すること |
| --- | --- | --- |
| [共通原則](foundations.md) | F | 読み順、色、文字、操作、状態とOSの境界 |
| [画面構成](screens.md) | S | 目的、入口と終了、構成、画面固有の評価 |
| [部品台帳](components.md) | C | 責務、配置理由と制約、成立条件 |
| [設計根拠](evidence.md) | R | 要求・source・観測の種類と適用限界 |
| [評価課題](audit.md) | G | 目的達成を確認する問いと観測条件 |

IDは責務を識別し、Swift型と一対一でなくてもよい。採用しない旧画面は維持する操作として扱わない。語彙と操作の意味は[F09](foundations.md#f09-文言とデータ)と[文言設計](copy.md)へ集約する。

## 採用判断

- [操作・識別・回復](rationale/library-actions.md)：識別してから使う流れ、管理入口、作業の再開とごみ箱。
- [表示設定](rationale/fixed-interface.md)：標準文字、Dynamic Type、OS入力とsafe area。
- [並び順とピン留め](rationale/usage-order.md)：自動履歴順を持たず、利用者が頻用対象を選ぶ判断。
- [結果の通知](rationale/result-notices.md)：完了処理、失敗、明示的な再試行の区別。
- [原文の編集](../architecture/editing.md)、[変数](../architecture/variables.md)、[Keyboard](../architecture/keyboard.md)：入力、保存、完成文、外部作用の一体の設計。

情報構造や操作の意味を比較する際は[共通ひな形](../../tools/ui-design/templates/decision.md)、一般の工程は[共通手順](../../tools/ui-design/workflow.md)を使う。規定内の調整は対象IDの理由へ記す。画面の類似、一般指針、静的な照合だけでは実際の目的達成を証明しない。

## 設計基盤の構成

[共通ツールキット](../../tools/ui-design/README.md)がIDと入力照合を担う。[policy.json](policy.json)のsource範囲とregistryを[Adapter](../../scripts/check_ui_design.py)が選び、[review.json](review.json)へ確認した入力hash・判断要約・文書を記録する。

未確認変更を通すためにpolicyの入力範囲を狭めない。hashは実装・仕様・根拠の照合後に更新する。自動検査は形式と入力の一致を検査し、理由の妥当性、実操作、外観、製品全体の完成は判断しない。

## 変更時の手順

1. 変更をF・S・Cへ対応させ、採用仕様と実装を照合する。未確認の問いをGに残す。
2. [開発ガイド](../../CONTRIBUTING.md#実行と検査)に従い必要な検査と実操作を選ぶ。観測はsource・OS・構成・データ・操作・結果を持つrunへ記録する。
3. 実際に確認した文書と判断を指定して照合記録の候補を作る。

```sh
nix develop --command python3 scripts/check_ui_design.py snapshot \
  --summary '実装と採用仕様を照合した判断' \
  --reference docs/design/screens.md \
  --reference docs/design/components.md > artifacts/ui-design-review.json
diff -u docs/design/review.json artifacts/ui-design-review.json
```

4. 対象ファイル集合・判断・参照文書をレビューして候補を反映し、共通検査を行う。

```sh
cp artifacts/ui-design-review.json docs/design/review.json
nix flake check --no-update-lock-file --print-build-logs
```

snapshot生成は設計の承認や検証を代行しない。CIは読取検査だけを行い、自動更新しない。
