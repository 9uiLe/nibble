# UIと保存の性能検証

## 目的と評価単位

検索して正しい文章を確認し、意図した内容で使うまでの応答と資源消費を評価する。正しい原文・入力・対象UUIDを保持した条件で測る。件数、body評価回数、タップ数だけを成果にしない。実行は専用iOS 26.5 Simulator、Releaseを使い、実機の性能は受入に含めない。

| 指標 | 終点と適用限界 |
| --- | --- |
| 保存層の検索 | 公開APIをawaitして50件以下のページを受け取るまで。描画や利用者の発見時間を含まない |
| 全ページ走査 | 5,000件・100ページの取得とID・バイト数集計の終了まで。通常の一覧が全件取得する意味ではない |
| 長文確認の安定 | 実WorkspaceUseViewを配置し、25ms以上離れた2回のPNGが一致するまで。描画・PNG圧縮・ポーリングを含む |
| 反復の保持量 | 各回の表示中と終了後のprocess physical footprint、モデルとscroll viewの解放。allocatorのcacheを含む |
| 利用完了時間・hitch | 別の利用課題・traceで測る。上の補助指標から換算しない |

## 専用Release測定

[NibblePerformanceの測定](../app/NibblePerformanceTests/WorkspaceMeasurements.swift)は製品をホストする独立targetで、通常の`Nibble` schemeに時間の閾値を混ぜない。[共通host](../app/TestSupport/ViewTestHost.swift)を使い、Rive依存はない。

```sh
nix develop --command env NIBBLE_UI_FORMAT=json python3 scripts/verify.py run \
  --scope performance --device "$NIBBLE_SIMULATOR"
```

5,000件のDBを計測区間外で作る。1件は製品の公開保存APIで作り、残りは同じschemaへの一括fixture投入を使う。検索4種類を8回、全ページ走査を4回行う。約200 KBのUnicode原文を使う全文確認は、初回と再訪6回で実windowへ配置し、終了後に所有資源が解放されることを確認する。

xcresultの`workspace-repository-measurements.json`と`workspace-preview-measurements.json`へ、各回のms、UTF-8バイト数、件数、実際のhost寸法、OS、process footprintを残す。計測区間へseedingを混ぜない。録画・Instruments・別の負荷試験と同時に実行しない。

| 保守的な回帰上限 | 値 |
| --- | --- |
| 1ページの検索 | 750 ms |
| 5,000件全ページの走査 | 8,000 ms |
| 配置から2回の同一renderまで | 6,000 ms |
| 準備回を除く終了後footprintの最大−最小 | 96 MiB |

これらは異常な劣化を見つける上限であり、快適な入力・描画・利用完了時間を保証する値ではない。値が上限内でも原文や対象のassertionが失敗すれば不合格とする。上限を超えたrunを残し、表示障害や計測結果を理由に成功扱いへ変えない。

## 比較条件

コミット・入力hash、Xcode/Swift/SDK、OS build、Simulator UDID、ビルド構成、最適化、テスト可能性、署名、件数・長さ、操作順と測定回数をそろえる。準備と本計測を分け、版の実行順を交互にし、各サンプルとばらつきを残す。前版の保存モデルと互換性がない場合は、同じ上位課題を各版の実入口で実行する。新しいAPIの値だけから前版より速いと述べない。

## Instrumentsの構成と成立条件

`xctrace`は記録とexportを行うCLI、`.trace`は記録のまとまりである。対象のUDID・bundle ID・PID・起動時刻・実行ファイルを照合し、記録開始、対象操作、正常停止、保存、export、対象PIDの実サンプルまで確認する。ファイルの存在や終了コード0だけでは計測成功にならない。

導入版の`xcrun xctrace help record`と`help export`で仕様を確認する。新しい出力先を使い、接続確認と製品操作の本計測を分ける。次は5秒の接続確認例で、45秒は開始・保存待ちを含めた外側の期限である。

```sh
nix develop --command timeout --signal=INT --kill-after=5s 45s \
  xcrun xctrace record --template 'Time Profiler' \
  --device "$NIBBLE_TRACE_DEVICE" --attach "$NIBBLE_TRACE_PID" \
  --time-limit 5s --output "$NIBBLE_TRACE_OUTPUT"
xcrun xctrace export --input "$NIBBLE_TRACE_OUTPUT" --toc --output "$NIBBLE_TRACE_TOC"
```

導入版のTOCに存在するtableを選んでexportし、対象PIDと操作区間のデータを読む。開始前・記録中・保存中・exportの失敗を区別する。権限・署名・OSが原因という判断には条件を変えた実験が必要である。Macの最小プログラムが動くことをSimulatorの成功へ読み替えない。

## 検証記録

`artifacts/`へソース、環境、コマンド、開始終了、終了コード、打ち切り、raw JSON、trace/exportと観測を保存する。現在の実行結果は[証跡手順](review-evidence.md)で照合する。未実施のフレーム時間、hitch、CPU、電力や実機性能を推定しない。

## Riveの補助指標

この見出しは既存の参照を保つために残す。再設計した製品はRive演出を採用しておらず、旧Rive測定の結果・予算は現在の製品の合格証拠ではない。現在の測定入口は上記の専用Release測定である。
