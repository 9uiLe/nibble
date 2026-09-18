# UIとモデルの性能検証

## 目的と評価単位

nibbleの性能検証は、入力・検索・保存・画面遷移の応答と、表示内容の整合性を評価する。最低対応OSはiOS 26.0、製品の実行評価はiOS 26.5 Simulatorとする。実機の性能を評価する場合は端末と手順を別に定義する。

設計上の責務は[製品設計](decisions/0002-mvp-app.md)、ビルドと操作は[MVP手順](mvp.md)、実測・未確認事項は[検証結果](mvp-validation.md)を参照する。

| 評価単位 | 調べること | 結果の意味 |
| --- | --- | --- |
| View値の生成 | initializerから呼ぶ処理、生成するオブジェクト、頻度 | View構造を作るCPU負荷 |
| bodyの評価 | 状態の読取、派生値の計算、更新範囲と頻度 | 表示内容を決める処理の負荷 |
| レイアウト | サイズ提案・決定・配置、内容や利用領域の変化 | 要素の配置にかかる負荷と安定性 |
| 描画・合成 | フレーム時間、hitch、GPU、画面外の処理 | 実際に画面を表示する負荷 |
| モデル・保存層 | 要求から結果反映までの時間、SQL、並行操作 | データ処理の負荷。描画の結果は含まない |
| メモリ・容量 | 保持期間、ピーク、archive内のファイル量 | 常駐負荷と配布物の大きさ |

bodyの実行回数、画像の一致、自動操作の録画時間だけで応答や描画の改善を判定しない。症状が現れる操作と、その操作に関係する時間・頻度・更新範囲を対応させる。

## 比較条件

比較する版ごとに、コミットと入力ファイルのhash、Xcode・Swift・SDK、OS build、端末UDID、ビルド構成、データ、操作、測定回数を記録する。原則として同じRelease条件を使い、最適化・テスト可能性・署名条件に違いがあれば明記する。

1. 起動、検索、入力、スクロール、連続操作、背景復帰から評価対象を選ぶ。
2. 同じダミーデータ、検索語、件数、本文長、表示設定、操作順を用意する。
3. ウォームアップと測定を分け、比較する版の実行順を交互にする。
4. 個別サンプルを保存し、代表値とばらつきを示す。p95は95パーセンタイルを意味する。
5. 応答とともに、入力・選択・原文・対象UUIDが保持されることを確認する。

Simulatorのホスト負荷と実機の条件は一致しない。モデル単体の時間、SwiftUIのフレーム時間、端末全体のメモリを混ぜて集計しない。容量は同じarchive条件で本体・拡張・runtime・アセットを比較し、dSYM・テスト・DerivedDataを除く。

## Instrumentsの構成と成立条件

Instrumentsは計測結果を表示・分析するアプリ、`xctrace`は記録・exportを行うCLIである。`.trace`は記録ファイルのまとまりを指す。Time ProfilerはCPUのサンプルを取得する計測テンプレートである。

計測は、対象の識別、サービス接続、記録開始、時間経過、停止、保存、exportの順に進む。`--time-limit`による記録時間と、開始待ち・保存待ちを含むコマンド全体の期限を分ける。

| 判定 | 必要な確認 |
| --- | --- |
| 対象が正しい | UDID、bundle ID、PID、起動時刻、実行ファイルが一致する |
| 記録が成立する | 開始と停止を確認し、期限による強制終了がなく正常終了する |
| 保存物が使える | traceをexportでき、必要なテーブルに対象プロセスの実データがある |
| 性能を比較できる | 記録区間に対象操作が含まれ、端末・版・データ・操作条件を照合できる |

ファイルの存在や正常終了だけでは、指定した操作の計測成功にならない。開始待ち、保存待ち、記録エラー、空テーブル、対象違いは別々の失敗として残す。

## 短時間の接続確認

Nixの開発環境とローカルのApple CLIを使う。`xcode-select -p`、`xcodebuild -version`、`xcrun xctrace version`、`xcrun xctrace list templates`で使用環境を記録する。コマンドの仕様は導入版の`xcrun xctrace help record`と`help export`で確認する。

