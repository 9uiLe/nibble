# nibbleのUI設計

指定された `a-ios-polish-v1` への反映は[外観の基準と反映の境界](ios-polish.md)を参照する。一覧から詳細・入力・標準Alertへ展開し、利用者が選んだ破棄確認・削除取り消し・タイトルと本文の必須条件を反映する。以下の旧構成を、新しい一覧へ部品を追加する根拠にはしない。

UIはプロンプトの作成・発見・全文確認・コピー・回復をつなぐ。OS標準の日本語入力とDynamic Typeを使う。最低対応はiOS 26.0、実行評価はiOS 26.5の専用Simulatorである。

## 操作と表示の方針

| 利用場面 | 構成と理由 |
| --- | --- |
| 作る | 新規作成はタイトルと本文、本文編集は本文だけを扱い、成功まで元の保存内容を変えない |
| 探して選ぶ | タイトル・本文検索、1行の本文抜粋、行コピーと詳細への選択を分ける |
| 確認して使う | 枠のない文字どおりの全文を表示し、明示コピー後は入力先でOSのペーストを行う |
| 誤操作から戻る | 変更の破棄を確認し、削除直後に取り消せる。保存失敗の入力を残す |
| 結果を理解する | 完了した保存・削除・復元・コピーだけを伝える。コピーを貼付・送信と呼ばない |

本体はNavigationStackと指定された余白・Capsule・行構成を使い、Liquid Glass・Alert・入力はiOSへ任せる。旧構成のList・Form・設定・作業中・差し替えは通常導線へ持ち込まない。共有拡張・Keyboardの責務は[本体との境界](ios-polish.md)を参照する。構成の選択だけで速度や使いやすさの改善を断定しない。

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
