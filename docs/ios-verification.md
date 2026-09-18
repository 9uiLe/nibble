# ローカル iOS 検証

[scripts/ios.py](../scripts/ios.py) は、iOS Simulatorに対するビルド・テスト・操作・画面記録の共通コマンドを提供する。Apple CLIでビルドと実行管理・撮影を行い、Nixで固定したsim-useで画面を読み取り操作する。構成と採用理由は [検証基盤の設計](decisions/0001-local-ios-verification.md) に記載する。

工程・結果・保存先は[共通表示Adapter](script-tooling.md)からstderrへ表示する。doctor/devices/uiのJSONとcreateのUDIDはstdoutへ返す。AI・CIでは`NIBBLE_UI_FORMAT=json`を指定する。コマンド引数とネイティブ出力の詳細はrunのmanifestとログを参照する。

## 検証対象と前提

共通driverは設定ファイルで検証対象を選ぶ。指定を省略すると、基盤を試験するVerificationAppを使用する。

| 項目 | Nibble / NibbleShare | VerificationApp | ResearchProbe |
| --- | --- | --- | --- |
| 目的 | 製品の保存・画面・呼び出し・共有 | 共通コマンド・文字列照合・撮影の成立 | 保存・検索・入力・コピー・復旧・OS連携の比較 |
| project | `app/Nibble.xcodeproj` | `validation/VerificationApp.xcodeproj` | `validation/ResearchProbe.xcodeproj` |
| shared scheme | `Nibble` | `VerificationApp` | `ResearchProbe` |
| bundle ID | `nibble.9uiLe.com` / `nibble.9uiLe.com.share` | `dev.nibble.VerificationApp` | `dev.nibble.ResearchProbe` |
| 設定ファイル | [app/project.json](../app/project.json) | [validation/project.json](../validation/project.json) | [validation/research-project.json](../validation/research-project.json) |
| 操作の検証 | `scripts/check-mvp-ui.py` | `scripts/ios.py smoke` | `validation/check-research-ui.py` |

各targetの最低対応OSはiOS 26.0、Swift language modeは6。確認環境はXcode 26.5、Apple Swift 6.3.2、Simulator SDK 26.5、NixのPythonとsim-use 0.14.0。実行対象はiOS 26.5のみで、確認したbuildは23F77。研究用driverはApple Silicon Macを前提とする。

製品の操作・期待結果は[MVP手順](mvp.md)、ResearchProbeの比較条件は[研究用の設計と実行手順](../validation/RESEARCH.md)を参照する。`smoke`はVerificationApp専用である。

