# キーボード説明アニメーションの検証

設定内の「nibbleキーボード」画面（S10）にある説明イラスト（C49）について、表示、再生の寿命、読込失敗からの回復、容量と負荷を評価した。図は「キーボード切替→保存済み行のタップ→本文挿入」を8.4秒で繰り返し、入力先と保存元に本文が残る関係を示す。設計は[説明イラスト](decisions/0004-rive-presentation.md)、制作と接続は[アセット手順](../app/Animations/README.md)を参照する。

## 対象ソースと実行条件

検証日は2026-09-20。基準版は説明図を持たない`7316466036ee5409c361ce59c4d0583bf87bd2a5`、評価版の製品実装は`8ebb38e85f9b7fbda18b6be02e65780d60a16e94`である。各runは一回のiOS実行のソース・端末・コマンド・成否・媒体をまとめた記録で、`artifacts/ios/<run ID>/`に保存する。runの開始・終了入力hashと、レビュー対象revisionの入力ファイルを照合する。

| 条件 | 値 |
| --- | --- |
| 制作ソース | `app/Animations/keyboard/scene.rml`、SHA-256 `24cb23d392b76194c0cbcccdc2a2d63479509860bad9e3724382ab6ac4d0f3d5` |
| Bundle内アセット | `keyboard-story.riv`、SHA-256 `9a8ca87f2915372164fbb321626866be7da6f58319a3b957031b8e26677f5633` |
| 制作・表示環境 | Rive CLI 1.0.4、rive-ios 6.27.0 |
| ビルド環境 | macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2、Release/arm64 Simulator |
| 専用端末 | iPhone SE（第3世代）、375×667 pt、iOS 26.5（23F77） |
| UDID | `04A79414-64A7-4167-9B1D-998F18DB9DA6` |
| データ | 検証専用のダミーデータ。図中の文章はアセットに定義した架空の例 |

## 自動検査の結果

`verify.py run --base origin/main`で選択した全6工程が成功した。計画と結果は`artifacts/issue-34/verification-accepted/result.json`に保存し、実行中のソースと各runの開始・終了入力が一致することを確認した。

| 工程 | 確認範囲・結果 | run ID |
| --- | --- | --- |
| 共通静的検査 | `nix flake check --no-update-lock-file --print-build-logs`、7 checks成功 | iOS実行なし |
| 製品テスト | 105 tests / 122 parameter executions、失敗・skip 0 | `20260920T110753Z-test-69c979` |
| MVP操作 | 作成、編集、検索、コピー、削除、取り消し、ごみ箱復旧など | `20260920T110812Z-mvp-ui-c87080` |
| 通知表示 | 結果通知と操作領域の回帰確認 | `20260920T111133Z-notice-ui-65258a` |
| 固定表示 | 通常設定と最大文字・高コントラスト設定 | `20260920T111304Z-fixed-interface-8e1977` |
| 保存の説明図 | 「nibbleについて」の表示・再生・寿命の回帰確認 | `20260920T111348Z-rive-about-c15480` |

キーボード説明の実バイナリテストでは、7プロパティの名前と型、初期値、配色の書込と読戻し、独立したSession、静止状態からループへの復帰、2周期超の進行、型不一致の拒否を確認した。

実際のRiveUIViewをSwiftUIへ載せたテストでは、画面外停止と復帰、停止中の配色変更とSession保持、バックグラウンド停止と復帰、View離脱時のwindow切離し、再入場時の独立Sessionを確認した。明示的なpauseと、windowから外れた際のruntimeによるクロック停止は、それぞれの状態で判定する。

CLI inspectの問題は0件。CLIで出力した0秒と8.4秒のPNG hashは一致した。この一致はタイムライン境界の同一性を補う証拠で、iOSの全フレームの滑らかさを証明するものではない。

## 画面と回復動作の観測

| 確認項目 | 観測 | run ID・媒体 |
| --- | --- | --- |
| 基準版の画面 | 導入文から追加手順へ続く文章だけの画面をライト／ダークで確認 | `20260920T103730Z-keyboard-guide-before-ce7ff3`、`before-light.png`・`before-dark.png` |
| 図全体と操作順 | 小画面内で図全体と短い説明を表示。切替、行タップ、挿入、原文保持、結果保持、全体フェードを観測 | `20260920T105555Z-keyboard-guide-loops-099585`、`light-complete-figure.png`・`dark-complete-figure.png`・`recording.mp4` |
| 表示設定と画面の寿命 | 初期からReduce Motionを有効にしても再生。表示中の設定変更、背景復帰、標準戻る・再入場、最大文字・高コントラストでの固定表示を確認 | `20260920T105555Z-keyboard-guide-loops-099585`、`20260920T105259Z-keyboard-guide-af93e3` |
| 文章の到達性 | 追加手順、フルアクセス、入力先の制約を下端までスクロールして読め、説明文のアクセシビリティ情報を取得できた | `20260920T105259Z-keyboard-guide-af93e3` |
| 読込失敗と再読み込み | 専用Simulatorのinstall済みBundleからkeyboard-story.rivだけを一時退避。説明文と再読み込みボタンを確認し、アセット復元後の再試行で図の描画へ復旧 | `20260920T110648Z-keyboard-guide-retry-visible-d9b266`、`failure-caption-and-retry.png`・`retry-visible-figure.png` |

