# ローカル iOS 検証

ビルド・テスト・Simulator の操作・画面記録を、[scripts/ios.py](../scripts/ios.py) から実行する。補助ツールは Nix、Apple のツールチェーンはローカル Xcode が担当する。

最初の実行対象は [VerificationApp](../validation/VerificationApp.xcodeproj/project.pbxproj)。入力したダミー文字列を画面へ反映する**基盤の検証用アプリ**であり、nibble 本体の機能・UI・保存方式を決めるものではない。

## ツールと責務

| 用途 | 使用するもの |
| --- | --- |
| ビルド・Swift Testing | Apple `xcodebuild`。共有 scheme と明示した Simulator destination を使用 |
| runtime・端末の作成／起動・アプリのインストール／起動 | Apple `xcrun simctl` |
| 画面の読取・タップ・テキストの貼り付け | Nix で固定した `sim-use` 0.14.0 |
| スクリーンショット・動画 | Apple `xcrun simctl io screenshot / recordVideo`。動画は SIGINT で確定 |
| テスト結果・添付ファイル | Apple `xcrun xcresulttool` |
| 動画のデコード確認・代表フレーム | Apple の Swift / AVFoundation / AppKit |
| 実行条件、ログ、成否の保存 | 既存の Nix Python と標準ライブラリ |
| Ubuntu CI | driver の失敗処理テスト、workflow 方針、Nix 書式。iOS は実行しない |

判断の背景・依存の固定方法は [ADR 0001](decisions/0001-local-ios-verification.md) を参照する。

## 初回セットアップ

