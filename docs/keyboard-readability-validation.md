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

録画`recording.mp4`（14.542秒）は、0.793、7.068、13.380秒の抽出フレームを確認した。挿入行のハイライト、ピン追加結果、ピン0件への変化を観測。全編再生は未実施。媒体レビューと公開URLはrun内`review.json`へ記録した。[PR #29](https://github.com/9uiLe/nibble/pull/29)に変更前の画像、対象コードの画像5枚と録画を添付した。2026-09-19 14:34 JSTに未ログインのCodex内蔵ブラウザーで画像の実寸と動画の読込を確認した。

## 長文末尾とキーボード切り替え

run `20260919T062242Z-keyboard-ui-179829`（passed）は、`04b094cf350b60bdee3d15a8a302148674da05e5`の製品Releaseビルド・installから実施した。製品コードは本書冒頭の対象と同一。専用SE・iOS 26.5・53件のダミーデータを使用し、終了時にデータを復元した。

| 条件 | 観測と証跡 |
| --- | --- |
| 全文の末尾 | 項目52の独立した「…」から120段落の全文を開き、本文領域を57回スワイプ。先頭の段落000から最終段落119と「全文の末尾です。」の画面内表示を画像で確認。`long-detail-top.png`、`long-detail-end.png` |
| 誤挿入 | 全文を開いて末尾までスクロールした後も入力欄のAX値は空。`long-scroll-no-insertion` |
| 標準キーボードへ戻る | 一覧へ戻り、地球儀をタップして標準の日本語かなキーボードへ切り替え。画像とAXで「あ」「か」「改行」、削除・音声入力キーを確認し、nibbleの操作IDが消えたことを照合。`keyboard-switch-observed.png`、`standard-keyboard-confirmed`。切り替え後も入力欄は空 |

操作ツールの一部のAX frameは拡張内の相対座標で返される。最初のID指定による戻る・地球儀タップではキーボードが切り替わらず、ホストの自動入力メニューが現れた。その試行を成功扱いせず、撮影画像上の戻る（59, 401pt）と地球儀（32, 645pt）を指定し、切り替え後の画面・AXで確認した。`standard-keyboard-after-switch.png`という途中ファイル名は切り替え成功を意味しない。

[長文末尾の画像](https://github.com/user-attachments/assets/10758b96-7229-42d4-9810-b08334f32bc3)、[標準キーボードの画像](https://github.com/user-attachments/assets/2f606f2f-fbf4-46fd-b744-efb9e3c15309)、[画面録画](https://github.com/user-attachments/assets/e6347255-e912-49c3-890d-4a2fc305aa68)をPR #29へ添付した。録画原本は37.408秒。抽出フレーム2.287・18.030・32.682秒で末尾付近のスクロールと最終文の表示、36.152・37.150秒で標準日本語かなキーボードへの切り替え後を確認した。全編再生は未実施。2026-09-19 15:40 JSTに未ログインのCodex内蔵ブラウザーで画像2枚の750×1334px、動画の750×1334px・readyState=4・errorなし・37.408333秒を確認した。

## モデル・SQLite処理の性能

測定IDは`run-20260919T063901Z`。base `b15b98f6860b20eaa077d724f6a94e5b060a6032`とfinal `04b094cf350b60bdee3d15a8a302148674da05e5`の`Snippet`、`SnippetLocation`、`SnippetQueries`、`SQLiteDatabase`、`KeyboardReader`、`KeyboardModel`をGitから取得し、同じ補助プログラムへ組み込んだ。製品ファイルを改変せず、各ファイルと補助プログラムのSHA-256をmanifestへ保存した。

測定には上記の専用SE / iOS 26.5 / arm64 Simulatorを使用し、Apple Swift 6.3.2で`-Osize -whole-module-optimization -swift-version 6 -strict-concurrency=complete -target arm64-apple-ios26.0-simulator`を指定した。UI検証・Xcodeビルドを終了し、入力先アプリを終了してから直列に測った。画面付きアプリのReleaseビルドそのものではなく、同じ最適化方針でコンパイルした製品のモデル・SQLite処理の比較である。

同じseed DBには10,000件（ピン200件）を保存し、長文1件は日本語・結合文字・絵文字・改行を含む620,000 UTF-8 byteとした。各プロセスへDBを複製し、本体と同様にWAL/SHMを保持する初期化を計測前に行った。読み取り接続の生成、SQL、モデルへの結果反映を計測に含む。挿入先は受け取った本文のbyte数を記録する補助実装で、OSの`insertText`は呼ばない。

base → final → final → base → base → finalの順に各3プロセス。各操作はプロセスごとに5回準備実行し、続く100回、合計300回を採用した。ContinuousClockで経過時間を測り、全サンプルの中央値と小さい順の285番目（p95）を集計した。測定前の処理時間予算は、一覧・短文・ピンをp95 16.7ms、長文挿入準備・全文取得をp95 50msと定義した。これは処理区間の予算であり、描画フレームやタップから表示までの保証ではない。

| 操作 | base 中央値 / p95（ms） | final 中央値 / p95（ms） | p95予算（ms） |
| --- | --- | --- | --- |
| 10,000件から先頭50件の要約を取得・モデルへ反映 | 0.668 / 0.998 | 0.671 / 1.042 | 16.7 |
| 短文を取得し挿入先の補助実装へ渡す | 0.444 / 0.683 | 0.419 / 0.650 | 16.7 |
| 620,000 byteの本文を取得し挿入先の補助実装へ渡す | 1.342 / 1.668 | 1.324 / 1.620 | 50 |
| 620,000 byteの全文を詳細モデルへ取得・詳細を閉じる | 対象外：新規操作 | 1.275 / 1.576 | 50 |
| 詳細でピンを交互に追加・解除しページ再取得を待つ | 対象外：新規操作 | 4.130 / 5.355 | 16.7 |

全操作が処理時間の予算内だった。一覧のp95は約0.044ms増えたが、予算を超える退行は観測しなかった。この規模の差から高速化は主張しない。補助プロセスの最大RSSはbase約37.00MiB、final約37.09MiB。finalだけが詳細とピンの追加測定を含むため、RSS差は同じ操作列による比較ではなく、キーボード拡張の実メモリとも異なる。

原本は`artifacts/keyboard-performance/`の`Benchmark.swift`、`manifest.json`、コンパイルログ、各プロセスのstdout/stderr、`run-20260919T063901Z/execution.json`・`summary.json`へ保存した。`run-20260919T063707Z`と`run-20260919T063753Z`は補助DBのWAL/SHM準備不足で最初の読取に失敗した試行であり、集計から除外した。成功試行では同じ初期化を両版に適用し、開始後にソース・seed・補助プログラムを変更していない。

## 個別観測と失敗run

- `20260919T042216Z-keyboard-ui-183702`：対象コード。120段落の長文表示・スクロール、詳細の「入力する」で1回の挿入、コピーのUTF-8一致とホスト不変、ピン結果を個別に確認。`long-detail.png`、`long-detail-scrolled.png`、`insert-feedback.png`等を保存。ただし後続の空状態見出しのAX assertionでrun全体はfailed。画像には見出し・案内が表示されており、ツールのoutlineには案内だけが含まれる。run全体の判定はfailedとし、`20260919T042514Z-keyboard-ui-d79537`では空状態の画像を直接確認した。録画は0、5.887、10.560秒の抽出フレームだけ確認。
- `20260919T040935Z-keyboard-ui-22dc33`：Dynamic Typeへ追従する試験用UI。フルアクセスなしのコピー・ピン拒否、本文挿入、詳細復帰、権限ありのコピー・ピンを確認した。最大文字サイズの表示に問題があり、対象コードの固定表示仕様の合格証跡には使わない。未許可コピー時のクリップボード不変は原文比較していない。
- `20260919T040048Z-keyboard-ui-94c399`：標準SettingsのAX読取で環境エラー。Simulatorを表示して回復し、後続runで操作できた。製品の不具合とは判定していない。
- `20260919T041752Z-keyboard-ui-103236`：操作検証を伴わない試験用ビルド。UIの合格証跡には使用しない。

## 未確認事項

実機、VoiceOverの実操作、横向き・iPad・ホームインジケータ付き端末、太字・コントラスト設定変更、OS 26.0での実行、ホストアプリごとの入力制限は未確認。性能計測はモデル・SQLite処理の区間に限定し、画面描画のhitch、呼び出しから表示、タップからホストへの反映時間、キーボード拡張全体のメモリは未測定。挿入APIから入力先の保存完了を確認することはできず、通知は本文を渡した結果を示す。

変更前の比較画像は[PR #28](https://github.com/9uiLe/nibble/pull/28)のiPhone 17 Pro / iOS 26.5から取得した。記録の対象`9920fc8389573685850a37abf88cbad8af810401`とbase `b15b98f`の製品・検証入力が同一であることを照合した。変更後のSEとは端末幅とデータが異なるため、配置の比較用とし、寸法・性能比較には使用しない。公開媒体のブラウザー確認はエージェントが実施したもので、レビュー担当者本人の確認とは区別する。
