# ローカルiOS検証の手順

変更に必要な検査は`verify.py`で計画・実行する。個別のビルド、調査、画面操作には`ios.py`と対象別UI driverを使う。Apple CLIがビルド・実行管理・撮影、Nixのsim-useが画面読取・入力を担う。責務と採用理由は[検証基盤の設計](decisions/0001-local-ios-verification.md)に定義する。

一連の検証実行の結果は`result.json`、個別のiOSコマンドの記録であるrunは`manifest.json`へ保存する。自動工程の成功を確認した後、画像・録画を開いて観測を記録する。

## 検証対象と前提

[READMEのセットアップ](../README.md#セットアップ)を完了し、Xcodeのライセンス・追加コンポーネント・iOS 26.5 Simulator runtimeを用意する。補助ツールはNixで管理するが、XcodeはローカルMacへ別途導入する。

| 対象 | 目的 | project / shared scheme | 設定ファイル |
| --- | --- | --- | --- |
| Nibble・NibbleShare・NibbleKeyboard | 製品の保存・画面・共有・キーボード | `app/Nibble.xcodeproj` / `Nibble` | [app/project.json](../app/project.json) |
| VerificationApp | 共通コマンド・文字列照合・撮影を試験するfixture | `validation/VerificationApp.xcodeproj` / `VerificationApp` | [validation/project.json](../validation/project.json) |
| ResearchProbe | 保存・検索・入力・コピー・復旧・OS連携の比較 | `validation/ResearchProbe.xcodeproj` / `ResearchProbe` | [validation/research-project.json](../validation/research-project.json) |

最低対応OSはiOS 26.0、実行対象はiOS 26.5。製品の操作と期待結果は[MVP手順](mvp.md)、研究の比較条件は[ResearchProbe手順](../validation/RESEARCH.md)を参照する。`ios.py`の対象設定を省略するとVerificationAppを選び、`smoke`もこのfixtureだけに使用できる。

以下のコマンドは、リポジトリルートで開いたNixシェル内で実行する。エージェントとCIはJSON形式を指定する。

```sh
nix develop
export NIBBLE_UI_FORMAT=json
```

stdoutは呼び出し元が読む結果、stderrは進捗・診断に使う。表示障害を理由に実行済みの操作を再試行しない。詳細は[スクリプトの出力契約](script-tooling.md#出力と成否の契約)を参照する。

## 環境の確認

Xcodeは`xcode-select`の選択先を使う。シェル単位で切り替える場合は、実際のインストール先に合わせて`DEVELOPER_DIR`を設定する。

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
python3 scripts/ios.py doctor
python3 scripts/ios.py devices
```

`doctor`はツール・runtime・shared scheme、`devices`は利用可能なSimulatorをJSONで返す。runtimeのversionが26.5であることを確認し、buildversionも検証条件に残す。

## Simulatorの作成と選択

操作対象には検証専用SimulatorのUDIDを明示する。UDIDは端末の一意な識別子で、同名のSimulatorも区別できる。既存の専用端末を再利用する場合は`devices`の出力でruntimeを確認する。

専用端末を新しく用意する場合は、利用可能なruntimeとdevice typeを選んで作成する。device typeは`xcrun simctl list devicetypes`で確認できる。

```sh
python3 scripts/ios.py create \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  --name 'nibble Verification 26.5'
```

`create`は毎回新しい端末を作り、stdoutへUDIDを返す。得られた値を次の変数へ設定する。作成・実行ともiOS 26.5以外は拒否される。

```sh
export NIBBLE_SIMULATOR='対象SimulatorのUDID'
python3 scripts/ios.py boot --device "$NIBBLE_SIMULATOR"
open -a Simulator
```

画面操作の前に対象端末のウィンドウを表示する。端末名や暗黙の`booted`を操作先に使わず、既存端末を消去・削除しない。

## 変更から検証を実行する

比較元を指定して計画を確認する。差分には比較元からのコミット済み変更、ステージ済み・未ステージの変更、未追跡ファイル、削除を含む。

```sh
python3 scripts/verify.py plan --base origin/main
```

計画の`steps`は選択した工程、`excluded`は対象外の工程と理由、`preconditions`は実行前の準備、`manual_review`は自動工程とは別に判断する確認事項を示す。主な選択規則は次のとおりで、複数の変更に該当すると必要な工程を合わせて選ぶ。

| 変更の区分 | 共通静的検査に加える工程 |
| --- | --- |
| Markdown・文書・エージェント指示、分類済みの静的検査・その回帰テスト | なし |
| `app/NibbleTests/` | 製品targetの全テスト |
| `validation/VerificationAppTests/` | fixtureの全テスト |
| 製品の実装・アセット・Xcode設定 | 製品テスト、MVP・通知・固定表示・説明画面のUI |
| 個別の製品UI driver | そのdriverのUI導線 |
| その他の`validation/` | fixtureと研究targetのテスト・UI |
| 共通基盤・依存設定・分類できない変更 | fixture・製品・研究targetの全工程 |

計画に`about`が含まれる場合は、専用Simulatorの「設定 > アクセシビリティ > 動作」を開いておく。英語表示ではSettings > Accessibility > Motionに当たる。driverは「視差効果を減らす」を観測・操作し、終了時に元へ戻す。共有拡張・キーボードのOS導線や研究の比較実験は、変更した責務と製品・研究手順に照らして確認する。

準備ができたら実行する。`run`は実行時のソースから計画を作るので、先に表示した`plan`の結果を固定して実行するコマンドではない。

```sh
python3 scripts/verify.py run --base origin/main --device "$NIBBLE_SIMULATOR"
```

共通静的検査、対象targetの全テスト、UI操作を順に実行する。iOS工程はReleaseを使う。文書だけの計画では`--device`を省略でき、Simulatorを起動しない。実行中はソースを編集しない。

stdoutに成否と結果ファイルのパスを返す。既定の保存先は`artifacts/verify/<検証実行ID>/result.json`で、任意の新しいディレクトリを`--output`で指定できる。既存の結果は上書きしない。

| 結果の項目 | 確認する内容 |
| --- | --- |
| `status`・`error` | 検証実行全体の成否と失敗理由 |
| `steps` | 工程ごとのコマンド、成否、時間、ログ、生成したrun、証跡照合 |
| `source_start`・`source_end` | 開始・終了時のソース内容 |
| `manual_review` | 自動成功に含まれない確認事項 |

失敗・中断・ソース変更では後続を開始せず、失敗と未開始工程を残す。該当する工程ログとrunを調べ、原因を修正して新しい保存先で実行する。媒体の目視と未解決事項の確認は、自動工程の`passed`とは別に完了させる。

### 成功結果からの再計画

合格後の追加差分には、成功結果のパスを指定する。

```sh
python3 scripts/verify.py plan --since artifacts/verify/対象ID/result.json
python3 scripts/verify.py run --since artifacts/verify/対象ID/result.json \
  --device "$NIBBLE_SIMULATOR"
```

`--since`は全工程が成功し、開始・終了ソースが一致する結果だけを受理する。共通静的検査は再計画にも含む。参照元の実行範囲が拡大するわけではなく、過去の媒体を現在のソースへ自動で認定するものでもない。runの再利用は[ソース照合](review-evidence.md#runのソースと結果)で確認する。

対象を明示する場合は`--scope fixture`、`--scope product`、`--scope all`を使う。これは自動選択した範囲への追加ではなく、指定した範囲への切り替えである。未解決事項がある導線はscope指定または個別コマンドで確認し、一部の範囲の成功を全対象の合格として扱わない。

## ビルド・テスト・動作確認

個別コマンドは特定工程の調査や明示的な再検査に使う。計画に従って合格した工程を、追加の変更や懸念なしに繰り返す必要はない。次はVerificationAppをReleaseで検証する例である。

```sh
python3 scripts/ios.py build --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py test --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py run --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py smoke --configuration Release --device "$NIBBLE_SIMULATOR"
```

`build`はビルド、`test`はビルドとSwift Testing、`run`はビルド・インストール・起動・画面読取を行う。`--configuration`の省略値はDebugなので、受け入れ検証ではReleaseを明示する。`test`は終了コードとxcresult summaryを確認し、成功1件以上・失敗なしを要求する。0件と全skipは合格にならない。

`smoke`はfixtureの画面読取、リセット、入力欄選択、ダミーテキスト貼り付け、反映、出力値の完全一致を検査し、画像と録画を生成する。既定の入力は`日本語 👩🏽‍💻`、改行、`Hello, nibble!`で、`--text`で変更できる。専用端末のクリップボードとfixtureの入力状態を書き換える。

ビルドは実行Mac向けのarchitectureを使い、テスト用とUI用でキャッシュを分ける。製品はApp Groupのentitlementを渡すためad hoc署名を使い、Developer Teamや証明書を必要としない。署名設定を省略したfixture・研究用targetは未署名でビルドする。

## 検証対象の切り替え

製品には`app/project.json`、ResearchProbeには`validation/research-project.json`を指定する。

```sh
python3 scripts/ios.py test --project-config app/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/check-mvp-ui.py --device "$NIBBLE_SIMULATOR"

python3 scripts/ios.py test --project-config validation/research-project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
python3 validation/check-research-ui.py --device "$NIBBLE_SIMULATOR"
```

`build`や`run`にも同じ`--project-config`を指定できる。製品の通知・固定表示・説明画面とOS連携は[MVP手順](mvp.md)、研究の保存方式・Safari・日本語入力・表示条件は[研究手順](../validation/RESEARCH.md)を参照する。

targetを定義する際は、`project`・`scheme`・`bundle_id`・`app_name`・`minimum_ios`を持つ設定を用意する。実行管理と撮影は共通driver、操作と期待結果は対象別driverへ置く。

## 個別の画面読取と操作

```sh
python3 scripts/ios.py ui --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py tap --device "$NIBBLE_SIMULATOR" fixture.input
python3 scripts/ios.py paste --device "$NIBBLE_SIMULATOR" \
  --target-id fixture.input --text '日本語の確認 🧪'
python3 scripts/ios.py tap --device "$NIBBLE_SIMULATOR" fixture.apply
```

この例は起動済みのVerificationAppを操作する。`tap`と`paste`は操作前後の画面情報を保存する。対象の期待結果は呼び出し側が確認する。

直接sim-useを使う場合もNixシェル内で実行する。`sim-use ui --json --no-raw`で観測した`uniqueId`を操作先に使う。原文の比較には`value`を使用し、空白や改行が表示用に整形される`label`やoutlineを代用しない。

状態遷移を待つdriverは`Run.ui(allow_empty=True)`で要素0件の取得を中間状態として扱える。有限回の待機と最終状態の条件はdriverが所有する。通常の単発読取は空を失敗とし、ツールの失敗や対象processの終了は待機中も失敗させる。

`paste --via-menu`は編集メニューを通すため、Simulatorのハードウェアキーボード接続に依存しない。貼り付けによる日本語入力は、IMEの変換・未確定文字・候補選択を検証しない。IMEは独立した操作で確認する。許可ダイアログや想定外の画面は読み取って対応し、権限を一括許可しない。

## スクリーンショットと画面録画

```sh
python3 scripts/ios.py screenshot --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py record --device "$NIBBLE_SIMULATOR" --seconds 10
```

静止画は`simctl io screenshot`、動画は`simctl io recordVideo`で取得する。録画は開始通知を待ち、SIGINTで確定する。`--seconds`は0より大きく60以下を指定する。動画の長さと代表フレーム3枚はSwift・AVFoundation・AppKitで取得する。

fixtureのsmokeでは、録画の確定後に操作後の静止画を撮影する。同時取得によってボタン文字が欠ける場合を避け、静止画と録画を独立して確認できる順序にする。

任意の操作を記録する場合は、一つのターミナルで`record`を実行し、別のターミナルでNixのsim-useを使う。直接のsim-useやXcode操作はdriverの端末ロックに参加しない。同じUDIDへ別の検証を同時に流さない。

## 成果物とレビュー

| 保存先 | 内容 |
| --- | --- |
| `artifacts/verify/<検証実行ID>/` | 計画・工程結果・所要時間・工程ログ・runへの参照 |
| `artifacts/ios/<UTC日時>-<コマンド>-<ID>/` | 個別runのmanifest・ネイティブログ・xcresult・画面情報・媒体 |
| `artifacts/ios/DerivedData/<UDID>/<ビルド条件のhash>/` | 構成別のビルドキャッシュ |

すべてGit管理対象外で、新しいcheckoutには含まれない。失敗した記録も残す。キャッシュの存在だけではソースとの対応を保証できず、各build・test・launchでXcodeの増分検査を行う。

[証跡手順](review-evidence.md)に従い、対象ソース・実行結果・媒体を照合し、実際に開いた画像・録画の観測と閲覧条件を`review.json`へ記録する。単独撮影は補助資料であり、インストール済みアプリのソースを証明しない。

## 検証時間を比較する

[benchmark-verification.py](../scripts/benchmark-verification.py)は、JSONで指定したコマンド列を一巡の検証サイクルとして連続実行する。各工程とサイクルの時間、成功回の中央値・最小・最大・ばらつき、測定時間窓内の完了数を`results.json`へ保存する。失敗は記録して停止し、自動再試行しない。

次は起動済みの専用端末でfixtureのtestとsmokeを測る例。測定するキャッシュ条件に合わせて準備実行を済ませ、`--condition`へ実際の条件を記載する。

```sh
mkdir -p artifacts
cat > artifacts/verification-commands.json <<JSON
[
  ["python3", "scripts/ios.py", "test", "--device", "$NIBBLE_SIMULATOR", "--configuration", "Release"],
  ["python3", "scripts/ios.py", "smoke", "--device", "$NIBBLE_SIMULATOR", "--configuration", "Release"]
]
JSON
python3 scripts/benchmark-verification.py \
  --commands artifacts/verification-commands.json \
  --output artifacts/verification-benchmark --samples 3 \
  --condition 'Release、起動済み専用Simulator、依存取得済み、準備実行済みのキャッシュ、ソース変更なし'
```

出力先には新しいディレクトリを使い、測定中はソースを固定する。初回、ソース変更なし、代表編集、失敗と修正後は別条件にする。対象ソース・依存lock・端末・構成・キャッシュ状態・データ・負荷・試行数を記録し、初回の依存取得や人による修正・媒体レビューを通常反復の時間と混ぜない。実行方式の比較条件と適用限界は[評価記録](verification-performance.md)を参照する。

runの`timing`は経過時間、外部コマンドの合計、manifest書込、終了処理の内訳を持つ。入れ子の工程があるため単純に合算しない。`xcodebuild`ログの`-showBuildTimingSummary`も工程分析に使える。benchmarkはコマンドの成否とソースの安定を集計するもので、媒体の整合性や目視は[証跡手順](review-evidence.md)で確認する。

## 検証範囲

共通fixtureの合格は製品の操作・権限・表示の合格を意味しない。製品の受け入れ条件は[MVP手順](mvp.md)、未確認条件は[検証範囲](mvp-validation.md)に従う。Simulatorと実機の性能は異なる条件として扱う。製品MVPの受け入れに実機は含めず、配布後の確認は[TestFlight手順](testflight.md)の担当者が行う。
