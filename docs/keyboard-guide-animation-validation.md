# キーボード説明アニメーションの検証

2026-09-20にIssue #34のS10/C49を検証した。採用した構図と時間は[演出設計](decisions/0004-rive-presentation.md)、再生成と接続契約は[アセット手順](../app/Animations/README.md)を参照する。

## 対象と条件

- 変更前はmainの`7316466036ee5409c361ce59c4d0583bf87bd2a5`。変更後は本書と同じコミットの実装。各runの開始・終了入力hashとコミット後の照合で対応させる。
- 制作ソース`keyboard/scene.rml` SHA-256: `24cb23d392b76194c0cbcccdc2a2d63479509860bad9e3724382ab6ac4d0f3d5`。
- 配布用`keyboard-story.riv` SHA-256: `9a8ca87f2915372164fbb321626866be7da6f58319a3b957031b8e26677f5633`。
- Rive CLI 1.0.4、rive-ios 6.27.0、macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2。
- 専用iPhone SE（第3世代）、375×667 pt、iOS 26.5（23F77）、UDID `04A79414-64A7-4167-9B1D-998F18DB9DA6`。アプリはRelease/arm64 Simulator、ダミーデータ。署名配布archiveや実機の測定ではない。

## 自動検査

`verify.py run --base origin/main`の計画で、次の全6工程が成功した。結果は`artifacts/issue-34/verification-accepted/result.json`。実行中のソースは固定し、各runの開始・終了入力も一致した。

| 工程 | 結果・run ID |
| --- | --- |
| static | `nix flake check --no-update-lock-file --print-build-logs`成功（7 checks） |
| product-test | `20260920T110753Z-test-69c979`。105 tests / 122 parameter executions、失敗・skip 0 |
| mvp | `20260920T110812Z-mvp-ui-c87080` |
| notice | `20260920T111133Z-notice-ui-65258a` |
| interface | `20260920T111304Z-fixed-interface-8e1977` |
| about | `20260920T111348Z-rive-about-c15480` |

実バイナリのテストは、型付きの7プロパティ、初期値、色の書き込みと読み戻し、独立したSession、静止状態からの復帰と2周期超の進行、型不一致の拒否を確認する。UIへ実際のRiveUIViewを載せるテストでは、スクロールで停止・再開、停止中の色変更とSession保持、背景停止と復帰、離脱時のwindow切離し、開き直した独立Sessionを確認する。

CLI inspectの問題は0件。CLIレンダリングの0秒と8.4秒のPNG hashは一致した。これはタイムラインの境界の同一性を補うが、iOS録画の全編再生を代替しない。

## 画面・媒体の観測

すべて`artifacts/ios/<run ID>/`に保存。画像はローカルで開いて確認した。動画はAVFoundationで抽出したフレームを確認し、全編連続再生はしていない。外部公開・ブラウザーでの媒体閲覧は未実施。

| run ID | 結果と確認した条件 |
| --- | --- |
| `20260920T103730Z-keyboard-guide-before-ce7ff3` | 変更前のビルドとライト/ダーク画像。導入文から追加手順へ続く文章だけの画面 |
| `20260920T105259Z-keyboard-guide-af93e3` | 変更後のビルド、全段落到達、標準戻る・再入場、背景復帰、表示中のReduce Motion変更、最大文字/高コントラストでも固定表示、説明のAX情報。録画はスクロール位置により図の上端が画面外となるため、図全体の評価は次のrunを使う |
| `20260920T105555Z-keyboard-guide-loops-099585` | 図全体を収め、ライト約26秒・ダーク約20秒の連続録画。初期Reduce Motion有効で再入場しても再生。`light-complete-figure.png`、`dark-complete-figure.png`、`recording.mp4`が主媒体 |
| `20260920T105744Z-keyboard-guide-retry-3f121d` | install済みBundleの新アセットだけを一時退避し、説明文と再読み込みを確認。復元後の再読み込みでボタンが消える。製品ソースへ障害を残さない |
| `20260920T110648Z-keyboard-guide-retry-visible-d9b266` | 同じ失敗条件で再試行し、復旧後に図の位置へ戻して実際の描画も確認。`retry-visible-figure.png` |

