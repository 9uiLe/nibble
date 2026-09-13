# 研究用の実行検証

`ResearchProbe` は保存・検索・移行・コピー・画面操作を比較する使い捨てデータ用のアプリ。製品のUIや保存方式の採用を表すものではない。基盤を試験する `VerificationApp` とはproject・bundle ID・保存領域を分ける。

## セットアップと実行

[READMEのセットアップ](../README.md#セットアップ)でNix、Xcode 26.5、iOS 26.5 Simulatorを用意する。`scripts/ios.py devices`で選んだ専用SimulatorのUDIDを `NIBBLE_SIMULATOR` に設定する。

```sh
# Swift Testing。ResearchProbeだけはReleaseにもENABLE_TESTABILITYを設定している
nix develop --command python3 scripts/ios.py test \
  --project-config validation/research-project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"

# 個別APIの26.0 availabilityとextension-safeな利用を両SDKで確認
nix develop --command python3 validation/check-research-sdk.py

# Apple Silicon Macでの別プロセスSQLite・強制終了・読取専用ディレクトリ
nix develop --command python3 validation/check-research-processes.py --device "$NIBBLE_SIMULATOR"

# 作成→検索→再読込→コピー→削除→復元をsim-useで操作し、Apple CLIで録画
nix develop --command python3 validation/check-research-ui.py --device "$NIBBLE_SIMULATOR"
```

UI手順は研究用アプリの新規項目用下書き `Documents/draft-new.json` だけを準備時に削除する。保存済み項目は残し、各実行でダミーの項目を1件追加する。実データをこのアプリに入れない。`sim-use paste`はIMEを経由しないため、UI手順の成功を日本語変換の確認とはしない。

実行ログ・xcresult・録画・画像は `artifacts/ios/`、SDK検査・別プロセスの結果は `artifacts/research/` に保存する。Swift Testingの詳細JSONはテストアプリの `Documents/results/` にある。

```sh
# このコマンドが返すcontainerのDocuments/resultsを証跡ディレクトリへコピーする
xcrun simctl get_app_container "$NIBBLE_SIMULATOR" dev.nibble.ResearchProbe data
```

画像と動画を実際に開いて `REVIEW.md` へ確認結果を記録する。PRには画像・動画を閲覧可能な形で添付する。`artifacts/`はGitへ追加しない。

## 試作の意味と限界

| 対象 | 実装・比較条件 | 保証しないこと |
| --- | --- | --- |
| 3保存方式 | 同じ値の作成・全件取得・更新・削除・再open、読取専用接続。SwiftData/Core Dataは明示save | 製品の最適方式、App Groupの実権限、あらゆる移行・障害の安全性 |
| 移行 | SwiftDataのVersionedSchema/軽量移行、Core Dataの属性追加 | 未定義の製品スキーマの版飛ばしや破壊的変更 |
| SQLite worker | Simulatorの別プロセス、共有ファイル、コミット前SIGKILL、writer競合、readerのsnapshot | extension sandboxやApple派生SQLiteの全不具合修正。作業用プロセス自身が返したPIDだけを停止する |
| 検索 | NFC・case/width folding。かな/カナ、濁音/清音は区別。本文を正規化しない | 製品の最終検索仕様、IME・描画速度 |
| UI | UIKitでローカルの往復と保存失敗時の下書きを試す | 完成UI、全アクセシビリティ要件、復元情報の永続保存。削除復元は起動中の直前1件のみ |
| SDKCompileProbe | AppIntent/Shortcutsをアプリへ含める。Control/Widget等の型・memberをコンパイル | Control/Widget/Keyboard/Shareのextension登録・実行。別extension targetは含まない |
| Privacy Manifest | この研究アプリは収集・tracking・第三者SDKなし。テストbundleを配布しない | 製品のApp Privacy回答や必要理由コードの確定 |

保存は比較用にMainActorへ隔離している。10,000件を毎回全件読み込み・検索する構成を製品へ採用する根拠にはしない。保存方式の測定は単発、検索は30反復で、端末性能の保証値ではない。

結果と未実施条件は [検証結果](../research/experiments/ios-26-5-validation.md)、公開資料の照合は [一次資料検証](../research/experiments/primary-source-validation.md) を参照する。

## Safari・日本語入力・表示設定の手動比較

`HostForm.html`はダミー本文のペースト先。localhostでのみ配信する。

```sh
nix develop --command python3 -m http.server 8765 --bind 127.0.0.1 --directory validation
# 別のターミナル
xcrun simctl openurl "$NIBBLE_SIMULATOR" http://127.0.0.1:8765/HostForm.html
```

本体でコピーしてからSafariの「ペースト先」をタップ・長押しし、OSの「ペースト」を選ぶ。「本文のUTF-8を表示」の配列を原文のbytesと照合する。Safari側で`sim-use paste`を使うとpasteboardを上書きするため、この比較には使わない。リンクから本体へ戻る際にはOSの確認ダイアログも記録する。サーバーは確認後にCtrl+Cで終了する。

日本語入力は`sim-use`でシステムのかなキー「か」「な」を押し、候補「カナ」を選ぶ。元の本文と確定文字列をコピーして照合する。`setMarkedText`による単体テストと区別する。

```sh
xcrun simctl ui "$NIBBLE_SIMULATOR" appearance dark
xcrun simctl ui "$NIBBLE_SIMULATOR" content_size accessibility-extra-extra-extra-large
# sim-useで本文・ボタン・キーボードを操作し、simctl ioで撮影する
# 検証前の設定へ戻す（今回の初期値はlight/large）
xcrun simctl ui "$NIBBLE_SIMULATOR" appearance light
xcrun simctl ui "$NIBBLE_SIMULATOR" content_size large
```

小画面はSE第3世代の同じ26.5 runtimeを用いる。本文viewportの高さ・文字の切れ・キーや保存ボタンへの到達を確認する。Shortcutsの「nibble Research」欄から「研究用一覧」を実行し、登録と実行を別に判定する。Control/Widgetの型がアプリにあるだけでは、それらのextensionはインストールされない。