主録画は46.69秒で、ライト約26秒・ダーク約20秒を含む。AVFoundationで抽出した31時点を画像として開き、ライト約3周期とダーク約2周期をまたいで操作と結果の順序を確認した。抽出した時点に図の重なりはなかった。実際の抽出時刻と画像は`artifacts/issue-34/loop-frames/video.json`と`sheet-0.png`〜`sheet-3.png`に保存する。動画の確認方法は抽出フレームであり、全編連続再生ではない。

図はhit testingと読み上げを無効にし、製品モデル・保存・クリップボード・実際の入力先へ接続しない。隣接する説明文のAXラベルに、操作順、原文保持、入力先への反映確認を含める。失敗試験はinstall済みBundleへの一時的な障害注入で行い、製品の制作ソース・配布物には障害を残さない。

図の全体表示には`keyboard-guide-loops`の媒体を用いる。`keyboard-guide-af93e3`の録画はスクロール位置により図の上端が画面外にあるため、全段落到達と画面遷移の証跡として扱う。補助的な失敗回復run `20260920T105744Z-keyboard-guide-retry-3f121d`は、再試行ボタンの消失までを確認した記録として保持する。

## 容量とプロセス負荷

基準版と評価版のRelease/非testableのNibble.appを同条件で保存し、dSYM・テスト・DerivedDataを含めず比較した。全ファイルの差分は`artifacts/issue-34/bundle-delta.json`に保存する。

| 対象 | 基準版（byte） | 評価版（byte） | 増分（byte） |
| --- | ---: | ---: | ---: |
| Nibble.app全体 | 15,497,249 | 15,685,512 | 188,263 |
| 本体実行ファイル | 2,848,320 | 2,917,312 | 68,992 |
| keyboard-story.riv | 0 | 119,049 | 119,049 |
| CodeResources | 7,141 | 7,363 | 222 |

全体の増分は約184 KiB（1.21%）。Keyboard/Share拡張、about-story、runtimeの内容は一致した。値はSimulator用bundleの比較で、App Store配布サイズへは換算しない。

CPUとメモリは同じSimulator・ダミーデータ・ライト／標準文字／標準コントラストで測定した。共通操作は設定→キーボード案内→40ptのスクロールとし、基準版→評価版を3組交互にinstall・起動した。各回10秒のウォームアップ後、18秒の測定区間を設けた。

対象PID、起動時刻、実行ファイルを照合し、`ps`のCPU累積時間差を実経過時間で割った。メモリは区間末のプロセスRSSを採用した。個別サンプル、コマンド、両実行ファイルのSHA-256は`artifacts/issue-34/cpu-comparison/`に保存する。

| 指標 | 基準版：3回の範囲 / 中央値 | 評価版：3回の範囲 / 中央値 |
| --- | --- | --- |
| 1コアに対するプロセスCPU | 0.00% / 0.00% | 5.67〜5.94% / 5.88% |
| 区間末のプロセスRSS | 335.56〜336.64 / 336.61 MiB | 351.33〜351.66 / 351.47 MiB |

表示中はCPU中央値が約5.88ポイント、RSS中央値が約14.86 MiB増加した。評価版の同じプロセスで図を画面外へスクロールし、10秒後から18秒を測るとCPU累積値は変化しなかった（1回、0.01秒分解能内）。RSSは約351.48 MiBで、Sessionは保持される。

Time Profilerは同じSimulatorと照合済みPIDへ5秒記録を要求したが、45秒の期限と5秒の終了猶予で打ち切られた（終了-9）。正常停止・保存・exportが成立せず、比較に使えるサンプルはない。コマンドとログは`artifacts/issue-34/profile-probe/`に保存する。[Simulator計測の既知の制約](performance-verification.md#simulator計測の既知の制約)も参照する。

## 未確認項目と証跡の適用範囲

- VoiceOverの実音声・フォーカス移動、初見利用者の理解度、読書への干渉は未評価。[G15](design/audit.md)で評価条件を管理する。
- 動画は抽出フレームを確認した。全編連続再生と周期境界の全フレームでの滑らかさは未評価。公開先とブラウザー閲覧条件は各媒体のreview.jsonで別に記録する。
- CPUプロセス時間とRSSの値から、GPU・フレーム時間・hitch・電力・実機性能は判定しない。描画の性能予算への合格は未判定。
- 拡張の機能・entitlements・依存版は評価版の変更対象に含まず、拡張の出力は基準版と一致する。OS設定でのキーボード追加、共有拡張、secure入力、拒否するホストの操作は、この検証の対象外。
- 合格の根拠は上記の成功runと照合結果に限定する。失敗run `20260920T104652Z-test-eef112`と中断run `20260920T104915Z-mvp-ui-1b509a`は原記録を保持し、成功の根拠には含めない。
