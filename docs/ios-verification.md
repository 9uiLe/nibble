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

## 変更から検証を実行する

通常は[verify.py](../scripts/verify.py)で変更と検証計画を確認し、同じ入口で実行する。比較元からのコミット済み差分、未コミット変更、未追跡ファイル、削除を含む。

```sh
nix develop
export NIBBLE_UI_FORMAT=json
python3 scripts/verify.py plan --base origin/main
python3 scripts/verify.py run --base origin/main --device "$NIBBLE_SIMULATOR"
```

計画には選択した検査・対象外とした検査の理由、手動の確認事項、事前条件を記録する。文書だけなら共通検査、テストだけなら対象targetの全テスト、製品コードなら製品のテストとUI導線を選ぶ。共通基盤・設定・未知の変更はfixture・製品・研究targetへ広げる。個別テスト名をファイル名から推測せず、テストの選択漏れを避ける。

共通検査を先に実行し、失敗時は後続を開始しない。iOSの検査はRelease、同じ専用UDIDへの操作は直列で行う。`about`にはSettingsのAccessibility > Motionを開いておく事前条件がある。共有拡張・キーボードのOS導線、ResearchProbeの比較条件、媒体の目視は計画に従って別途確認する。自動工程の`passed`はこれらの手動確認を含まない。

結果は`artifacts/verify/<ID>/result.json`に計画・実行コマンド・工程時間・失敗・未開始工程・対応するrun・ソース照合をまとめる。stdoutは結果JSON、詳細と進捗はログとstderrに分ける。成功したiOS runは同じソース・端末・媒体のintegrityを自動照合する。失敗・中断・ソース変更は成功へ書き換えず、新しい結果ディレクトリへ再実行する。

合格後に追加変更をした場合は、その結果からの差分を再計画できる。

```sh
python3 scripts/verify.py run --since artifacts/verify/対象ID/result.json \
  --device "$NIBBLE_SIMULATOR"
```

`--since`はソースが安定した成功結果だけを受理する。再計画でも共通検査は実行し、過去のUI媒体を現在のソースへ自動で認定しない。未解決の懸念がある導線は個別コマンドで追加する。`--scope fixture|product|all`は明示した範囲を選ぶための指定で、除外理由も残す。一部のscope成功を全targetの成功と扱わない。

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

`test` は `xcodebuild` の終了コードと `xcresulttool` のsummaryを確認する。成功したテストが1件以上必要で、0件・全skip・失敗を成功扱いしない。fixtureのSwift Testingはホストの識別と、ViewControllerを経由するUnicode・空白の保持を検査する。

`smoke` はビルド・起動後、画面読取 → リセット → 入力欄選択 → ダミーテキストの貼り付け → 反映 → 出力値の照合を実行する。入力は `日本語 👩🏽‍💻` と改行・`Hello, nibble!`。`--text` で変更できる。個別に呼ぶ場合はSwift Testingを `test` コマンドで実行する。`verify.py`のfixture計画はテストとsmokeを順に実行する。

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

状態遷移を待つdriverは、`Run.ui(allow_empty=True)`で成功・要素0件の取得を中間状態として扱える。有限回のpollと最終状態の条件は呼出側が所有し、空の取得で条件成立とはしない。通常の単発読取では空を失敗とし、ツールの失敗と対象processの終了は待機中でも失敗させる。

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

各runの結果は`artifacts/ios/<UTC日時>-<コマンド>-<ID>/`、ビルドキャッシュは`artifacts/ios/DerivedData/<UDID>/<ビルド条件のhash>/`へ保存する。Git管理対象外であり、新しいcheckoutには含まれない。失敗runも残す。

[証跡とPRの検査](review-evidence.md)に従い、manifestの対象ソース・実行結果・媒体を照合し、観測と閲覧条件をreview.jsonへ記録する。単独の撮影は、インストール済みアプリとソースの対応を保証しない。

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

## 検証時間を比較する

[benchmark-verification.py](../scripts/benchmark-verification.py)は、JSONで指定したコマンド列を連続実行し、各工程と1サイクルの所要時間、中央値・最小/最大・ばらつき、実測した時間窓内の完了数を保存する。コマンドはNixシェル内で実行し、`--commands`にはargv配列の配列を渡す。失敗は記録して停止し、自動再試行しない。

```sh
python3 scripts/benchmark-verification.py \
  --commands artifacts/verification-commands.json \
  --output artifacts/verification-benchmark --samples 3 \
  --condition 'Release、起動済み専用Simulator、依存取得済み、増分cache、ソース変更なし'
```

コマンド列の例は`[["python3", "scripts/ios.py", "test", "--device", "専用UDID", "--configuration", "Release"], ["python3", "scripts/ios.py", "smoke", "--device", "専用UDID", "--configuration", "Release"]]`。出力先は新しいディレクトリとする。初回、ソース変更なし、代表変更、失敗と修正後を別の条件で記録し、対象ソース・依存lock・端末・キャッシュ状態・負荷をそろえる。初回の依存取得とSimulator準備、人の媒体レビューは通常の反復時間と分ける。

runの`timing`は開始から結果と媒体確定までの経過、外部コマンドの合計、manifest書込と終了処理の内訳を持つ。内訳には重複する工程があるので単純に合算しない。`xcodebuild`ログには`-showBuildTimingSummary`の内訳も残る。

## 検証範囲

共通fixtureの合格は製品の操作・権限・表示の合格を意味しない。製品の受け入れ条件は[MVP手順](mvp.md)、未確認条件は[検証範囲](mvp-validation.md)に従う。実機検証はMVPの受け入れ範囲外で、配布後の確認は[TestFlight手順](testflight.md)の担当者が行う。
