# ローカルiOS検証

本書は、対象アプリのビルド・テスト・画面操作を実行し、ソースと結果が対応したrunを取得する手順を定義する。runは1回の検証で記録するソース・端末・コマンド・成否・媒体のまとまりである。規約は[開発ガイド](../../../../CONTRIBUTING.md)の該当節、実行コマンドは次の対象別手順を参照する。

## 対象と期待結果

| 対象 | 設定と手順 | 確認する責務 |
| --- | --- | --- |
| Nibble / NibbleShare / NibbleKeyboard | `app/project.json`・[製品手順](../../../../docs/mvp.md) | 製品のデータ・画面・日常操作 |
| VerificationApp | `validation/project.json`・[共通手順](../../../../docs/ios-verification.md) | 検証基盤を試験するfixture。ツールチェーン・文字列反映・操作・撮影 |
| ResearchProbe | `validation/research-project.json`・[研究手順](../../../../validation/RESEARCH.md) | 保存・検索・復旧・OS連携の比較実験 |

製品の期待結果はNibble・NibbleShare・NibbleKeyboardで確認する。VerificationAppの`ios.py smoke`は基盤の動作確認、ResearchProbeの`validation/check-research-ui.py`は比較実験を担当する。fixtureや比較実験の成功を製品の成功として報告しない。

変更した責務に応じて期待結果を選ぶ。操作APIは直接awaitした直後の状態と永続化、タスクの重複・キャンセル・寿命は所有者、View比較は入力の変更・復元と同一入力での環境更新を検査する。[固定表示方針](../../../../docs/design/decisions/0002-fixed-interface.md#検証と見直し)に従い、比較ゲート単体は外観・Dynamic Type更新を遮断しないこと、製品の入口は文字サイズ・太字・コントラスト・独自演出を固定することを分けて確認する。

## 実行とソースの対応

Apple CLIがビルド・実行管理・撮影、Nixのsim-useが画面の読取と操作を担当する。端末識別子であるUDIDを明示し、iOS 26.5の専用Simulatorを端末ごとに直列で操作する。runの途中で製品・テスト・driver・ツール設定を編集しない。修正する場合はrunを終了して記録を保存し、修正後に必要な実行をやり直す。

DerivedDataはコンパイルcacheとして使い、対象destinationでビルドする。別runのビルドや単独撮影ではソース照合が成立しない。実行記録・画像・録画はGit管理対象外の`artifacts/`へ保存し、[ソースと結果の照合](../../../../docs/review-evidence.md#runのソースと結果)へ進む。候補・採用・検証済みを区別し、記録には対象ソース・環境・手順・観測・失敗・未実施条件を残す。

## 操作と失敗の切り分け

- `sim-use ui`の結果から対象を選ぶ。要素の識別には`uniqueId`、原文比較には`value`を使う。
- 作成項目は一意なダミー検索語とUUIDで追跡する。編集後のコピーは空白・改行・結合文字を含むUTF-8、削除取り消しは同じUUIDで照合する。
- 日本語ペーストとIME変換を別々に検証する。`paste --replace`の日本語編集メニュー問題は、製品driverの限定的なfallbackと編集後コピーの完全一致で判定する。任意の非ゼロ終了を無視しない。
- Simulatorが応答しない場合はログを残す。Apple CLIの端末状態とSettings等の標準アプリの操作から、製品固有の失敗かを切り分ける。同じ失敗を繰り返さず、必要なら専用Simulatorを新規作成する。既存端末を消去・削除しない。
- Xcodeのマクロ未承認は、固定revisionを照合し、対象パッケージを承認する[セットアップ手順](../../../../README.md#3-xcodeとswift-packageを準備する)に従う。一括でマクロ検証を無効にしない。
