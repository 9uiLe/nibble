# View比較と入力反映の検証

対象ソースは`f1ef9eb6d69c7d550e202983df231da25b04d127`。全15型の自作Viewについて、比較宣言、親入力の差し替え、所有する状態の更新を評価した記録である。方式の選択と状態寿命の契約は[実装規約](library-policy.md#viewの比較境界)、各Viewの役割は[製品設計](decisions/0002-mvp-app.md#viewの比較と表示更新)を参照する。

## 対象と実行条件

対象は本体`Nibble`、共有拡張`NibbleShare`が使う共通エディター、ローカルPackage `RivePresentation`。値表示の2型、親入力を持つ9型、親入力を格納しない4型を含む。`App`、`ViewModifier`、UIKitのクラス、外部パッケージのView実装は比較宣言の検査対象外である。

| 項目 | 条件 |
| --- | --- |
| 実施日 | 2026-09-18 |
| ツールチェーン | macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2 |
| 実行端末 | iPhone 17 Pro Simulator、iOS 26.5（23F77） |
| UDID | `D099A849-386F-4EAE-AE12-02D8DC623AF2` |
| 製品ビルド | Release。本体・共有拡張を同じrunでビルド |
| 依存 | AppMacros 0.3.0、SwiftSyntax 603.0.2、Rive iOS 6.27.0 |
| 操作と撮影 | Nixのsim-use 0.14.0、Appleのsimctl |

1回の検証実行をrunと呼ぶ。`artifacts/ios/<run>/manifest.json`はソース・媒体のハッシュ、端末、コマンドと終了コードを記録する。以下の3 runは開始・終了時の入力が変化しておらず、対象コミットの検証入力とも一致した。媒体のハッシュ照合も成功した。照合結果はローカルの`artifacts/evidence-integrity-final.json`にある。

## 自動検査の結果

| 検査 | 結果と保証範囲 |
| --- | --- |
| Nix共通検査 | aarch64-darwinの全7 check成功。Ubuntu上の実行結果は含めない |
| Python回帰テスト | 106件成功。View・representableのマクロ欠落、不正な比較除外、比較用UUIDの再利用・可変化・除外を検出 |
| Swift規約 | 所有する46ファイルを検査し違反なし。型解決とマクロ展開は含めない |
| Releaseビルド・Swift Testing | 74テスト、パラメーター展開後80件が成功。失敗・skipなし。run `20260918T065900Z-test-43b81f` |

`RowComparisonTests`は次の契約を検査した。

- 行の表示入力を変えると比較結果と描画が変わり、値を戻すと表示も復元する。
- 表示入力が同じでも、新しく構築された行のcallbackは比較で同一視されない。呼出先が新しいclosureであることを確認する。
- 現在値が等しい別のBindingを渡すと、書込先は新しいBindingの保存先になる。
- マウント済みフィルターのBindingを差し替えた後、古い保存先の変更では画像が変わらず、新しい保存先の変更・復元には追従する。
- 値表示の入力を固定した状態で、外観・文字サイズのtrait変更が描画へ反映される。これは部品単体の環境更新の検査であり、製品の固定表示方針を変更するものではない。

## 本体・共有拡張の操作結果

| run | 操作と結果 |
| --- | --- |
| `20260918T065928Z-mvp-ui-214fa8` | 標準UI driverで作成、下書き保持・再開、保存、日本語検索、同じUUIDの編集、原文コピー、ピン留め・解除、削除・Undo、破棄、削除済み一覧の検索・復元が成功。3タブ、左右の操作位置と再起動後の保持、一覧・検索から開いた編集画面の背景復帰も確認 |
| `20260918T071049Z-equatable-share-about-16e999` | Safariから共有拡張を開き、タイトル入力、保存、Safariへの復帰、本体での検索・コピーが成功。Aboutの演出進行、ライト／ダーク切替、SpringBoardへの移行と復帰を確認 |

標準UI driverの対象はダミー項目`日本語コピー 83398ca3`、UUIDは`37F93DBB-2D7D-4611-86EF-3CC36603F814`。共有の対象は`共有境界検証-9be740ec`、UUIDは`248D7A38-6164-40BB-95AB-0BB8545B89DF`。編集後と共有後の本文は、空白、改行、結合文字、絵文字を含むコピー結果のUTF-8完全一致で判定した。

標準操作は[製品検証手順](mvp.md#基本操作の自動検証)で再現する。共有・Aboutの補助driverは対応runの`driver.py`に保存し、manifestにSHA-256を記録している。runの成功は操作結果を示し、すべての録画フレームを目視したことは意味しない。

## 媒体の観察と公開状況

原本PNGと録画の抽出フレームを開いて観察した。画像の大きさは1206×2622。録画は下表の時刻を対象としたサンプルレビューであり、全編再生は実施していない。観測は各runの`review.json`に保存している。

| run | 画像と録画の観察範囲 |
| --- | --- |
| 本体UI | `finished.png`、`resumed-draft.png`、`about.png`、`left-library.png`、`right-library.png`。一覧の選択・表示、保持された編集内容、Aboutの構成、左右の操作配置を確認。194.698秒の録画から9.207 / 97.085 / 175.220秒を確認し、背景移行、検索とキーボード、削除済み一覧の復元操作を観察 |
| 共有・About | `share-sheet-position.png`、`share-editor.png`、`about-motion-1.png`〜`about-motion-3.png`、`about-dark.png`、`about-returned.png`、`about-resumed-confirmed.png`。共有本文、保存の表示と次の演出周期、配色、背景移行後の画面を確認。388.885秒の録画から8.697 / 194.202 / 350.428秒を確認し、共有先選択、入力中の共有エディター、Aboutの演出を観察 |

原本画像9枚と録画2本を[PR #23](https://github.com/9uiLe/nibble/pull/23)へ添付した。本体録画は添付上限に収めるため、Apple `avconvert`の`Preset1280x720`で全区間を再圧縮した公開用動画を使用する。共有録画とPNGは原本である。生ログ・原本媒体はGit管理対象外のため、新しいcheckoutには含まれない。

| 媒体 | 公開先 |
| --- | --- |
| 本体の一覧・下書き | [一覧](https://github.com/user-attachments/assets/33efcb84-2818-456e-9fc8-f2d986072662)、[再開した下書き](https://github.com/user-attachments/assets/9e974775-1b45-4a5e-81d8-bd08596a58c5) |
| 左右の操作位置 | [左側](https://github.com/user-attachments/assets/d2c26eba-91d9-4f01-9d81-cfd005503c46)、[右側](https://github.com/user-attachments/assets/d4213431-ea35-48d3-8080-56d5b301495a) |
| About | [説明画面](https://github.com/user-attachments/assets/e82d7da0-dedd-4c98-9518-4fe58ca58b3e)、[ダーク配色](https://github.com/user-attachments/assets/aa46404d-93b3-4eba-97c5-14b598528215)、[演出周期](https://github.com/user-attachments/assets/ee35aacc-bd67-4777-85c5-40dfd8a55311)、[背景復帰](https://github.com/user-attachments/assets/a67f0e0b-904b-41eb-bb3b-7b674dbb67c5) |
| 共有取込 | [共有エディター](https://github.com/user-attachments/assets/81b4c6c2-758b-4519-8472-e2ce7c2fe26c) |
| 画面録画 | [本体の基本操作](https://github.com/user-attachments/assets/3ce09d24-5a6f-48b6-9ffe-c1af955e7bb6)、[共有保存とAbout](https://github.com/user-attachments/assets/d485d441-c67b-4501-90b0-7d48f85c05e7) |

2026-09-18、ログイン済みリポジトリ所有者のChromeで、上記9画像が1206×2622で読み込まれたことを確認した。本体動画は588×1280・194.698333秒、共有動画は1206×2622・388.885秒で、両方とも`readyState=4`、`error=null`だった。未認証ユーザーのアクセスと全編再生は未確認である。

本体の公開用動画は55,713,409 bytesで、原本と同じ194.698333秒の全区間を保持する。公開版の9.187 / 96.935 / 175.345秒も抽出して開き、SpringBoard、検索とキーボード、削除一覧の復元行を確認した。原本・公開版のSHA-256、変換条件、抽出時刻は`artifacts/pr-media/publication.json`とrunのレビュー記録に保存する。公開URLは再圧縮版を指すため、原本とのバイト一致は意味しない。

公開した媒体は各runの`review.json`にURL・観測・閲覧条件を記入し、`check_evidence.py`のソース照合とレビュー申告検査に合格した。公開対象に選ばなかった画像も含むローカル観察は`review-local.json`に保持する。自動検査の合格は、目視や全編再生の実施を証明するものではない。

## 操作自動化の制約

| 条件 | 観測と処理 |
| --- | --- |
| 日本語の編集メニュー | sim-use 0.14.0が「すべてを選択」を照合できず、標準UI driverに終了コード1を記録した。対象エラーに限定したネイティブメニュー操作を行い、編集後コピーの完全一致で回復を確認 |
| 共有ポップオーバー | 最初のラベル指定タップは要素のローカル座標を画面座標として使い、共有先が起動せずSafariにAbortErrorが表示された。画像で確認したポップオーバーの原点と要素位置から座標を補正して起動。実行中のNibbleShareのパスが、検証でインストールした本体の`PlugIns/NibbleShare.appex`と一致することを確認 |

これらは操作自動化で観測した制約である。失敗した操作と回復後の結果をrunに保持し、製品コードを変更して回避した結果として扱わない。

## 評価の限界

本記録の受入条件は表示・入力・保存・再生の整合性である。`inputRevision`を持つ9型は親入力の反映を優先し、新しく構築されたViewの更新を比較で省略しない。マクロの宣言数からbody評価回数、FPS、応答時間の改善率を算出できない。

比較処理の時間、フレーム時間、メモリ、電力、実機性能の比較測定は未実施。実操作は上記Simulatorに限り、別の画面サイズ・回転・RTLは評価に含まれない。Riveの時刻別画像は演出の進行を示すが、全フレームの連続性やフレームレートを保証しない。
