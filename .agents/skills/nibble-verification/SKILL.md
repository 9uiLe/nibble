---
name: nibble-verification
description: nibbleのローカルiOS検証、証跡整理、PR作成・更新に使う。検証対象とソースの一致、Simulator操作の失敗切り分け、画像・録画の確認範囲、PR本文とコミットの整合性を扱う。
---

# nibbleの検証とレビュー

規約は[開発ガイド](../../../CONTRIBUTING.md)、コマンドと合格条件は[証跡とPRの検査](../../../docs/review-evidence.md)を参照する。依頼された作業に必要な部分を適用する。PR作成の依頼はマージやリポジトリ権限の変更を含まない。

## 1. 対象と期待結果を定義する

| 対象 | 設定と手順 | 確認する責務 |
| --- | --- | --- |
| Nibble / NibbleShare | `app/project.json`・[製品手順](../../../docs/mvp.md) | 製品のデータ・画面・日常操作 |
| VerificationApp | `validation/project.json`・[共通手順](../../../docs/ios-verification.md) | ツールチェーン・文字列反映・操作・撮影 |
| ResearchProbe | `validation/research-project.json`・[研究手順](../../../validation/RESEARCH.md) | 保存・検索・復旧・OS連携の比較実験 |

fixtureや比較実験の成功を製品の成功として報告しない。操作APIは直接awaitし、戻った時点の状態と永続化を検査する。タスクの重複・キャンセル・寿命は所有者、View比較は入力の変更・復元と同一入力での外観・Dynamic Type更新を検査する。

設計資料には目的・採用構成・責務・契約・制約を定義する。検証記録には対象ソース・環境・手順・観測・失敗・未実施条件を置き、候補・採用・検証済みを区別する。

## 2. 専用Simulatorで実行する

Apple CLIとNixのsim-useを使い、明示したiOS 26.5のUDIDを直列に操作する。1回の実行をrunと呼ぶ。ソースと実行バイナリの対応を保つため、runの途中で製品・テスト・driver・ツール設定を編集しない。DerivedDataはコンパイルcacheとして使い、対象destinationでビルドする。別runのビルドや単独撮影ではソースの照合が成立しない。

- `sim-use ui`を実行して得た結果から対象を選ぶ。要素の識別には`uniqueId`、原文比較には`value`を使う。
- 作成項目は一意なダミー検索語とUUIDで追跡する。編集後のコピーは空白・改行・結合文字を含むUTF-8、削除取り消しは同じUUIDで照合する。
- 日本語ペーストとIME変換を別々に検証する。`paste --replace`の日本語編集メニュー問題は、製品driverの限定的なfallbackと編集後コピーの完全一致で判定する。任意の非ゼロ終了を無視しない。
- Simulatorが応答しない場合はログを残す。Apple CLIの端末状態とSettings等の標準アプリの操作から、製品固有の失敗かを切り分ける。同じ失敗を繰り返さず、必要なら専用Simulatorを新規作成する。ユーザーの端末をeraseしない。
- Xcodeのマクロ未承認は、固定revisionを照合し、対象パッケージを承認する[セットアップ手順](../../../README.md#3-xcodeとswift-packageを準備する)に従う。一括でマクロ検証を無効にしない。

## 3. ソース・媒体・観測を照合する

1. `check_evidence.py --integrity-only`でrunの成否と対象revision・媒体の一致を調べる。文書だけの変更でもファイル照合を行う。失敗runは残し、成功した別runで上書きしない。
2. `--init-review`で記入用の`review.json`を作る。画像を開き、録画は必要な範囲を再生またはフレーム抽出で確認する。実際の観測、抽出時刻、未確認条件を記録する。抽出フレームの確認を全編再生と記載しない。
3. 公開する媒体がダミーデータであることを確認する。`nix develop --command gh pr create --help`で`--attach`の対応を確認し、対応する場合は原本を添付する。対応しない場合はGitHubのブラウザー添付を使う。
4. アップロード後の本文をGitHubから取得し、その本文を編集元にする。画像の読込サイズと動画プレーヤーの読込状態をブラウザーで確認し、閲覧条件を記録する。未認証HEADの403だけで添付失敗と判定しない。
5. 安定した添付URLを`review.json`へ記載し、`check_evidence.py`で照合して`REVIEW.md`を生成する。ブラウザー用の一時署名URLは保存しない。原本とブラウザーで動画時間が異なる場合はそれぞれの観測として扱う。

## 4. PRとマージ条件を確認する

- `check_pr.py commits --base origin/main`で全コミット表を生成し、説明を目的に沿って編集する。本文はファイルに保存し、`gh pr create/edit --body-file`で改行を保持する。
- コミット済みの差分に対して`check_pr.py local --complete`で本文を検査する。pushや本文編集後は`remote --complete --check-ci`で現在headと全コミットを確認する。実行中のCI自身から`--check-ci`を呼ばない。
- 性能改善は同条件の測定結果に基づいて述べる。driverの待機を含む録画時間、比較コードの存在、画像一致だけで高速化を主張しない。UX・アクセシビリティ・性能の未完了事項を明記し、完了チェックを付けない。
- 自動検査は記録の整合性と申告の形式を扱う。影響する導線の検証、媒体の内容、実際の閲覧、単一目的かという判断はレビューで行う。