専用Simulatorの起動とアプリのインストールは[MVP手順](mvp.md)に従う。`simctl launch`が返したPIDを`ps -p <PID> -o pid=,lstart=,comm=`で照合する。アプリを再起動した場合はPIDを取り直す。SimulatorのPIDをホストの計測対象として扱わない。

次の変数へ確認済みの値を設定する。出力パスは毎回未使用のものを選ぶ。

| 変数 | 値 |
| --- | --- |
| `NIBBLE_TRACE_DEVICE` | 専用SimulatorのUDID |
| `NIBBLE_TRACE_PID` | 起動時刻と実行ファイルを照合したアプリのPID |
| `NIBBLE_TRACE_OUTPUT` | 保存する`.trace`のパス |
| `NIBBLE_TRACE_TOC` | exportするテーブル一覧XMLのパス |
| `NIBBLE_TRACE_SAMPLES` | exportするCPUサンプルXMLのパス |

5秒の記録、45秒の外側の期限、割り込み後5秒での強制終了は接続確認用の値である。本計測では操作区間と通常の開始・保存時間に合わせて期限を決める。`timeout`はNix環境内のGNU coreutilsを使う。

```sh
nix develop --command timeout --signal=INT --kill-after=5s 45s \
  xcrun xctrace record --template 'Time Profiler' \
  --device "$NIBBLE_TRACE_DEVICE" --attach "$NIBBLE_TRACE_PID" \
  --time-limit 5s --output "$NIBBLE_TRACE_OUTPUT"
```

正常終了したtraceに対して、テーブル一覧とサンプルをexportする。

```sh
xcrun xctrace export --input "$NIBBLE_TRACE_OUTPUT" --toc \
  --output "$NIBBLE_TRACE_TOC"
xcrun xctrace export --input "$NIBBLE_TRACE_OUTPUT" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output "$NIBBLE_TRACE_SAMPLES"
```

このXPathは1回目のrunの`time-profile`テーブルを選ぶ。導入版のテーブル一覧に存在することを確認して使い、サンプルの対象PIDと記録区間まで照合する。成功した接続確認は、製品操作の性能評価とは別の記録にする。

## 失敗時の切り分け

| 確認する境界 | 方法 | 残す情報 |
| --- | --- | --- |
| 対象の識別 | PID・パス・起動時刻・UDIDを照合 | コマンドと対象識別情報 |
| 停止した段階 | 記録ログと計測プロセスの短いスタックを確認 | 開始前・記録中・停止中・保存中の別 |
| アプリへの依存 | 同じ端末でデータを持たない最小プログラムを計測 | ソース、compile条件、成否 |
| 計測器への依存 | 導入版に存在する別テンプレート・単体計測器を使用 | 各計測器の対応状況と結果 |
| 端末・サービスへの依存 | 別の専用端末、専用サービスの再起動、データを消さない再起動で比較 | 変更した条件と同時刻のサービスログ |
| ホストへの依存 | Mac用の最小プログラムで記録・exportを確認 | Simulatorとは別の対照結果 |

一度に一つの条件を変える。権限設定・署名・OS更新を原因と断定するには、その条件を変えた比較が必要になる。ホスト側の成功をSimulatorの成功として扱わない。`sample`で取得したcall graphは停止箇所の切り分けに使い、フレーム時間やhitchの評価へ換算しない。

計測用プロセスは識別して停止し、ユーザーの別端末・作業・保存データへ影響を広げない。認証情報・Keychain・配布用設定・認証ログは調査対象に含めない。

## 検証記録

`artifacts/`へコマンド、対象ソース、端末、開始時刻、終了コード、打ち切り、ログ、trace、export結果を保存する。確認した事実、原因の仮説、未実施条件を分け、[証跡の契約](review-evidence.md)に従って対象と結果を対応させる。

- [SwiftUIの評価記録](swiftui-investigation.md): 対象別の調査範囲、モデル処理、画面操作、未確認条件。
- [Instrumentsの診断記録](instruments-diagnosis.md): 計測サービスの障害と比較試験。記録失敗を製品の性能値として使用しない。
