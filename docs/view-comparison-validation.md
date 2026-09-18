# View比較の検証

比較の宣言、入力の差し替え、SwiftUIが所有する状態の更新を検査する。実装の契約は[Viewの比較境界](library-policy.md#viewの比較境界)、実操作と証跡の要件は[製品検証](mvp.md)を参照する。

## 対象

| 領域 | View | 比較の方式 |
| --- | --- | --- |
| 本体の入口 | LibraryView、SceneInterfaceDefaults | 親からのStore・effectsはrevision、状態を持たないUIKit接続はMainActorのマクロ比較 |
| 一覧・検索・削除 | LibraryScreen、DeletedSnippetsView、LibraryFilterBar | 外部モデル・Focus / Filter Bindingはrevision、所有するStateはSwiftUIで更新 |
| 行・通知 | SnippetRow、SnippetRowContent、LibraryNotice | 操作とモデルはrevision、行の表示値はEquatableBodyView |
| 設定 | LibrarySettingsView | 設定のBindingと画面を開く操作はrevision |
| 製品情報 | AboutView、AboutSection、AboutURL、AboutIllustration | generic contentはrevision、URLの表示値はEquatableBodyView、演出のState・EnvironmentはSwiftUIで更新 |
| 共通編集 | SnippetEditor（本体・共有拡張） | 終了callbackはrevision、EditorModelと入力・タスクの寿命はState |
| 再利用Package | RiveCanvas | Sessionとホスト設定はrevision、画面寿命・scenePhaseはSwiftUIで更新 |

自作Viewは15型。App、ViewModifier、UIKitのクラス、外部依存のView実装は対象外とする。外部依存の直接編集やバージョン更新は行わない。

## 自動検査

- 全View / representableのマクロ欠落をLintで拒否する。
- revisionを持たないBinding・closure・参照入力、revisionの除外・可変化・共有値化、不変let以外の比較除外を拒否する。
- 値比較の境界への状態・操作の持込み、比較ゲートの直接使用、手書きの等価演算を拒否する。
- 新しいBindingの現在値が古いBindingと同じ場合も比較で更新を省略せず、新しい保存先に書き込むことを検査する。
- マウント済みフィルターのBindingを置き換え、古い保存先の変更では表示が変わらず、新しい保存先の変更・復元に表示が追従することを検査する。
- 既存の行表示テストで表示入力・配色・文字サイズの反映を検査する。

## 実行記録

2026-09-18、macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2を使用した。実行先はiPhone 17 Pro / iOS 26.5（23F77）の専用Simulator、UDIDは`D099A849-386F-4EAE-AE12-02D8DC623AF2`。依存はAppMacros 0.3.0、SwiftSyntax 603.0.2、Rive iOS 6.27.0を維持する。

| 検査 | 結果 |
| --- | --- |
| 検証ツールのPython回帰 | 106件成功 |
| 本体・共有拡張のReleaseビルドとSwift Testing | 74テスト（parameter展開80件）成功、失敗・skipなし |
| 一覧・検索・編集・設定・製品情報の実操作 | Releaseで成功。下書きの再開、同じUUIDの編集・削除取消・復元、フィルター、設定の保存、編集後のUTF-8完全一致を確認 |
| 共有元からの取込みと復帰 | Releaseで成功。今回の本体に埋め込まれた共有拡張の起動、保存後のSafari復帰、本体からのコピーのUTF-8完全一致を確認 |
| Riveの表示更新 | 異なる時点の演出、ライト／ダーク切替、バックグラウンドからの復帰を確認 |
| Nix共通検査 | aarch64-darwinの全7 check成功。Swift規約は46ファイルを検査 |

### runと実操作

各runは`artifacts/ios/`に保存する。`manifest.json`がビルドコマンド、実行中のソース、媒体のハッシュを持ち、`test-summary.json`が実行済みテスト数を持つ。対象ソースはコミット後に`check_evidence.py --integrity-only --ref HEAD`で照合する。

| run | 対象と観測 |
| --- | --- |
| `20260918T065900Z-test-43b81f` | Releaseテスト。Bindingの差し替え、マウント済みフィルター、callbackの更新を含む74テストが成功 |
| `20260918T065928Z-mvp-ui-214fa8` | 標準UI driver。作成→下書き保持→再開→保存→検索→編集→コピー→ピン留め→削除→Undo→破棄、3タブ、左右の操作位置と再起動後の保持、削除済み一覧の検索・復元 |
| `20260918T071049Z-equatable-share-about-16e999` | 補助driver。Safariから共有→タイトル入力→保存→共有元へ復帰→本体で検索・コピー、Aboutの配色変更・背景移行・復帰 |

標準UI driverの対象はダミー項目`日本語コピー 83398ca3`、UUIDは`37F93DBB-2D7D-4611-86EF-3CC36603F814`。共有の対象は`共有境界検証-9be740ec`、UUIDは`248D7A38-6164-40BB-95AB-0BB8545B89DF`。文字列の保持は空白、改行、結合文字、絵文字を含むコピー結果のUTF-8で判定した。

### 画像・録画のレビュー

原本PNGと録画から抽出したフレームを開いて確認した。録画は全編再生ではなく、以下の時刻を抽出したサンプルレビューである。ローカルの`review.json`へ観測を記録し、公開先URLと閲覧確認は未記入とする。PR添付と公開先の閲覧確認は本記録の完了項目に含めない。

| run | 確認した媒体と範囲 |
| --- | --- |
| 標準UI | `finished.png`、`resumed-draft.png`、`about.png`、`left-library.png`、`right-library.png`。一覧の選択・表示、保持された編集内容、Aboutの構成、左右の操作配置を確認。194.698秒の録画から9.207 / 97.085 / 175.220秒を確認し、背景移行、検索とキーボード、削除済み一覧の復元操作を観察 |
| 共有・About | `share-sheet-position.png`、`share-editor.png`、`about-motion-1.png`〜`about-motion-3.png`、`about-dark.png`、`about-returned.png`、`about-resumed-confirmed.png`。共有本文、保存の表示と次の演出周期、配色、背景移行後の画面を確認。388.885秒の録画から8.697 / 194.202 / 350.428秒を確認し、共有先の選択、入力中の共有エディター、Aboutの演出を観察 |

### 操作自動化の観測

- 標準UI driverではsim-use 0.14.0の日本語「すべてを選択」の照合失敗を記録した。既存の限定fallbackでネイティブメニューを操作し、編集後コピーの完全一致を確認した。
- 共有ポップオーバーの最初のラベル指定タップは、要素のローカル座標を画面座標として使用し、共有先が起動せずSafariでAbortErrorになった。画像で確認したポップオーバーの原点と要素位置からタップ位置を補正した。起動したNibbleShareのプロセスパスが、今回インストールした本体の`PlugIns/NibbleShare.appex`と一致することを確認した。製品コードの変更やエラーの無視で回避していない。

## 評価の限界

revision付きViewは、親が再構築した入力を必ず反映するための保守的な比較を行う。すべてのViewにマクロがあることは、すべてのViewで更新回数が減ることを意味しない。FPS、body回数、応答時間の改善をこの宣言数から算出しない。

表示・入力・保存・再生の整合性を受入条件とする。比較の速度、フレーム時間、電力、実機での性能改善は別の計測が必要であり、本記録から保証しない。今回追加した実操作は上記Simulatorに限り、別の画面サイズ・回転・RTL・実機での再検証は行っていない。Riveの画像差分と時刻別の観察は演出の進行を示すが、全フレームの連続性やフレームレートの測定ではない。
