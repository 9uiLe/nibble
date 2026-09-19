# キーボードの行タップ・全文・ピン操作の検証

2026-09-19の検証対象はコミット`3c91f027a2c4ef6f0ec219473177e0030c59f255`の製品コード。[キーボード設計](decisions/0005-snippet-keyboard.md)、[画面構成のS09](design/screens.md#s09-スニペットキーボード)、[部品台帳のC45〜C48](design/components.md#スニペットキーボード)に対して結果を記録する。検証実行をrunと呼び、各runのmanifestに対象ソースのSHA-256、実行コマンド、端末、成否を保持する。対象コードと異なる試験用ビルドは個別に明記する。

## 環境と確認範囲

Xcode 26.5（17F42）、iOS 26.5（23F77）、専用iPhone SE（第3世代）Simulator `A566331E-BF10-48B5-9A79-74D7177430EF`、375×667pt。ユーザーの既存Simulatorやデータは使用しない。試験用の本文と53件のダミースニペットを使用する。

入力先は製品と別プロセスのVerificationAppのUITextView。この入力欄を使って製品のNibbleKeyboardを操作する。補助driverは`artifacts/keyboard-session.py`、各runにも実行時のコピーとhashを保存した。試験データはrun終了時に復元する。記録は`artifacts/ios/`配下に保持する。

対象仕様は、本体・共有拡張・キーボードの文字サイズをlarge、太字・コントラスト設定を標準値に固定する。ライト／ダーク外観、VoiceOverの意味情報、44pt以上の操作領域を提供する。Dynamic Typeへ追従する試験用ビルドの表示結果は、この固定表示仕様の合格証跡に含めない。

## 自動検証

- `20260919T035326Z-test-b3e8c1`：試験用ビルドのRelease構成でSwift Testingの96テスト成功。詳細の古い取得結果、詳細を開いたときの0挿入、1回の挿入、長文保持、ピン権限不足・書込失敗・更新番号競合、本文の原文保持を含む。
- `20260919T042748Z-test-352c41`：対象コードのReleaseビルドと96テストが成功。Xcodeのtest summaryで失敗0件を照合。
- `nix flake check --no-update-lock-file --print-build-logs`：aarch64-darwinの7検査成功。ログは`/tmp/nibble-keyboard-flake-final.log`。Swift構文・設計照合の成功を実際のタップ・読み上げの確認とは扱わない。

## 実画面と操作

対象コードの主要runは`20260919T042514Z-keyboard-ui-d79537`（passed）。同じrunで製品Releaseビルド・installを行い、次の操作と画像を確認した。

| 条件 | 観測と証跡 |
| --- | --- |
| 行タップ | 1回のタップ後、入力先のアクセシビリティ情報（AX）の値に本文が1回だけ現れる。`row-one-tap-one-insertion`、`row-insertion.png` |
| 独立した「…」 | 本文を追加せず詳細へ移る。`more-keeps-single-insertion` |
| コピー | 空白・改行・結合文字・絵文字を含む41 byteの原文とクリップボードのUTF-8が完全一致。`copy-exact` |
| ピンと0件 | 追加後はピン印・解除操作・ピン集合の1件を表示。解除して戻ると追加方法を説明する空状態。`detail-pinned.png`、`pinned-list.png`、`empty-pinned.png` |
| 一覧へ戻る | 「すべて」のスクロール途中で詳細を開いて戻る。`scroll-settled-before.json`と`scroll-after.json`の行ID・frameが一致。例：項目48はy=76、項目46はy=185（ツールの拡張相対座標） |
| 狭幅・外観 | 375ptの一覧と詳細で主要操作を表示。`list-initial.png`、`detail-from-scroll.png`、`list-dark.png` |
| 最大文字設定 | OSを最大アクセシビリティ文字サイズへ変えても、キーボードの文字と操作の配置は固定。`fixed-largest-type.png`。ホストの文字は拡大する |
| ページ・更新 | 2ページ目は残り3件、更新すると同じフィルターの先頭へ戻る。`second-page.png`、`refreshed-first-page.png` |
| 閉じる・切替 | 閉じる後のAXにキーボードがない。地球儀はOSの「Quickly Change Keyboards」案内へ到達。`keyboard-dismissed.json`、`system-keyboard.png`。その案内を閉じた後の標準キーボードまでは未確認 |

入力先AXは前後空白を省略するため、挿入についてUTF-8全byte一致を確認したとは扱わない。原文の完全一致はコピーと保存層テストの結果である。driverのAX照合記録にあるscope欄は検査の一般的な説明であり、入力先から本文をコピーして照合した記録ではない。

録画`recording.mp4`（14.542秒）は、0.793、7.068、13.380秒の抽出フレームを確認した。挿入行のハイライト、ピン追加結果、ピン0件への変化を観測。全編再生は未実施。媒体レビューはrun内`review.json`へ記録し、公開URL欄は未添付のままとする。

## 個別観測と失敗run

- `20260919T042216Z-keyboard-ui-183702`：対象コード。120段落の長文表示・スクロール、詳細の「入力する」で1回の挿入、コピーのUTF-8一致とホスト不変、ピン結果を個別に確認。`long-detail.png`、`long-detail-scrolled.png`、`insert-feedback.png`等を保存。ただし後続の空状態見出しのAX assertionでrun全体はfailed。画像には見出し・案内が表示されており、ツールのoutlineには案内だけが含まれる。run全体の判定はfailedとし、`20260919T042514Z-keyboard-ui-d79537`では空状態の画像を直接確認した。録画は0、5.887、10.560秒の抽出フレームだけ確認。
- `20260919T040935Z-keyboard-ui-22dc33`：Dynamic Typeへ追従する試験用UI。フルアクセスなしのコピー・ピン拒否、本文挿入、詳細復帰、権限ありのコピー・ピンを確認した。最大文字サイズの表示に問題があり、対象コードの固定表示仕様の合格証跡には使わない。未許可コピー時のクリップボード不変は原文比較していない。
- `20260919T040048Z-keyboard-ui-94c399`：標準SettingsのAX読取で環境エラー。Simulatorを表示して回復し、後続runで操作できた。製品の不具合とは判定していない。
- `20260919T041752Z-keyboard-ui-103236`：操作検証を伴わない試験用ビルド。UIの合格証跡には使用しない。

## 未確認事項

実機、VoiceOverの実操作、横向き・iPad・ホームインジケータ付き端末、長文末尾までのスクロール、太字・コントラスト設定変更、OS 26.0での実行、ホストアプリごとの入力制限、メモリ・応答性能の計測は未確認。挿入APIから入力先の保存完了を確認することはできず、通知は本文を渡した結果を示す。

比較用の基準ソース`b15b98f`のスクリーンショットと録画は未取得。対象コードの画像と録画はローカルに保存している。PRは未作成で、媒体の添付とレビュー担当者によるブラウザー閲覧は未実施。
