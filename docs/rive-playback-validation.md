# 説明イラストの再生と資源利用の評価

「nibbleについて」の説明イラスト（S05・C44）と、「nibbleキーボード」の説明イラスト（S10・C49）を対象に、停止・復帰、配色、読込と回復、画面を閉じた後の資源解放を評価する。採用仕様は[演出設計](decisions/0004-rive-presentation.md)、APIは[RivePresentation](../app/Packages/RivePresentation/README.md)、操作手順は[製品の検証手順](ios-verification.md#説明イラストの検証)にある。

本記録の製品ソースは `4a467c3887405c9394440a25d50fe03aa9d2162b`、評価日は2026-09-20である。再生状態と寿命の契約、読込失敗からの回復、補助指標を確認している。画面への表示完了時間やスクロールの引っかかりを含む性能受入は未完了で、[G16](design/audit.md#g16-c--説明画面の再生とスクロールの性能)の評価対象である。

## 測定対象と条件

| 条件 | 値 |
| --- | --- |
| 実行環境 | macOS 26.2、Apple M1 Pro、16GiB、Xcode 26.5 (17F42)、Swift 6.3.2 |
| Simulator | 専用iPhone SE (3rd generation)、iOS 26.5 (23F77)、UDID `04A79414-64A7-4167-9B1D-998F18DB9DA6` |
| 構成 | Release、-Osize、whole-module。契約テストはENABLE_TESTABILITY=YES |
| アセット | about-story.riv：80,316 bytes、keyboard-story.riv：119,049 bytes。内容のhashはrunのmanifestへ保存 |
| runtime | rive-ios 6.27.0、revision `4c42e5839167a06a56d336e80813578bac018dde` |
| 表示 | 375×667ptのhost window、ライト、scale 2。実画面の図はAboutが幅327pt、Keyboardが幅335pt。通常はCanvas 1個、独立性テストは2個 |
| データと操作 | ダミーDB。説明画面を開く→350ms再生→末尾へスクロールして停止→先頭へ戻る→閉じる |
| 反復 | 各アセットの準備1回と再訪5回。serialized suiteで実行し、OS・Metalのキャッシュは消去しない |
| 観測負荷 | テスト中だけRiveLog collectorを接続し、10ms間隔で状態を待つ。補助指標の測定中は録画・Instrumentsを使わない |

測定値は `artifacts/ios/20260920T130549Z-test-8cf70e/` のmanifestとattachmentsに対応する。manifestは実行前後の入力hash、端末、toolchain、コマンドを記録し、attachmentsは `rive-playback-measurements.json` の生値を持つ。成果物はGit管理外の `artifacts/` に保存する。ソース・実行結果・媒体の照合は[証跡手順](review-evidence.md)に従う。

## 補助指標と適用範囲

advanceはruntimeによるフレーム評価を指す。評価後に画面へ描画されるまでの時間は含まない。次の予算は読込・再生制御・保持量を確認するためのもので、描画性能の合否予算ではない。

| 指標 | 補助予算 | About | Keyboard |
| --- | --- | --- | --- |
| View配置から最初のadvance、再訪5回の中央値／最大 | 各回100ms以下 | 28.46／35.42ms | 25.11／31.57ms |
| 可視復帰要求から最初のadvance、再訪5回の中央値／最大 | 各回100ms以下 | 12.99／34.86ms | 16.43／16.61ms |
| 準備回の最初のadvance | 200ms以下 | 33.48ms | 42.47ms |
| 画面を閉じた後のfootprint、再訪5回の最大−最小 | 8MiB以下 | 114,688 bytes | 32,768 bytes |
| 各表示で生成するFile・Worker・表示用View | 各1、スクロールでは増加しない | 各1 | 各1 |
| 停止後の周期advance | 150msの収束待ち後、300ms間に0回 | 0回 | 0回 |
| 復帰初回のadvance | 時間差0 | 0 | 0 |

この条件では補助予算を満たしている。画面ごとの読込と解放を使う設計の評価資料として扱う。

準備回はプロセスのcold launchではない。別のテストやOSキャッシュの影響があるため、初回表示速度の指標に使わない。footprintは `task_info` によるプロセス全体の物理メモリ使用量であり、Workerだけの確保量ではない。解放の確認には、メモリ量とオブジェクトのweak参照の消失を併用する。ログには初期のMetal drawable取得失敗があり、advance到達を実際の描画完了や空白フレームがないことの証明には使わない。

## 再生状態と寿命の検証

現在の回帰契約を担う[RivePresentationTests](../app/NibbleTests/RivePresentationTests.swift)は実アセットを読み込み、実Canvasのフレーム評価をruntimeのloggerで観測する。再生用の時計をテスト側から与えず、Canvas自身の停止と復帰を確認する。

| 対象 | 確認した条件 |
| --- | --- |
| 停止理由の合成 | ホストの停止要求とinactive・backgroundが重なった状態で、一つだけ解除しても周期進行しない。すべて解除した最初の時間差は0 |
| 可視性 | 初回通知前と10%未満で停止する。safe areaを含めて9%／11%を往復し、Sessionと表示用Viewを保持する |
| 配色と寸法 | 停止中の配色変更は同じSessionと一度の表示用View生成で反映する。寸法変更は同じ表示用Viewで反映する。単発描画の時間差は0で、周期再生は開始しない |
| 表示の独立性と解放 | 同時CanvasのSessionとData Binding値が独立する。画面を閉じるとSession・File・表示用Viewのweak参照が消失する |
| 画面の寿命 | TabView・NavigationStack・fullScreenCoverを使い、タブとシートからの復帰では同じRive、戻る操作で閉じた後は解放、再訪では新規生成となる |
| 読込と取消 | 読込失敗から操作APIで再試行できる。離脱による取消後に遅れて届く結果を採用しない |
| 配色の適用時点 | 読込中に外観を変えた場合は完了時の配色を使う。配色変更後のタブ往復で色と表示用Viewを保持する |

所有するSession・File・表示用Viewの解放を通常回帰で確認する。反復時の累積保持は[専用の性能target](../app/NibblePerformanceTests/RivePlaybackMeasurements.swift)でprocess footprintを測り、外部runtimeの私有フィールド名を回帰条件にしない。

## 製品画面の観測

製品画面の操作記録はAboutが `20260920T130800Z-rive-about-b5cbf5`、Keyboardが `20260920T131134Z-rive-keyboard-d9deb2` である。両runは冒頭の製品ソースに対応するReleaseビルドを使い、専用Simulatorで故障回復・外観変更・タブ移動・スクロール・背景復帰を実行している。

読込失敗は、インストール済みアセットのコピーを一時的に不正なバイト列へ置き換えて作る。注入前に製品ソースとのhashを照合し、失敗画面を開いたまま元のバイト列を復元して実ボタンを押す。元・注入・復元のhashと操作順はmanifestの `fault_injection` に記録する。この条件で、ボタンから読込taskを経由して図を表示するまでの接続を確認する。

両画面で代替表示・キャプション・戻る操作を保持し、再読み込みボタンから現在のダーク配色の実イラストへ回復することを確認した。ライトへの変更、タブ復帰、3往復のスクロール後も図と配色を確認した。Keyboardでは通常キーボード、nibble選択、行選択、入力結果と保存行の併存、次周期を画像で確認した。

媒体の観測範囲は各runの `local-review.json` に、ファイルhashとともに記録している。録画の抽出確認はAboutが7.95・80.76・145.24秒、Keyboardが8.36・80.98・146.13秒である。30秒の背景滞在から復帰する直後の画像はOSの切替途中であり、その画像から停止状態は判定できない。停止理由の合成と周期advanceの不在は契約テストの確認範囲である。

全編再生、VoiceOver音声、媒体公開・ブラウザー閲覧は未実施である。自動操作の成功、画像の確認、録画の抽出確認、公開媒体の閲覧はそれぞれ別の記録として扱う。

## 未評価の性能と計測環境

hitchは、画面更新が描画期限に間に合わず生じる引っかかりを指す。hitchの時間・比率、画面への初回／復帰表示完了時間、SwiftUI body・UIViewRepresentableの更新時間、CPU・GPU時間、電力は未評価である。hitchと表示完了時間の予算を確定して判定するまで、説明画面の性能受入は完了としない。

この環境の計測には次の制約がある。

| 計測方法 | 対象と観測 | 記録 |
| --- | --- | --- |
| Time Profiler | 基準ソース `99050be923596ac9d6eee9340b43cde8988e493a` のSimulatorプロセス。5秒の記録が45秒の外側期限とSIGINT後5秒の終了待ちでも完了せず、終了コード137 | `artifacts/issue36-baseline-connection.stdout` と `.stderr` |
| Animation Hitches | 冒頭の製品ソースのSimulatorプロセスへの5秒接続。`Hitches is not supported on this platform.` で失敗 | `artifacts/ios/20260920T132022Z-rive-hitches-probe-8e4357/animation-hitches.log` |

Time Profilerの状態は[Simulator計測の既知の制約](performance-verification.md#simulator計測の既知の制約)に該当する。Animation Hitchesが保存したtraceは失敗した記録であり、測定成功の証跡には使わない。これらの観測から製品実装が原因とは判定できない。

環境や計測手段を変更した場合は、iOS 26.5 Simulatorで記録・exportが成立することを短時間の接続で確認する。実データを得てから描画性能の予算を定め、同条件で比較する。実機は製品の受入範囲に含めず、Simulatorの値から実機のGPU性能や電力を推定しない。