[READMEのセットアップ](../README.md#セットアップ)を完了し、Xcodeのライセンス・追加コンポーネントと対象runtimeを用意する。NixはXcodeをインストールしない。コマンドはリポジトリルートで実行する。

製品の設定は`simulator_signing: "ad-hoc"`でXcodeのローカル署名を指定する。App GroupのentitlementをSimulatorへ渡すために必要で、Developer Teamや署名証明書は使わない。設定を省略した基盤・研究用fixtureは未署名でビルドする。

## 環境の確認

Xcodeは `xcode-select` の選択先を使用する。シェル単位で選ぶ場合は、実際のインストール先に合わせて `DEVELOPER_DIR` を設定する。

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
nix develop --command python3 scripts/ios.py doctor
nix develop --command python3 scripts/ios.py devices
```

`doctor` はツール・runtime・shared scheme、`devices` は利用可能なSimulatorを確認する。runtimeの `version` がiOS 26.5であることを確認し、`buildversion` と合わせて検証条件に記録する。

## Simulatorの作成と選択

iOS 26.5の検証専用Simulatorを用意する。`--runtime` は `devices` の出力から26.5を選び、`--device-type` は `xcrun simctl list devicetypes` で利用可能な値を選ぶ。次は26.5のruntimeが導入済みの場合の例。

```sh
nix develop --command python3 scripts/ios.py create \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  --name 'nibble Verification 26.5'
```

`create` は実行ごとに新しい端末を作る。作成・実行とも共通CLIがruntime 26.5以外を拒否する。出力されたUDIDを保存し、再利用時は同じUDIDを指定する。UDIDは端末の一意な識別子であり、同名のSimulatorも区別できる。名前や暗黙の `booted` を操作対象に使わない。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
nix develop --command python3 scripts/ios.py boot --device "$NIBBLE_SIMULATOR"
```

必要なら `open -a Simulator` でSimulatorウィンドウを表示する。CLIによる操作はsim-useが観測したaccessibility identifierを使用する。

## ビルド・テスト・動作確認

以下は標準設定のVerificationAppを検証するコマンド。製品・ResearchProbeには[対象設定](#検証対象の切り替え)を指定する。

```sh
# Simulator向けビルド。署名アカウントは不要
nix develop --command python3 scripts/ios.py build --device "$NIBBLE_SIMULATOR"

# ビルドとSwift Testing。xcresultとsummaryを保存
nix develop --command python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR"

# ビルド、インストール、起動、画面読取
nix develop --command python3 scripts/ios.py run --device "$NIBBLE_SIMULATOR"

# fixtureの操作・期待結果の照合・静止画と動画の取得
nix develop --command python3 scripts/ios.py smoke --device "$NIBBLE_SIMULATOR"

# Release構成での操作確認
nix develop --command python3 scripts/ios.py smoke \
  --device "$NIBBLE_SIMULATOR" --configuration Release
```

`test` は `xcodebuild` の終了コードと `xcresulttool` のsummaryを確認する。成功したテストが1件以上必要で、0件・全skip・失敗を成功扱いしない。fixtureのSwift Testingはホストの識別・対応OSと、ViewControllerを経由するUnicode・空白の保持を検査する。

起動後はAppleの`simctl spawn launchctl list`で対象bundle IDとPIDを確認する。プロセスが現れるまで1秒間隔・最大5回待つ。SimulatorのプロセスはホストのPIDを使うため、各sim-use操作の前後にはホストの`ps`で同じPIDの起動時刻と実行ファイルを照合する。操作ごとにSimulator内へ監視プロセスを起動する待ち時間を避ける。終了・再起動・複数候補・取得エラーはrunを失敗にする。sim-useは操作ごとに新しいAX接続を使い、driverが起動したアプリでは組み込みのプロセス監視をこの照合で置き換える。監視方式・PID・プロセス情報はmanifestに記録する。

`smoke` はビルド・起動後、画面読取 → リセット → 入力欄選択 → ダミーテキストの貼り付け → 反映 → 出力値の照合を実行する。入力は `日本語 👩🏽‍💻` と改行・`Hello, nibble!`。`--text` で変更できる。Swift Testingは別の `test` コマンドで実行する。

smokeはSimulatorのクリップボードとfixtureの入力を書き換えるため、専用端末とダミーデータを使う。iOS 26.5のみで、変更の影響範囲を確認する。SimulatorのRelease実行と実機の性能測定は、それぞれ別の検証として記録する。

## 個別の画面読取と操作

```sh
nix develop --command python3 scripts/ios.py ui --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py tap --device "$NIBBLE_SIMULATOR" fixture.input
nix develop --command python3 scripts/ios.py paste --device "$NIBBLE_SIMULATOR" \
  --target-id fixture.input --text '日本語の確認 🧪'
nix develop --command python3 scripts/ios.py tap --device "$NIBBLE_SIMULATOR" fixture.apply
```

`tap` / `paste` は操作前後の画面情報を保存する。任意のアプリの期待結果は呼出側で確認する。`smoke` の自動照合はfixture専用である。

sim-useを直接使う場合も `nix develop` 内で実行する。`sim-use ui --json --no-raw` の `uniqueId` で要素を特定し、原文の比較には `value` を使う。表示用の `label` / outlineには空白・改行の整形が入る場合がある。

`paste --via-menu` はメニュー操作を使い、Simulatorのハードウェアキーボード接続に依存しない。日本語の貼り付けはIMEの変換・未確定文字・候補選択を試験しないため、IMEは独立した操作で検証する。許可ダイアログや想定外の画面は読み取って対応する。検証スクリプトによる権限の一括許可は行わない。

## スクリーンショットと画面録画

```sh
nix develop --command python3 scripts/ios.py screenshot --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py record --device "$NIBBLE_SIMULATOR" --seconds 10
```

静止画はAppleの `simctl io screenshot`、動画は `simctl io recordVideo` で取得する。録画は開始通知を待ち、SIGINTで確定する。`--seconds` は0より大きく60以下の値を指定する。動画の長さと代表フレーム3枚をSwift / AVFoundation / AppKitで取得する。

smokeでは録画の確定後に操作後の静止画を撮影する。同時取得時に静止画のボタン文字が欠ける場合を避け、動画と静止画を独立してレビューできる順序にする。

任意の操作を記録する場合は、一つのターミナルで `record` を実行し、別のターミナルからNix内の `sim-use ui` / `tap` / `gesture` 等を使う。検証スクリプト同士は同じUDIDをロックするが、直接のsim-useやXcode操作はロックしない。同じ端末へ別の検証を同時に流さない。

## 成果物とレビュー

1回の実行をrunと呼ぶ。各runは`artifacts/ios/<UTC日時>-<コマンド>-<ID>/`へ結果を保存する。ビルドキャッシュは`artifacts/ios/DerivedData/<UDID>/`に置く。`artifacts/`全体をGit管理対象外とする。

| ファイル | 内容 |
| --- | --- |
| `manifest.json` | 実行成否、コミット、未コミット状態、開始・終了の入力SHA-256、媒体SHA-256、ツール・端末・runtime、コマンドと終了コード |
| `review.json` | 確認した媒体のhash、目視の方法・観測・限界、安定した添付URL、ブラウザーでの閲覧確認の申告 |
| `*.log` / `*.stderr.log` | stdout / stderr。失敗時の出力も保存 |
| `build.xcresult` / `test.xcresult` | Xcodeの結果bundle。Xcodeで開いて調査できる |
| `test-summary.json` / `attachments/` | テスト件数・成否とテストに含まれる添付物。Swift Testingだけの場合は画像添付がないこともある |
| `before.json` / `after.json` 等 | sim-useの画面観測。要素や文字列の照合に使用 |
| `before.png` / `after.png` / `screenshot.png` | Apple CLIで撮影した静止画 |
| `recording.mp4` / `recording.log` | H.264動画と録画ログ |
| `video-frames/` | 動画の長さと代表フレーム3枚 |
| `REVIEW.md` | driverが作成する実行情報と記入欄。証跡検査後は`review.json`から生成したレビュー記録 |

共通driverは`evidence_version: 1`のmanifestに、開始時の`files_sha256`、終了時の`files_sha256_end`、run確定時の`media_sha256`を保存する。実行中に検証入力が変わったrunは失敗にし、ログと媒体を残す。文書だけの変更を含むrunの再利用は、コミット名ではなく検証入力のファイル照合で判断する。

レビューは[証跡とPRの検査](review-evidence.md)の順序で行う。

1. `check_evidence.py --integrity-only`で対象revision、runの成否、入力と媒体を照合する。
2. `--init-review`で記入用の`review.json`を作り、画像・動画を開いて表示・操作・時間経過を確認する。確認方法・観測・未実施条件を記載する。
3. 必要な画像・動画をPRへ添付するか、レビュー担当者が閲覧できる保存先へ置く。ブラウザーで読込を確認し、安定したURLと閲覧条件を記録する。
4. `check_evidence.py`でソース・媒体・レビュー申告を検査し、`REVIEW.md`を生成する。

ソース照合には同じrun内で対象scheme・UDIDへのビルド成功が必要になる。単独の`screenshot`・`record`は補助的な撮影記録であり、install済みアプリとソースの対応を保証しない。

コマンド成功、ファイル生成、動画デコード、抽出フレーム確認、全編再生、アップロード、閲覧確認を別々に記録する。公開するログ・画像・動画に個人情報や秘密情報が含まれないことを確認し、未実施を完了として記載しない。

## 検証対象の切り替え

製品のビルド・テスト・起動には`app/project.json`を指定する。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py run \
  --project-config app/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
```

製品の操作は`nix develop --command python3 scripts/check-mvp-ui.py --device "$NIBBLE_SIMULATOR"`で検査する。共有・ペースト・IME・呼び出しの手順は[MVP手順](mvp.md)に従う。

ResearchProbeのビルド・テスト・起動には専用設定を指定する。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config validation/research-project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
nix develop --command python3 scripts/ios.py run \
  --project-config validation/research-project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
```

`smoke`はVerificationApp専用。ResearchProbeの画面操作には`nix develop --command python3 validation/check-research-ui.py --device "$NIBBLE_SIMULATOR"`を使う。APIやデータの比較条件、Safari・日本語入力・表示設定の手順は[研究用の設計と手順](../validation/RESEARCH.md)で定義する。

検証targetを定義する際は同じ形式の設定を用意する。`project` / `scheme` / `bundle_id` / `app_name` / `minimum_ios`を実際の構成に合わせ、`--project-config <設定ファイル>`で選択する。共通のビルド・テスト・実行管理・撮影を利用し、操作と期待結果は製品の仕様に対応するdriverで検査する。

## 実機と製品固有の検証

このスクリプトとMVPの実行評価はiOS 26.5 Simulatorを対象とし、実機検証はMVPの受け入れ範囲に含めない。実機条件を評価する場合もiOS 26.5を使用する。実機の検出はAppleの `xcrun devicectl list devices`、ビルド・署名・インストール・起動は対象端末と署名設定に合わせて構成する。未接続・未信頼・署名未設定の場合は、その実機条件を未実施として記録する。

実機性能、VoiceOver・Dynamic Type、IME、キーボードextension、権限、保存・同期・配布は製品ごとの検証を行う。fixtureの合格をこれらの実施結果へ置き換えず、[製品の検証計画](../research/05-decisions-and-validation.md) の条件・期待結果と対応する証跡を残す。