主録画は46.69秒。31時点の実際の抽出時刻と画像を`artifacts/issue-34/loop-frames/video.json`、`sheet-0.png`〜`sheet-3.png`へ保存した。ライト約3周期、ダーク約2周期をまたいで、地球儀からの切替、行の主領域のタップ、入力先への本文の出現、保存行の原文保持、結果保持、全体フェードを観測した。確認時点に図の重なりはなかった。周期境界の全フレームでの滑らかさは未評価。

短い説明は図から独立し、AXラベルに操作順、原文保持、入力先への反映確認を含む。図はhit testingとAXを無効にし、製品モデル・保存・クリップボード・実際の入力先へ接続しない。既存の追加手順、フルアクセス、入力先の制約は文言を保持し、下端までスクロールできた。VoiceOverの実音声・フォーカス移動と初見利用者の理解度は未評価で、[G15](design/audit.md)に残す。

## 容量と負荷

変更前後のRelease/非testableのNibble.appを同じ条件で保存し、dSYM・テスト・DerivedDataを含めず比較した。全ファイルの差分は`artifacts/issue-34/bundle-delta.json`。

| 対象 | 変更前（byte） | 変更後（byte） | 増分（byte） |
| --- | ---: | ---: | ---: |
| Nibble.app全体 | 15,497,249 | 15,685,512 | 188,263 |
| 本体実行ファイル | 2,848,320 | 2,917,312 | 68,992 |
| 新Riveアセット | 0 | 119,049 | 119,049 |
| CodeResources | 7,141 | 7,363 | 222 |

全体の増分は約184 KiB（1.21%）。Keyboard/Share拡張、既存アセット、runtimeは内容まで同一。Simulator用bundleの比較であり、App Store配布サイズへ換算しない。

同一Simulator・ダミーデータ・ライト/標準文字/標準コントラストで、設定→キーボード案内→40ptのスクロールを共通操作とした。変更前→変更後を3組交互にinstall/起動し、10秒ウォームアップ後の18秒を測定。対象PIDと起動時刻・実行ファイルを照合し、`ps`のCPU累積時間差を実経過時間で割った。個別サンプルとコマンドは`artifacts/issue-34/cpu-comparison/`に保存。前後の実行ファイルSHA-256も結果JSONに含む。

| 指標 | 変更前 | 変更後 |
| --- | --- | --- |
| 1コアに対するプロセスCPU、3回の範囲 / 中央値 | 0.00% / 0.00% | 5.67〜5.94% / 5.88% |
| 区間末のプロセスRSS、3回の範囲 / 中央値 | 335.56〜336.64 / 336.61 MiB | 351.33〜351.66 / 351.47 MiB |

描画中はCPU約5.88ポイント、RSS中央値約14.86 MiBの増加を観測した。変更後の同じプロセスで図を画面外へスクロールし、10秒後から18秒を追加測定するとCPU累積値は変化しなかった（1回、0.01秒分解能内）。RSSは約351.48 MiBでSessionを保持する。上記はCPUプロセス時間とRSSの測定で、GPU・フレーム時間・hitch・電力・実機性能ではない。描画の性能予算への合格は判定しない。

Time Profilerは同じSimulatorと照合済みPIDへ5秒記録を要求し、45秒の外側期限と5秒の終了猶予で打ち切られた（終了-9）。記録開始の表示の後、正常停止・保存・exportへ到達せず、比較に使えるサンプルなし。ログとコマンドは`artifacts/issue-34/profile-probe/`。フレーム時間・GPU・hitchは[既知の環境制約](performance-verification.md#simulator計測の既知の制約)と分けて未測定として残す。

## 途中の失敗と適用限界

- 最初の追加UIテストは、windowから外れたRiveUIViewの`isPaused`を停止の判定に使って失敗した。runtimeのwindow離脱によるクロック停止と明示的pauseは別の境界だったため、window切離しと再入場時の独立Sessionを検査するよう修正した。失敗run `20260920T104652Z-test-eef112`を保持する。
- 検証中に文書を更新し、生成用buildのGit除外漏れを発見したため、その一連の実行を中断した。`20260920T104915Z-mvp-ui-1b509a`は失敗のまま残し、成功へ変更していない。ソースを固定して最終検証をやり直した。
- 拡張の機能・entitlements・依存版は変更せず、拡張の出力も同一。OS設定でのキーボード追加、共有拡張、secure入力、拒否するホストの再試験は今回の対象外。既存の権限説明を読み、挿入にフルアクセスが必須である表現を追加していない。
