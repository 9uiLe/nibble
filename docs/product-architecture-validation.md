# 製品基盤の検証

## 対象と条件

比較元は`3ce14844af5b32793926468a753099038a8482cf`、検証対象の製品・テスト・driverは`c84280c3c26b6cf0a8cbf75dd46e8d3ee78e40e2`。目的は保存・検索・下書きの整合性と画面操作を保ち、保存資源とOS操作の責務を限定し、配布容量を抑えること。構成の正本は[製品設計](decisions/0002-mvp-app.md#構成と責務)、実装契約は[ライブラリ規約](library-policy.md)とする。

- Xcode 26.5（17F42）、Swift 6.3.2、SDK / 実行runtime iOS 26.5。
- 容量はarm64のunsigned Release archive。認証・署名・アップロードを含めない。
- 保存の比較は同じ専用Simulator、10,000スニペット（ピン50件）、200下書き（本文118,750 UTF-8 bytes）のDB複製を使う。
- `validation/StoreBenchmark.swift`が実際の製品保存層・編集モデルを呼ぶ。UIとRiveの描画性能は測定しない。
- `scripts/benchmark-store.py`は比較元をGitから、比較先を作業ツリーから固定し、ソースhash、SDK、最適化、端末、実行ごとの生データを保存する。

## 再現手順

専用のiOS 26.5 Simulatorを起動し、ほかのビルドや測定を停止する。出力先は新しいディレクトリを指定する。

```sh
nix develop --command python3 scripts/benchmark-store.py \
  --device "$NIBBLE_SIMULATOR" \
  --baseline-ref 3ce14844af5b32793926468a753099038a8482cf \
  --output artifacts/store-comparison
```

比較順は変更前→変更後→変更後→変更前→変更前→変更後。各プロセスは同じDBのコピーから始める。一覧はwarm-up後30回、検索・下書き再開・入力保存・1 MB入力はそれぞれ100回の値を取る。変更前は`-O`、変更後は製品Releaseと同じ`-Osize`、両方whole-module・Swift 6とする。

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

### 製品テストとUI操作

Releaseテストは`artifacts/ios/20260918T010253Z-test-858b63`で67件成功、失敗・skipなし。SQLの再利用と失敗回復、複数接続、業務処理とOS操作の順序、下書き競合、表示値の比較、Riveと固定表示を含む。

初回の`20260918T005616Z-test-e107ad`はテスト側の旧initializer呼出しでコンパイルが失敗した。保存先の注入を修正して上記runで再実行し、初回のテストは実行済み件数へ含めていない。

UIは同じiPhone 17 Pro Simulator（iOS 26.5、23F77、402×874 pt）でRelease buildを含むrunを取得した。各run内に操作ログ、assertion、PNG、MP4、原本からの抽出フレームを保存した。

| run | 確認した動作 | 結果 |
| --- | --- | --- |
| `20260918T010429Z-mvp-ui-3ad4dd` | 作成、下書き保持・再開、保存、検索・編集、原文コピー、ピンと各フィルター、操作位置と再起動、削除・Undo、破棄、削除一覧での検索・復元、設定・About | 全assertion成功。Undo・復元は同じUUIDと本文で確認 |
| `20260918T011747Z-architecture-swipes-539cfd` | 右フルスワイプのピン解除・設定、左フルスワイプの削除、Undo、本文コピー | 同じUUID・UTF-8原文で復元 |
| `20260918T012520Z-architecture-share-15adaa` | Safariのダミー本文を共有、拡張でタイトル入力・保存、共有元へ復帰、本体に反映・コピー | bundle ID・App Groupを照合。前後空白・改行・結合文字・絵文字を含む原文が完全一致 |

MVPの`resumed-draft.png`、`pinned-filter.png`、`settings.png`、`about.png`、`finished.png`を開き、本文、選択表示、行操作、設定、説明の配置を確認した。183.017秒の動画は7.993秒・91.725秒・164.735秒のフレームを開いた。順に一覧、検索結果のメニュー遷移、削除一覧の検索0件とキーボードを確認した。

スワイプの`restored.png`と11.118秒の動画の8.578秒で、復元済み行とコピー通知を確認した。共有の`share-options.png`、`share-editor.png`、`shared-in-library.png`と、126.240秒の動画の64.140秒を開き、共有先、共通編集、キーボード併用、保存済み行の配置を確認した。動画は抽出フレームによる観察であり、全編連続再生の確認ではない。

操作driverの失敗も保持した。`20260918T011632Z-architecture-swipes-f49622`は短い左ジェスチャーで削除ボタンの表示までしか進まず、全幅の操作に修正して再実行した。共有の`20260918T011855Z-architecture-share-f5b77d`は表示切替後に古いラベルへ再タップして失敗し、`20260918T012347Z-architecture-share-454ee8`は共有シートの相対座標を画面座標として使ってシート外をタップした。画像とAXを照合し、画像上の共有先位置で操作した最終runが成功した。これらの失敗runを成功した証跡に含めない。

## 共通検査と証跡

`nix flake check --no-update-lock-file --print-build-logs`の7検査が成功した。iOS toolingの101件、共通UI設計ツールの35件の回帰テストを含む。ログは`artifacts/nix-final.log`と`artifacts/nix-final-evidence.log`に保存した。

archiveの製品入力と性能比較の保存層・編集モデルのhashが作業ツリーと一致することも確認した。上記のReleaseテストと3種類のUI runは、`check_evidence.py --ref c84280c3c26b6cf0a8cbf75dd46e8d3ee78e40e2 --integrity-only`ですべて成功した。開始・終了・コミットの検証入力、ビルド、媒体hashを照合した結果であり、公開先の閲覧確認は含まない。

各UI runの`review.json`に実際の観察範囲を記録した。画像・動画はローカルの`artifacts/`で保持し、PRへのアップロードと閲覧確認は実施していない。

## 測定の限界

Simulatorの値を実機の応答速度、フレームレート、消費電力へ換算しない。archive内のバイト数はApp Storeの圧縮・thinning後のダウンロードサイズではない。追加の索引と最大32件のstatementはメモリ・DB容量を使用する。本文のbindingは実行後に解除する。

## 参照した仕様

- [SQLite reset](https://www.sqlite.org/c3ref/reset.html)、[bindingの解除](https://www.sqlite.org/c3ref/clear_bindings.html)：resetだけでは値を解放しない。失敗時はstatementを破棄する。
- [Swiftのサイズ最適化](https://www.swift.org/blog/osize/)：コード生成の速度・サイズのトレードオフ。nibbleでの採否は上記の同条件比較と操作検証に基づく。
