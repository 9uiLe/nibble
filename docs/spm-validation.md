# Swift Package構成の検証

確認日：2026-09-16。対象はnibbleの本体・共有拡張で使うSwift Package構成と、一覧行の比較を行う`SnippetRowContent`。対象ソースは`bd53d99e792241966834f0be2eb711ef0f2868e0`である。採用理由・実装上の契約・ビルド条件は[実装規約](library-policy.md)、製品全体の観測は[検証結果の索引](mvp-validation.md)を参照する。

## 対象の依存構成

Xcode projectのexact version、共有`Package.resolved`、取得したパッケージのソースを照合した。

| パッケージ | バージョン | Git revision |
| --- | --- | --- |
| swift-tasking | 0.3.0 | `4a3eeeedf37e291a7effeba08cad0cd24224d50c` |
| swift-scoped-animation | 0.2.2 | `78b1e6981cd89c313b4d6906f74deb2d02ffff4c` |
| swift-app-macros | 0.3.0 | `9b6d5d699b44990029cdfa61cddf35cec46d1520` |
| swift-syntax | 603.0.2 | `79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` |

直接依存3件の安定版リリースと、AppMacrosのmanifestによるswift-syntaxのexact指定を確認した。ScopedAnimation・AppMacrosのMITライセンスと著作権表記は、製品に含める`ThirdPartyNotices.txt`と整合している。

ソース上の`SnippetRowContent`は`@Equatable`と`@MainActor EquatableBodyView`を宣言し、タイトル・本文プレビュー・ピン状態を通常の`let`入力として持つ。MainActor付きの準拠について、Lintは可変入力・closure・独自body・マクロ欠落・extension準拠を拒否した。型適合と描画の検証状況は下表に示す。

## 環境と結果

| 実行条件 | 値 |
| --- | --- |
| ホスト | macOS 26.2、arm64 |
| Xcode / Swift | Xcode 26.5（17F42）、Swift 6.3.2 |
| Simulator | 専用iPhone 17 Pro、iOS 26.5（23F77） |
| UDID | `D099A849-386F-4EAE-AE12-02D8DC623AF2` |
| ビルド指定 | scheme `Nibble`、製品テスト・基本操作はRelease、通知はDebug、ad hoc署名 |
| 製品設定 | deployment target 26.0、Swift language mode 6、strict concurrency complete、default isolation nonisolated |

| 検証 | 結果 | 記録 |
| --- | --- | --- |
| パッケージ解決 | 表の4件のバージョン・revisionを解決 | `artifacts/package-resolution.log` |
| Nix共通検査 | ローカル5 check成功。Python回帰テスト65件、Swiftソース29件の規約検査を含む | `artifacts/nix-package-final.log` |
| Releaseビルド・製品テスト | 42件成功、失敗・skipなし。パラメータ展開後43実行 | run `20260916T032846Z-test-93c9c4` |
| 基本操作のUI検証 | 成功。下書き再開・保存・検索・編集・原文コピー・pin・削除・同一UUIDのUndo・破棄を確認 | run `20260916T101304Z-mvp-ui-764740` |
| Debug通知・Reduce Motion | 無効・有効の両方で通知表示・2.3秒後の消去・編集開閉が成功。設定を初期状態の無効へ復元 | 下記のDebug run |
| 通知トリガーの解決処理 | 同一端末・Release最適化で0.2.1と0.2.2を比較。詳細は下記 | `artifacts/package-performance/result.json` |
| GitHub Actions | Ubuntuの共通検査とPR本文検査。実行状態は対象PRのChecksを参照 | iOSの実行検証は上記ローカルrunで評価 |

runは1回の検証実行を指す。manifest・ログ・xcresultは`artifacts/ios/<run>/`へ保存する。Releaseテスト・基本操作・Debug通知の各runの開始・終了時の検証入力は、対象ソースとファイルhashが一致した。行の全入力の比較、マウント済みViewの変更・復元、同一入力での外観・文字サイズの更新を含む。

### ビルドホストとテストログの観測

初回run `20260916T015640Z-test-a1ce49`は、更新した`AppMacrosMacros`の承認が必要というXcode診断で中止した。固定revisionとマクロ展開ソースを確認し、Xcodeで対象のrevisionを有効にした後、上表のReleaseテストが成功した。全マクロの検証を無効にする設定は使用していない。

