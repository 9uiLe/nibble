# 保存と配布容量の比較根拠

## 対象と条件

比較元は`3ce14844af5b32793926468a753099038a8482cf`、検証対象の製品・テスト・driverは`c84280c3c26b6cf0a8cbf75dd46e8d3ee78e40e2`。目的は保存・検索・下書きの整合性と画面操作を保ち、保存資源とOS操作の責務を限定し、配布容量を抑えること。構成の正本は[製品設計](decisions/0002-mvp-app.md#構成と責務)、実装契約は[ライブラリ規約](library-policy.md)とする。

- Xcode 26.5（17F42）、Swift 6.3.2、SDK / 実行runtime iOS 26.5。
- 容量はarm64のunsigned Release archive。認証・署名・アップロードを含めない。
- 保存の比較は同じ専用Simulator、10,000スニペット（ピン50件）、200下書き（本文118,750 UTF-8 bytes）のDB複製を使う。
- `validation/StoreBenchmark.swift`が実際の製品保存層・編集モデルを呼ぶ。UIとRiveの描画性能は測定しない。
- `scripts/benchmark-store.py`は比較元をGitから、比較先を作業ツリーから固定し、ソースhash、SDK、最適化、端末、実行ごとの生データを保存する。

## 測定条件と再測定

比較順はA→B→B→A→A→B。各プロセスは同じDB複製から始め、一覧はwarm-up後30回、それ以外は100回測定した。比較元Aは`-O`、比較先Bは`-Osize`、両方whole-module・Swift 6である。最適化を含む構成全体の比較で、各変更の寄与率は測っていない。

現在の`benchmark-store.py`は両版を`-Osize`で比較する。[実行手順](mvp.md#開発環境とビルド)は現在の保存層比較に使い、この記録の最適化条件を再現するコマンドとは扱わない。

## 結果

### 保存・入力の応答

`artifacts/store-comparison/results.json`に6プロセスの生データ、`summary.json`に集計を保存した。表は、各プロセスの中央値を求め、その3値の中央値を比較する。ファイルのhashも同じ記録に含む。

| 対象 | 変更前 | 変更後 |
| --- | ---: | ---: |
| 一覧100件＋下書き3件 | 0.337 ms | 0.310 ms |
| ピン留め50件 | 0.760 ms | 0.080 ms |
| 下書き再開 | 0.049 ms | 0.022 ms |
| 下書き入力の永続化 | 0.131 ms | 0.092 ms |
| 部分一致100件 | 0.144 ms | 0.138 ms |
| 部分一致なし（10,000件走査） | 4.565 ms | 4.282 ms |
| 1 MB入力のsetter＋保存可能判定 | 0.0263 ms | 0.0263 ms |
| 一覧保持時のプロセスfootprint | 9.69 MiB | 9.75 MiB |

ピン条件の索引利用と準備済みSQLの再利用は、この条件で応答を改善した。部分一致の走査時間は同程度で、全件走査をなくした結果ではない。メモリは約0.06 MiB増加した。測定後のDBとsidecarは両方28,585,984 bytesで同じだった。このfixtureでは空きページが追加の索引に再利用されるため、全データ量で索引の容量が無料になることを意味しない。

### 配布容量

`artifacts/performance/{baseline,verified}.xcarchive`と`{baseline,verified}-size.json`で比較した。署名・配信は行っていない。

| archive内の対象 | 変更前 | 変更後 |
| --- | ---: | ---: |
| `.app`全体（共有拡張を含む） | 8,588,489 bytes | 6,168,849 bytes |
| 本体実行ファイル | 2,706,152 bytes | 838,472 bytes |
| 共有拡張実行ファイル | 932,616 bytes | 380,656 bytes |
| RiveRuntime | 4,824,968 bytes | 4,824,968 bytes |
| Riveアセット | 80,316 bytes | 80,316 bytes |

全体は約28.2%減少した。外部依存・イラストの生成物・画面の機能を削らず、Releaseのテスト専用公開範囲とコード生成、View・保存層の分割を含む変更全体で比較している。個々の変更だけの寄与率は測っていない。

## 測定の限界

Simulatorの値を実機の応答速度、フレームレート、消費電力へ換算しない。archive内のバイト数はApp Storeの圧縮・thinning後のダウンロードサイズではない。追加の索引と最大32件のstatementはメモリ・DB容量を使用する。本文のbindingは実行後に解除する。

## 参照した仕様

- [SQLite reset](https://www.sqlite.org/c3ref/reset.html)、[bindingの解除](https://www.sqlite.org/c3ref/clear_bindings.html)：resetだけでは値を解放しない。失敗時はstatementを破棄する。
- [Swiftのサイズ最適化](https://www.swift.org/blog/osize/)：コード生成の速度・サイズのトレードオフ。nibbleでの採否は上記の条件を明示した比較と製品の操作検証に基づく。