1. [README のセットアップ](../README.md#セットアップ)を完了する。Xcode 初回起動時のライセンス・追加コンポーネントを準備し、iOS runtime を導入する。Nix は Xcode 自体をインストールしない。
2. 必要なら、このシェルだけで `DEVELOPER_DIR` を設定する。未指定なら `xcode-select` の選択先を使う。例：`export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer`。実際のインストール先に合わせる。
3. 次のコマンドで Xcode、Swift、sim-use、runtime、共有 scheme を確認する。

```sh
nix develop --command python3 scripts/ios.py doctor
nix develop --command python3 scripts/ios.py devices
```

専用 Simulator を作る。`--runtime` と `--device-type` はローカルで利用可能な識別子を使う。利用可能な device type は `xcrun simctl list devicetypes` で確認できる。次の例は該当 runtime が導入済みの場合に実行する。

```sh
nix develop --command python3 scripts/ios.py create \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  --name 'nibble Verification 26.5'
```

出力された UDID を設定する。同じ名前でも端末は区別されるため、名前や暗黙の `booted` は操作対象に使わない。`create` は実行ごとに新しい端末を作るので、2回目からは既存の UDID を使う。

```sh
export NIBBLE_SIMULATOR='作成時に出力されたUDID'
nix develop --command python3 scripts/ios.py boot --device "$NIBBLE_SIMULATOR"
```

必要なら `open -a Simulator` で Apple の Simulator ウィンドウを表示する。CLI は Simulator 内のタップに座標の推測を使わず、`sim-use` で観測した accessibility identifier を使用する。

## ビルド・テスト・動作確認

```sh
# Simulator 向けにビルド。署名アカウントは不要
nix develop --command python3 scripts/ios.py build --device "$NIBBLE_SIMULATOR"

# ビルドして Swift Testing を実行。xcresult と summary を保存
nix develop --command python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR"

# ビルド → インストール → 起動 → 画面を読み出す
nix develop --command python3 scripts/ios.py run --device "$NIBBLE_SIMULATOR"

# 検証用アプリを操作し、日本語・絵文字・改行の反映、画像・動画を確認
nix develop --command python3 scripts/ios.py smoke --device "$NIBBLE_SIMULATOR"

# 最適化した構成で同じ基盤を実行
nix develop --command python3 scripts/ios.py smoke \
  --device "$NIBBLE_SIMULATOR" --configuration Release
```

`smoke` は本体ビルドと、画面の読取 → リセット → 入力欄選択 → ダミーテキスト貼り付け → 反映 → 出力値の照合を実行する。Swift Testing は別の `test` コマンドで実行する。クリップボードの書き換えと fixture の入力リセットを伴うため、専用 Simulator とダミーデータを使う。

操作後の静止画は録画を終了・確定してから撮影する。検証時に、録画中の静止画でボタン文字が欠け、動画フレームには正常に写るケースを観測したため、同時取得を避けている。画面の正しさは保存した画像も開いて確認する。

テストは `xcodebuild` の終了コードに加え、`xcresulttool` の summary が成功か、実際に1件以上のテストが通ったかを確認する。0件・全 skip・失敗を成功と報告しない。失敗時にも取得できたログ・結果は保存する。

## 個別の操作と記録

```sh
nix develop --command python3 scripts/ios.py ui --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py tap --device "$NIBBLE_SIMULATOR" fixture.input
nix develop --command python3 scripts/ios.py paste --device "$NIBBLE_SIMULATOR" \
  --target-id fixture.input --text '日本語の確認 🧪'
nix develop --command python3 scripts/ios.py tap --device "$NIBBLE_SIMULATOR" fixture.apply
nix develop --command python3 scripts/ios.py screenshot --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py record --device "$NIBBLE_SIMULATOR" --seconds 10
```

`tap` / `paste` は操作前後の画面を保存する。任意のアプリの期待結果までは推測しないので、出力された画面を確認する。`smoke` の期待結果照合は fixture 固有である。

独自の操作を録画する場合は `record` を一つのターミナルで実行し、もう一つで Nix 内の `sim-use ui` / `tap` / `gesture` 等を使う。driver 同士は同じ UDID の競合をロックするが、直接の `sim-use` や Xcode の操作まではロックしない。別の検証を同時に同じ端末へ流さない。

`sim-use paste --via-menu` はハードウェアキーボード接続に依存しないメニュー操作を使う。日本語の**貼り付け**が成功しても、日本語 IME の未確定文字・変換候補の動作を検証したことにはならない。許可ダイアログや想定外の画面が出た場合は、その画面を確認して対応する。driver は権限を一括で許可したり端末設定を変更したりしない。

直接 `sim-use` を使う場合も、`nix develop` 内で実行する。`sim-use ui --json --no-raw` の出力では `uniqueId` で要素を特定し、値が必要な場合は `value` を読む。表示用の `label` / outline は空白や改行が整形される場合がある。

## 成果物とレビュー

毎回 `artifacts/ios/<UTC日時>-<コマンド>-<ID>/` を作り、既存の結果を上書きしない。ビルドキャッシュは `artifacts/ios/DerivedData/<UDID>/`。このディレクトリ全体は Git 管理対象外である。

| ファイル | 内容 |
| --- | --- |
| `manifest.json` | 実行成否、コミット、未コミット状態、対象ファイルの SHA-256、Xcode / Swift / sim-use、端末・runtime、実行したコマンド・終了コード |
| `*.log` / `*.stderr.log` | stdout / stderr。ビルド・テスト失敗の原文も保持 |
| `build.xcresult` / `test.xcresult` | Xcode が生成する結果 bundle。Xcode で開いて調べられる |
| `test-summary.json` / `attachments/` | テスト件数・成否と、存在するテスト添付物。Swift Testing だけなら画像添付がない場合もある |
| `before.json` / `after.json` 等 | sim-use の画面観測。文字列の照合に利用 |
| `before.png` / `after.png` / `screenshot.png` | Apple CLI で撮影した画像 |
| `recording.mp4` / `recording.log` | H.264 動画と録画ログ。開始を確認してから操作し、SIGINT で保存を確定 |
| `video-frames/` | 動画の長さ、代表フレーム3枚。デコード成功は人による動画レビューの代替ではない |
| `REVIEW.md` | 実行情報と、画像・動画の確認／PR 添付先の記入欄 |

画像と動画を開いて、表示・操作・時間経過を確認する。`REVIEW.md` に確認した内容・残る問題を追記し、PR に閲覧できる形で添付する。**コマンド成功・ファイル生成・ローカルパスの記載だけでは、UI レビューや PR 添付の完了にならない。** ログや画像にはダミーテキストを使い、公開するファイルを確認する。

## 本体への接続と対応範囲

将来、本体の Xcode project と shared scheme を作成したら、`validation/project.json` と同じ形式の設定を追加し、`--project-config <設定のパス>` で選択する。project / scheme / bundle ID / app 名を実際のターゲットに合わせる。`build` / `test` / `run` / `ui` / 記録を共通利用できる。`smoke` は本体の公開された操作と期待結果に合わせて別途実装する。

今回の driver は **iOS Simulator 用**。実機の検出は Apple `xcrun devicectl list devices`、署名・インストール・起動は選んだ実機と署名設定で別途構成する。実機が未接続・未信頼の場合や、署名 Team が未指定の場合に代替のSimulator結果で実機確認済みとしない。

iOS 26.0 と最新の正式版で影響範囲を確認する。runtime の表示名だけで版を判断せず、manifest の実際の `version` / build を使う。例えば `iOS-26-0` という識別子でも導入済みの実体が 26.0.1 の場合があり、厳密な 26.0.0 の結果とは区別する。

実機性能、VoiceOver・Dynamic Type 等の網羅的な使いやすさ、キーボード extension、権限、保存・同期・配布の成立は、この fixture の成功では保証しない。[研究の検証計画](../research/05-decisions-and-validation.md)の各試作で、この基盤を使って個別に確認する。