成功runにはコピーしたDerivedDataの古いパスに関する警告と、AppIntents metadata抽出の対象がない旨の警告がある。また使い捨てDBの後片付けでSQLiteの`vnode unlinked while in use`が出る。SQLiteの診断は更新前のrun `20260916T013623Z-test-a80994`にも存在し、テスト用DBを接続の解放前に削除する後片付けに対応する。警告のない実行とは報告しない。

## Simulatorの操作検証

### 基本操作と通知

標準UI driverのrun `20260916T101304Z-mvp-ui-764740`で、新規作成→閉じる→下書き再開→保存→日本語検索→編集→コピー→pin→削除→Undo→下書き破棄を実行した。作成したUUIDを編集・復元後も保持し、コピーは改行・空白・結合文字を含むUTF-8で原文と一致した。破棄後の保存済み本文も一致した。既存項目は保持し、ダミーデータのみを操作した。

| Debug条件 | run | 結果 |
| --- | --- | --- |
| Reduce Motion無効 | `20260916T101819Z-package-notice-disabled-1caf35` | 通知表示・2.3秒待機後の消去・編集開閉が成功 |
| Reduce Motion有効 | `20260916T102207Z-package-notice-enabled-3a9374` | 同じ操作と表示状態の照合が成功 |

Debugの補助driver `artifacts/check-package-notice.py`は共通の`Run`でビルド・起動・ソース照合・撮影を行い、自身のhashとSettingsの観測をmanifestへ記録した。Settingsの`REDUCE_MOTION`をvalue 0/1で照合し、検証後は初期状態の0へ戻した。通知の通常0.16秒・有効時0秒という指定は実装上の条件であり、今回の抽出フレームから遷移時間を測定したものではない。

2026-09-16 19:18:19〜19:23:00 JSTのSimulator統合ログをinfo/debug込みで取得した。Nibble / NibbleShareのScopedAnimationカテゴリと`Unhandled ViewTaskStore`に該当する記録は0件だった（`artifacts/package-debug-diagnostics.json`）。一覧と編集内部の診断、入力barrierを通る今回の通知・編集開閉が対象で、共有拡張は実行していない。OSのシートtransactionは外側のbarrierで遮断する。全導線の診断がないことを示す結果ではない。

一覧・下書き再開・通知表示と消去のPNGを開き、録画は次の時刻の抽出フレームを確認した。タイトル・本文・pin・コピー操作が表示され、確認した画面に操作を妨げる重なりはなかった。

| 録画 | 原本の長さ（秒） | 確認した抽出時刻（秒） |
| --- | --- | --- |
| 基本操作 | 93.412 | 4.860、46.343、83.198 |
| Reduce Motion無効 | 10.757 | 0、7.068、9.127 |
| Reduce Motion有効 | 12.428 | 0、8.030、10.485 |

全編の連続再生、全フレームのhitch評価、VoiceOver実操作、今回の構成での日本語IME変換・小画面・最大文字の操作は未実施。録画時間にはdriverの待機と画面読取を含む。比較Viewの外観・文字サイズへの追従は製品テストで評価した。画像・録画の共有URLとブラウザー閲覧条件は対象PRと各runの`review.json`に記録する。

### 実行基盤が停止したrun

以下は同日の成功runより前の失敗記録である。各runのビルドは成功したが、Simulator操作の座標変換エラー・タイムアウトで操作検証を中止した。

| run | 観測 |
| --- | --- |
| `20260916T033756Z-mvp-ui-a69447` | 一覧の撮影後、新規作成のタップでsim-useの`No translation object returned for simulator`が発生 |
| `20260916T034112Z-mvp-ui-c80012` | 新規本文を入力して下書きに保存。再開のタップで同じ座標変換エラーが発生 |
| `20260916T034321Z-mvp-ui-32d952` | 検証用wrapperでタップ前0.5秒・後0.3秒の待機を追加。判定は標準driverと同一だが、下書き再開のタップが60秒でタイムアウト |
| `20260916T034626Z-mvp-ui-056e0c` | 専用Simulatorをデータを保持して再起動。標準driverのアプリinstallが60秒でタイムアウト |
| `20260916T041557Z-mvp-ui-193409` | 作業再開後の標準driver。Releaseビルドは成功したが、アプリinstallが再び60秒でタイムアウト |

