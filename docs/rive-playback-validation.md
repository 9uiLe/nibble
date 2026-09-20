# 説明画面の再生・停止・復帰の検証

対象は[Issue #36](https://github.com/9uiLe/nibble/issues/36)のS05・S10、C44・C49。採用仕様は[演出設計](decisions/0004-rive-presentation.md)、汎用APIは[RivePresentation](../app/Packages/RivePresentation/README.md)、評価課題は[G16](design/audit.md#g16-c--説明画面の再生とスクロールの性能)を参照する。本記録は測定したソースと条件の記録であり、未評価の性能を保証しない。

## ソースと条件

基準の製品ソースは`99050be923596ac9d6eee9340b43cde8988e493a`。測定用テストだけを加えた`20260920T122436Z-test-155be5`と、実装変更後の`20260920T130549Z-test-8cf70e`を比較した。各runの`manifest.json`に開始・終了の入力hash、端末、toolchain、コマンドを記録し、`attachments/`に`rive-playback-measurements.json`をexportしている。保存先はGit管理外の`artifacts/ios/`である。

| 条件 | 値 |
| --- | --- |
| 実行環境 | macOS 26.2、Apple M1 Pro、16GiB、Xcode 26.5 (17F42)、Swift 6.3.2 |
| Simulator | 専用iPhone SE (3rd generation)、iOS 26.5 (23F77)、UDID `04A79414-64A7-4167-9B1D-998F18DB9DA6` |
| 構成 | Release、-Osize、whole-module。契約テストのみENABLE_TESTABILITY=YES |
| アセット・依存 | 両版で同じabout-story.riv（80,316 bytes）・keyboard-story.riv（119,049 bytes）。hashはrunへ保存。rive-ios 6.27.0、revision `4c42e5839167a06a56d336e80813578bac018dde` |
| 表示 | 375×667ptのhost window、ライト。実画面の図は幅327pt／335pt、scale 2。通常はCanvas 1個、独立性テストは2個 |
| データと操作 | ダミーDB。各説明画面を開く→350ms再生→末尾へ移動→停止→先頭へ戻る→閉じる |
| 反復 | 各アセットの準備1回と再訪5回。通常テストの同じserialized suite。OS・Metal cacheは消去しない |
| 観測負荷 | テスト限定のRiveLog collectorと10ms間隔の状態待ち。録画・Instrumentsなし。製品にフレーム購読や独自時計を追加しない |

この準備回はプロセスのcold launchではない。別の契約テストやOS cacheの影響もあるため、初回描画の比較値には使わない。メモリは`task_info`のプロセス全体の`phys_footprint`であり、Workerだけの確保量ではない。

## 調整前に固定した補助予算と観測

基準測定後、製品実装を変更する前に`artifacts/issue36-budgets-before-implementation.md`へ以下を固定した。待機期限と合否予算は別である。表示完了やhitchの予算を決める測定は成立していない。

| 指標 | 補助予算 | 基準：About／Keyboard | 変更後：About／Keyboard |
| --- | --- | --- | --- |
| mountから最初のadvance、再訪5回中央値 | 各回100ms以下 | 31.09／27.09ms | 28.46／25.11ms |
| 同、再訪最大 | 同上 | 32.18／27.56ms | 35.42／31.57ms |
| 可視復帰要求から最初のadvance、中央値 | 各回100ms以下 | 32.58／33.18ms | 12.99／16.43ms |
| 同、最大 | 同上 | 35.54／34.12ms | 34.86／16.61ms |
| 準備回の最初のadvance | 200ms以下 | 89.54／39.98ms | 33.48／42.47ms |
| 閉鎖後のfootprint、5回の最大−最小 | 8MiB以下 | 212,992／65,536 bytes | 114,688／32,768 bytes |
| 各表示の生成回数 | File・Worker・表示用Viewが各1、スクロールで増加なし | 各1 | 各1 |
| 停止後の周期advance | 150ms収束待ち後、300ms間に0回 | 0回 | 0回 |
| 復帰初回 | 時間差0 | 0 | 0 |

補助予算は両構成で満たした。再訪時の処理が小さく、Fileの解放も確認できたため、Resourceの画面間共有は導入しない。この比較は交互のA/B/A実行ではなく、基準→変更後の順である。中央値の差から高速化を断定しない。両版のテストログには初期のMetal drawable取得失敗もあり、advance到達を初回描画や空白フレームなしの証明には使わない。

## 実Canvasの契約

[RivePresentationTests](../app/NibbleTests/RivePresentationTests.swift)は固定runtimeのloggerをテスト中だけ接続する。State Machineへテスト側から時計を与える方式ではなく、Canvas自身のadvanceの有無と時間差を観測する。

- ホスト停止・inactive・backgroundを重ね、一つだけ解除しても周期進行しない。すべて解除した最初の時間差は0。
- 可視性の初回通知前と10%未満を停止し、9%／11%の境界を3往復してもSessionと表示用Viewを維持する。スクロール位置の計算はsafe areaを含む。
- 停止中の配色変更は同じSessionへ反映し、表示用Viewの一回の再生成で時間差0。寸法変更は同じ表示用Viewで時間差0。単発描画後に周期進行しない。
- 同時CanvasのSessionとData Bindingは独立。3回の開閉でSession・Rive・File・Worker・表示用Viewのweak参照が解放される。Workerの確認だけは固定runtimeの内部保持をテスト内のMirrorで観測する。
- 実TabView・NavigationStack・fullScreenCoverを使ったhostで、復帰は同じRive、pop後は解放、再訪は新規表示となる。
- ファイル読込失敗後の操作APIによる再試行と、読込中の離脱後に遅れて届く結果の不採用を確認する。
- 読込待ちの間に配色を変更しても、完了時の配色を使う。配色変更後のタブ往復は色と表示用Viewを保持する。

操作APIのテストと、再読み込みボタン→attempt→SwiftUI taskの操作接続は区別する。SwiftUIのアクセシビリティ要素をhost内部から取得する試行は成立しなかったため、ボタン接続は後述の製品画面への故障注入で確認した。途中の失敗runも保持している。

## 配色の回帰と製品画面の観測

最初の故障注入run `20260920T125523Z-rive-about-922a78`では、ダークで復旧した後にライトへ変え、タブを往復すると図だけダークへ戻った。`after-tab.png`と録画81.22秒で不一致を確認した。読込タスクが以前の配色を捕捉していたため、Session公開時の現在の配色を使い、初回配色を適用してからCanvasを生成するよう修正した。読込を保留して配色を変えるテストは`20260920T130342Z-test-fc79e2`で両ホストとも失敗し、最終runでは合格した。修正後の実画面と同位置の画素検査でも、タブ復帰後にライト配色が維持された。

| 最終ソースのrun | 結果と範囲 |
| --- | --- |
| `20260920T130549Z-test-8cf70e` | Release、113テスト・13 suite合格。契約・生成回数・解放・補助予算 |
| `20260920T130800Z-rive-about-b5cbf5` | Aboutの故障注入、実ボタンで復旧、タブ・スクロール・背景往復、配色、本文。161.30秒の録画 |
| `20260920T131134Z-rive-keyboard-d9deb2` | Keyboardの同じ操作。162.41秒の録画 |
| `20260920T131436Z-mvp-ui-c8b032` | 保存・編集・コピー・検索・削除・復元の回帰操作合格 |
| `20260920T131750Z-notice-ui-9cd2d8` | 通知・取り消し・キーボード・シートの回帰操作合格 |
| `20260920T131918Z-fixed-interface-f219cc` | 通常設定と最大文字・高コントラストで固定表示の回帰操作合格 |

故障注入は専用Simulatorへインストールしたアセットのコピーだけを一時的に不正なバイト列へ置き換えた。元のファイルと製品ソースのhashを照合してから注入し、失敗画面を開いたまま元のバイト列を復元し、実ボタンを押した。元・注入・復元のhashと操作順はmanifestの`fault_injection`にある。これは配布物そのままの実行とは区別する。

両画面で代替表示・キャプション・戻るを保持し、ボタンからダーク配色の実イラストへ回復した。ライトへの変更、タブ復帰、3往復のスクロール後にも配色と図が表示された。Keyboardでは通常キーボード、nibble選択、行選択、入力結果と保存行の併存、次周期を画像で確認した。30秒背景復帰直後の画像はOSの切替途中であり、その一枚で停止状態は判定しない。停止理由の合成と周期advanceの不在は契約テストの保証である。

確認した画像・hash・録画時刻・観測は各runの`local-review.json`に記録した。説明画面の録画抽出確認はAboutが7.95・80.76・145.24秒、Keyboardが8.36・80.98・146.13秒。全編再生、VoiceOver音声、媒体公開・ブラウザー閲覧は未実施である。自動操作の合格と、確認した媒体の範囲を相互に代用しない。最終commitとのソース照合には`check_evidence.py --integrity-only`を使う。

## 製品操作の再現手順

専用Simulatorで「設定 > アクセシビリティ > 動作」を開き、[iOS手順](ios-verification.md)に従ってNix環境を使う。次のdriverは同じReleaseアプリをビルド・インストールし、画像・複数周期・復帰を録画する。`--story keyboard`はキーボード説明の制作変更でも共用できる。

```sh
export NIBBLE_UI_FORMAT=json
python3 scripts/check-about-ui.py --device "$NIBBLE_SIMULATOR" --story about --interruptions --fault-retry
python3 scripts/check-about-ui.py --device "$NIBBLE_SIMULATOR" --story keyboard --interruptions --fault-retry
```

表示中の短いドラッグと減速、可視範囲の往復、タブ往復、3秒と30秒のbackground、画面外のままの復帰、ライト／ダーク、Reduce Motion、末尾の文章と戻る操作を同じ順序で記録する。アセット変更時はhashと描画寸法も更新する。driverの成功、画像確認、動画の抽出確認、全編再生は別に記録する。

## 未評価と完了の境界

Time Profilerの5秒接続試行は、45秒の外側期限とSIGINT後5秒の終了待ちでも記録開始・保存を完了せず、終了コード137だった。ログは`artifacts/issue36-baseline-connection.stdout`と`.stderr`、対象は基準runのPID 92505。既知の[Simulator計測障害](performance-verification.md#simulator計測の既知の制約)と同じ停止段階であり、アプリ変更の原因とは断定しない。

最終ビルドでは`20260920T132022Z-rive-hitches-probe-8e4357`で同じ専用SimulatorのPID 16366へAnimation Hitchesを5秒接続した。`Hitches is not supported on this platform.`というエラーで終了し、runは失敗である。保存された`hitches.trace`を測定成功の証跡には使わない。コマンド・診断は同runの`animation-hitches.log`に残した。

したがってhitch時間・比率、画面への初回／復帰表示完了時間、body・Representableの更新時間、CPU、GPU時間、電力は未評価である。hitchと実際の表示完了の予算確定・合格を含むIssue #36全体の性能受入は完了していない。GPU・電力をSimulatorから実機性能へ推定しない。実機は受入範囲に含めない。環境更新後は接続試行を再実行し、iOS 26.5 Simulatorを測定できる手段で実データをexportしてから予算を定め、同条件で比較する。