初めの座標変換エラー後、Settingsで「視差効果を減らす」が無効であることを確認し、アプリの空の編集画面を閉じられた。しかし専用端末の再起動後はAppleのSettingsの起動も応答しなくなった。専用端末のrunningboardサービスを再起動しても、Settingsの起動は回復しなかった。

新規の専用iPhone 17 Pro / iOS 26.5 Simulator（`31DA9A52-C6C0-4F37-9326-352CD49B12A5`）は作成できたが、起動が`launchd failed to respond`で失敗した。作業再開時にもこの端末のbootが45秒でタイムアウトした（`artifacts/package-simulator-resume-boot.log`）。この端末では製品を実行していない。既存データのerase、他のSimulatorの停止、Mac全体のサービス再起動は行っていない。

これらの部分的な入力・画像・録画を成功runへ合算していない。上記の基本操作とDebug通知は、ホスト再起動後に標準driverと補助driverをそれぞれ最初から実行して取得した独立の結果である。

## 通知トリガーの処理時間

`Library.Notice`が使うBoolean 1件と`.easeOut(duration: 0.16)`を条件に、ScopedAnimation 0.2.1と0.2.2の履歴解決処理を比較した。上表の同一Simulator、Swift 6.3.2、iOS 26.5 SDK、arm64、`-O`、Swift language mode 6で、各revisionの変更していないSwiftソースと共通の測定コードをコンパイルした。内部APIの呼出名と採用indexの参照だけを版ごとに切り替える。

2つのsnapshotを事前に作り、同じ値を繰り返す条件と、false/trueを交互に解決する条件を測る。各プロセスで1,000回の準備実行後、200,000回を1標本として7標本取得した。実行順は0.2.1→0.2.2→0.2.2→0.2.1、各版14標本。結果のchecksumを検査し、各標本の1操作あたり時間を集計した。

| 条件 | 0.2.1 中央値（最小〜最大）ns | 0.2.2 中央値（最小〜最大）ns |
| --- | --- | --- |
| 同じ値の再評価 | 8.80（8.53〜9.11） | 86.28（83.90〜89.92） |
| 通知状態の変化 | 345.84（339.38〜361.93） | 180.33（179.39〜202.22） |

同じsnapshotの再評価は約77ns増え、状態変化時は約166ns減った。通知1件のこの処理はいずれも1µs未満であり、通知処理のCPU時間を理由に採用を見送る結果ではない。無変化時の増加を含むため、一律の高速化・非劣化とはしない。snapshot構築、SwiftUIのlayout・描画、操作全体の遅延、hitch、メモリ、電力はこの測定に含まない。事前構築したsnapshotの再利用による最適化も結果に含まれる。

ソースrevision、コンパイル引数、測定コードのhash、CSV、集計結果は`artifacts/package-performance/`へ保存した。この測定は通知の内部処理に限定した補助評価であり、実機性能を示さない。

## 再現手順と受け入れ条件

リポジトリルートで次を実行する。パッケージの取得とXcodeによる対象マクロの有効化は[セットアップ](../README.md#3-xcodeとswift-packageを準備する)に従う。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
nix flake check --no-update-lock-file --print-build-logs
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
nix develop --command python3 scripts/check-mvp-ui.py \
  --device D099A849-386F-4EAE-AE12-02D8DC623AF2
```

別のMacでは、端末一覧から選んだ専用iOS 26.5 SimulatorのUDIDを指定する。

製品テストでは表示入力の等価比較、マウント済みViewの変更・復元、同じ入力での外観・文字サイズへの追従を確認する。UI driverでは作成・下書き再開・保存・検索・編集・コピー・ピン留め・削除取り消し・下書き破棄を確認する。

[MVP手順](mvp.md#タスクの寿命とアニメーション)に従い、Debugで通知の表示・消去、Reduce Motion、アニメーション診断を確認する。対象の画像・録画を確認・添付し、[証跡検査](review-evidence.md)でソースと媒体を照合する。これらの実行結果と閲覧可能な証跡がそろうことをiOS検証の受け入れ条件とする。実機・署名配布はMVPの受け入れ範囲外である。
