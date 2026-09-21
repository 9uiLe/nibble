# ローカルiOS検証の手順

この手順は、専用Simulatorで検査を実行し、操作結果と画面の確認に必要な記録を取得するためのもの。`verify.py`で検査を計画・実行し、個別の調査には`ios.py`と対象別UI driverを使う。保存済みの画面情報は`inspect_ui.py`で要約できる。構成と保証範囲は[検証基盤の設計](architecture/verification.md)に定義する。

一連の検証実行の結果は`result.json`、個別のiOSコマンドの記録であるrunは`manifest.json`へ保存する。自動工程の成功を確認した後、画像・録画を開いて観測を記録する。

## 検証対象と前提

[READMEのセットアップ](../README.md#セットアップ)を完了し、Xcodeのライセンス・追加コンポーネント・iOS 26.5 Simulator runtimeを用意する。補助ツールはNixで管理するが、XcodeはローカルMacへ別途導入する。

| 対象 | 目的 | project / shared scheme | 設定ファイル |
| --- | --- | --- | --- |
| Nibble・NibbleShare・NibbleKeyboard | 製品の保存・画面・共有・キーボード | `app/Nibble.xcodeproj` / `Nibble` | [app/project.json](../app/project.json) |
| VerificationApp | 共通コマンド・文字列照合・撮影を試験するfixture | `validation/VerificationApp.xcodeproj` / `VerificationApp` | [validation/project.json](../validation/project.json) |
| NibblePerformance | Riveの時間・メモリ測定 | `app/Nibble.xcodeproj` / `NibblePerformance` | [app/performance-project.json](../app/performance-project.json) |

最低対応OSはiOS 26.0、実行対象はiOS 26.5。製品の期待動作は[製品仕様・要件](product-specification.md)、自動工程の責務は[テスト設計](testing.md)を参照する。`ios.py`の対象設定を省略すると製品のNibbleを選ぶ。`fixture-smoke`は基盤試験用のVerificationAppを選び、このfixtureだけに使用できる。

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
python3 scripts/verify.py plan --base origin/main --output artifacts/verification-plan
```

`--output`は新しいディレクトリへ完全な`plan.json`を保存し、stdoutには工程ID・変更件数・手動確認と参照先を返す。再計画には別の保存先を使う。選択理由の確認には保存した計画を開く。`--output`を省略すると従来どおり詳細をstdoutへ返す。

完全な計画の`steps`は選択した工程と理由、`excluded`は対象外の工程と理由、`preconditions`は実行前の準備、`manual_review`は自動工程とは別に判断する確認事項を示す。主な選択規則は次のとおりで、複数の変更に該当すると必要な工程を合わせて選ぶ。

| 変更の区分 | 共通静的検査に加える工程 |
| --- | --- |
| Markdown・文書・エージェント指示、分類済みの静的検査・画面要素の解析・その回帰テスト | なし |
| 画面確認CLI・画像加工・macOSの画像試験 | ローカルMacの`preview-native`。Simulatorは不要 |
| `app/NibbleTests/` | 製品targetの全テスト |
| `validation/VerificationAppTests/` | fixtureの全テスト |
| 製品の実装・アセット・Xcode設定 | 製品テスト、基本操作・通知・固定表示・説明画面のUI |
| 個別の製品UI driver | そのdriverのUI導線 |
| その他の`validation/`（保存層の測定harnessを除く） | fixtureのテスト・fixture-smoke |
| `app/NibblePerformanceTests/`、保存層の測定harness | 手動確認欄に測定・比較の実行先を表示。通常回帰へは追加しない |
| `app/TestSupport/` | 製品回帰と、手動確認欄への性能測定の案内 |
| 共通基盤・依存設定・分類できない変更 | `preview-native`とfixture・製品の通常回帰全体 |

製品UIを含む一連の検証は、専用SimulatorのNibbleを初期化した状態から開始する。基本操作のdriverは一巡ごとにダミー項目を残す。項目が蓄積して対象行が画面下部の操作領域に隠れると、コピー確認が成立しない。インストール済みの検証用Nibbleを次のコマンドで削除し、アプリのダミーデータを初期化する。端末のOS設定とDerivedDataは維持され、次のdriverがビルド・installする。

```sh
xcrun simctl uninstall "$NIBBLE_SIMULATOR" nibble.9uiLe.com
```

説明画面のdriverは、専用Simulatorの設定を開き、観測したコントロールから「アクセシビリティ > 動作」へ移動する。「視差効果を減らす」の現在値を確認して操作し、終了時に元へ戻す。設定画面へ到達できない場合は有限回の観測で失敗とする。共有拡張・キーボードのOS導線は、変更した責務と本書の操作手順に照らして確認する。

準備ができたら実行する。`run`は実行時のソースから計画を作るので、先に表示した`plan`の結果を固定して実行するコマンドではない。

```sh
python3 scripts/verify.py run --base origin/main --device "$NIBBLE_SIMULATOR"
```

共通静的検査、選択されたmacOSの画像試験、対象targetの全テスト、UI操作を順に実行する。iOS工程はReleaseを使う。文書だけの計画では`--device`を省略でき、Simulatorを起動しない。実行中はソースを編集しない。

stdoutに成否と結果ファイルのパスを返す。既定の保存先は`artifacts/verify/<検証実行ID>/result.json`で、任意の新しいディレクトリを`--output`で指定できる。既存の結果は上書きしない。

| 結果の項目 | 確認する内容 |
| --- | --- |
| `status`・`error` | 検証実行全体の成否と失敗理由 |
| `steps` | 工程ごとのコマンド、成否、時間、ログ、生成したrun、証跡照合 |
| `source_start`・`source_end` | 開始・終了時のソース内容 |
| `manual_review` | 自動成功に含まれない確認事項 |

失敗・中断・ソース変更では後続を開始せず、失敗と未開始工程を残す。該当する工程ログとrunを調べ、原因を修正して新しい保存先で実行する。媒体の目視と未解決事項の確認は、自動工程の`passed`とは別に完了させる。

### 検証状態を確認する

実行中・中断後の状態は、ソースsnapshot全体やログ全文を読む前に要約する。

```sh
python3 scripts/verify.py status --result artifacts/verify/対象ID/result.json
```

記録された成否・失敗理由、工程ごとの時間・ログ・run、開始時からの変更ファイル、手動確認事項を返す。ログは`result.json`の親ディレクトリ基準。`source_stable`は記録内の開始・終了ソースの一致、`source_matches_current`は終了ソースと現在のworktreeの一致で、終了記録がなければ両方`null`となる。結果は完全なJSONを一時ファイルから置換して保存するため、実行中も読み取れる。

`status`の終了コード0は読み取り成功を意味する。`status: failed`を成功へ変えず、`running`はプロセスの生存を保証しない。媒体hashや観測の真実性は検査しない。引き継ぎ先や別worktreeではソース不一致を確認し、必要なログ・runだけを開く。待機には起動元のプロセス待機を使い、状態の短周期ポーリングを繰り返さない。

### 成功結果からの再計画

合格後の追加差分には、成功結果のパスを指定する。

```sh
python3 scripts/verify.py plan --since artifacts/verify/対象ID/result.json
python3 scripts/verify.py run --since artifacts/verify/対象ID/result.json \
  --device "$NIBBLE_SIMULATOR"
```

`--since`は全工程が成功し、開始・終了ソースが一致する結果だけを受理する。共通静的検査は再計画にも含む。参照元の実行範囲が拡大するわけではなく、過去の媒体を現在のソースへ自動で認定するものでもない。runの再利用は[ソース照合](review-evidence.md#runのソースと結果)で確認する。

対象を明示する場合は`--scope inspection`、`--scope fixture`、`--scope product`、`--scope regression`、`--scope performance`を使う。`regression`は通常回帰全体、`performance`はRiveの測定targetを選ぶ。`inspection`は共通検査とmacOSの画像試験を選び、`--device`を必要としない。これは自動選択した範囲への追加ではなく、指定した範囲への切り替えである。未解決事項がある導線はscope指定または個別コマンドで確認し、一部の範囲の成功を全対象の合格として扱わない。

## ビルド・テスト・動作確認

個別コマンドは特定工程の調査や明示的な再検査に使う。計画に従って合格した工程を、追加の変更や懸念なしに繰り返す必要はない。次は製品のNibbleをReleaseで検証する例である。

```sh
python3 scripts/ios.py build --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py test --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py run --configuration Release --device "$NIBBLE_SIMULATOR"
```

`build`はビルド、`test`はビルドとSwift Testing、`run`はビルド・インストール・起動・画面読取を行う。`--configuration`の省略値はDebugなので、受け入れ検証ではReleaseを明示する。`test`は終了コードとxcresult summaryを確認し、成功1件以上・失敗なしを要求する。0件と全skipは合格にならない。

`fixture-smoke`はfixtureの画面読取、リセット、入力欄選択、ダミーテキスト貼り付け、反映、出力値の完全一致を検査し、画像と録画を生成する。既定の入力は`日本語 👩🏽‍💻`、改行、`Hello, nibble!`で、`--text`で変更できる。専用端末のクリップボードとfixtureの入力状態を書き換える。

ビルドは実行Mac向けのarchitectureを使い、テスト用とUI用でキャッシュを分ける。製品はApp Groupのentitlementを渡すためad hoc署名を使い、Developer Teamや証明書を必要としない。署名設定を省略したfixtureは未署名でビルドする。

## 検証対象の切り替え

製品には`app/project.json`、基盤fixtureには`validation/project.json`、Rive測定には`app/performance-project.json`を指定する。設定の読込と検査は`scripts/ios_project.py`が担う。必須項目は`project`・`scheme`・`bundle_id`・`app_name`・`minimum_ios`で、任意の`simulator_signing`は`disabled`または`ad-hoc`とする。未知のキー、空の値、存在しないproject、不正なbundle ID・OS版・署名方式は、Appleツールを起動する前に拒否する。

```sh
python3 scripts/ios.py test --project-config app/project.json \
  --configuration Release --device "$NIBBLE_SIMULATOR"
python3 scripts/check_library_ui.py --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py fixture-smoke --configuration Release --device "$NIBBLE_SIMULATOR"
```

`build`や`run`にも同じ`--project-config`を指定できる。製品の通知・説明画面・OS連携は次節を参照する。

## 製品の操作検証

通常は`verify.py run --scope product`で製品テストとUI工程を実行する。`library-ui`工程は`check_library_ui.py`で基本操作を検査する。作成・下書き・編集・検索・原文コピー・ピン・削除と復元を確認し、期待結果は[製品仕様・要件](product-specification.md#機能要件と受け入れ条件)へ対応させる。

固定表示は`check_interface_ui.py --device "$NIBBLE_SIMULATOR"`で一覧・編集・設定・両説明画面を巡回する。標準と最大文字サイズ・高コントラストの配置を比較し、最小文字はhostedテストで確認する。OS所有の入力UIやVoiceOver音声を画像比較の合格に含めない。

### 検索・設定・編集操作の検証

```sh
python3 scripts/check_controls_ui.py --device "$NIBBLE_SIMULATOR"
```

`controls-ui`は検索への移動だけでは入力を開始しないこと、設定のバージョンとインストール済みbundleの一致、削除一覧への往復、設定からの新規作成と呼出元への復帰を確認する。編集では44pt以上の操作領域、キーボードと画面側の操作の排他、補足から戻った時の入力フォーカス復元を検査する。

設定末尾の区切り線がないこと、アイコンの外観、キーボード上の8ptの間隔、背景の連続性、案内文のまとまりは保存した画像を全体と細部で確認する。標準幅と狭幅の専用Simulatorで実行し、AXの成功だけで外観を確認済みにしない。

### 操作完了通知の検証

```sh
python3 scripts/check_notice_ui.py --device "$NIBBLE_SIMULATOR"
```

起動直後のコピー、連続操作による通知の置換、削除と取り消し、検索入力中のフォーカス、期限、タブ・シート・背景への離脱を確認する。表示前・表示中・消去後のタブと作成ボタンに1ptを超える変化があれば失敗する。`--geometry-only`は起動直後のコピーと配置に絞り、`--scroll`は8件を追加して末尾行の位置保持も確認する。`--appearance dark`でダークを選ぶ。表示・録画・読み上げ・実機の触覚は別々の検証範囲として記録する。

### 説明イラストの検証

設定アプリの「アクセシビリティ > 動作」でReduce Motionスイッチを読み取れる状態にして実行する。

```sh
python3 scripts/check_about_ui.py --device "$NIBBLE_SIMULATOR" --story about --interruptions --fault-retry
python3 scripts/check_about_ui.py --device "$NIBBLE_SIMULATOR" --story keyboard --interruptions --fault-retry
```

実アセットの複数周期、本文末尾、ライト／ダーク、背景復帰、表示中のReduce Motion切替を録画する。`--interruptions`はタブ往復と可視境界のスクロール、`--stress`は反復と30秒の背景滞在、`--reduce-motion enabled`は初期から有効な条件を選ぶ。driverは設定を復元する。

`--fault-retry`はインストール済みアセットのhashを照合し、一時的な破損・代替表示・元のバイト列の復元・実ボタンでの回復を確認する。制作ソースや配布物は変更しない。図の意味・動きは録画と時刻付き抽出画像を開いて確認し、全編再生と抽出確認を区別する。可視率、複合停止理由、全面シート、Session解放はhostedテスト、描画時間は[性能測定](performance-verification.md)が担当する。

### 共有・ペースト・呼び出しの検証

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory validation
```

専用SimulatorのSafariで`http://127.0.0.1:8766/ShareHost.html`を開く。テキスト共有→nibbleで保存→本体コピー→Safariの標準編集メニューからペーストし、「本文のUTF-8を表示」で全バイトを照合する。URL共有も保存・コピー後のURLと照合する。共有を閉じた下書きは本体で再開する。終了後はサーバーを停止する。

ペースト結果の検証にクリップボードを上書きする`sim-use paste`を使わない。日本語のかな入力・変換確定はペーストと別に操作する。ショートカットの「URLを開く」から`nibble://library`と`nibble://new`を呼び出し、前者は一覧を初期化、後者は新規作成、編集中はいずれも既存入力を維持することを確認する。

### キーボードの操作検証

本体UI driverとは別に、入力先アプリ、本文、フルアクセス権限、端末・OS・ビルドを記録して確認する。

1. 空白・改行・タブ・結合文字・絵文字を含む本文とピン留め項目を本体で保存する。OS設定でnibbleキーボードを追加する。
2. フルアクセスなしで行のタイトル・本文領域をタップし、1回の挿入と原文のUTF-8を照合する。「…」は挿入せず全文へ進み、長文末尾と戻った位置を確認する。
3. 未許可のコピー・ピン操作は案内だけを表示し、クリップボード・入力欄・ピン状態を変えないことを確認する。許可後はコピーとピン留め・解除が成立し、コピーが挿入を伴わないことを照合する。
4. ピン留め0件、更新、51件以上のページ、変更・削除された項目の利用拒否、標準キーボードへの復帰を確認する。本文取得中の入力先変更・離脱・連打は遅延を制御する製品テストと実操作を組み合わせる。
5. 狭幅・長いタイトル・縦横・ライト／ダークで操作への到達を確認し、権限・外観・向きを元へ戻す。未実施の入力先と表示条件を記録する。

入力欄のフォーカスだけでソフトウェアキーボードの表示を判断しない。`sim-use keyboard-state --device "$NIBBLE_SIMULATOR"`と実画面を照合する。secure入力などOSが標準キーボードへ切り替える条件やホスト側の文字数制限は[Keyboard仕様](architecture/keyboard.md)に従う。

targetを定義する際は、`project`・`scheme`・`bundle_id`・`app_name`・`minimum_ios`を持つ設定を用意する。実行管理と撮影は共通driver、操作と期待結果は対象別driverへ置く。

## 個別の画面読取と操作

画面の要素や入力値はsim-useのaccessibility情報で確認する。外観は[画像の全体と細部の確認](review-evidence.md#画像の全体と細部の確認)、遷移や動きは録画で確認する。対象Simulatorを起動してウィンドウを表示し、同じUDIDへの操作を直列に実行する。

### 画面を取得して操作する

```sh
python3 scripts/ios.py ui --project-config validation/project.json --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py tap --project-config validation/project.json --device "$NIBBLE_SIMULATOR" fixture.input
python3 scripts/ios.py paste --project-config validation/project.json --device "$NIBBLE_SIMULATOR" \
  --target-id fixture.input --text '日本語の確認 🧪'
python3 scripts/ios.py tap --project-config validation/project.json --device "$NIBBLE_SIMULATOR" fixture.apply
```

この例は起動済みのVerificationAppを操作する。`ui`は画面情報を読み取り、`tap`と`paste`は操作前後の画面情報を保存する。操作先には直前の観測で確認した`uniqueId`を使う。コマンド成功後は、操作後の値や状態を期待結果と照合する。

`paste --via-menu`はネイティブ編集メニューを通すため、Simulatorのハードウェアキーボード接続に依存しない。貼り付けによる日本語入力の確認範囲は貼り付けた値とその反映である。IMEの変換・未確定文字・候補選択は別の操作で確認する。許可ダイアログや想定外の画面が出た場合は、その状態を読み取って対応し、権限を一括許可しない。

### 画面要素の要約と差分

画面情報をファイルに保存し、`inspect_ui.py tree`で必要な要素を読む。既存runの`ui.json`や操作前後のJSONも入力に使える。直接sim-useを使う場合は、観測ごとに異なる保存先を選ぶ。

```sh
export NIBBLE_OBSERVATION='artifacts/ui-observations/対象の観測ID'
mkdir -p "$NIBBLE_OBSERVATION"
sim-use ui --device "$NIBBLE_SIMULATOR" --json --no-raw \
  > "$NIBBLE_OBSERVATION/before.json"
python3 scripts/inspect_ui.py tree "$NIBBLE_OBSERVATION/before.json"
```

対象の操作を実行した後、同じSimulatorから新しい画面情報を取得して比較する。

```sh
sim-use ui --device "$NIBBLE_SIMULATOR" --json --no-raw \
  > "$NIBBLE_OBSERVATION/after.json"
python3 scripts/inspect_ui.py tree "$NIBBLE_OBSERVATION/after.json" \
  --before "$NIBBLE_OBSERVATION/before.json"
```

結果は原本hash、選択条件、省略した件数・文字列長を含む。原文照合には対象IDと`--text-limit 0`を指定して完全な`value`を読む。コマンドの引数、結果JSON、判断の限界は[観測データの確認](simulator-inspection.md#画面要素の読取)を参照する。

### 遷移中の画面取得

状態遷移を待つdriverは`Run.ui(allow_empty=True)`で要素0件の取得を中間状態として扱える。有限回の待機と最終状態の条件はdriverが所有する。通常の単発読取は空を失敗とし、ツールの失敗や対象processの終了は待機中も失敗させる。保存済みJSONの要約は待機や期待結果の判定を行わない。

操作コマンドの成功は、画面で操作が成立したことを保証しない。OS設定・共有シート・キーボードでは、画面全体の画像とAXの矩形を照合し、操作後の画面や入力値で成立を確かめる。拡張のAX座標が拡張内の原点を基準にする場合は、その値を画面全体のタップ位置として使わない。タップが反映されない場合は、専用Simulatorの対象アプリを再起動して観測し直す。入力経路の調査にはsim-useの`SIM_USE_NO_DAEMON=1`と`SIM_USE_HID_TRANSPORT=indigo`を実行環境へ指定できる。使用した環境と操作後の観測をrunへ記録し、失敗したrunを残す。保存・削除などの操作は、結果を確認せずに繰り返さない。

## スクリーンショットと画面録画

```sh
python3 scripts/ios.py screenshot --device "$NIBBLE_SIMULATOR"
python3 scripts/ios.py record --device "$NIBBLE_SIMULATOR" --seconds 10
```

静止画は`simctl io screenshot`、動画は`simctl io recordVideo`で取得する。録画は開始通知を待ち、SIGINTで確定する。`--seconds`は0より大きく60以下を指定する。動画の長さと代表フレーム3枚はSwift・AVFoundation・AppKitで取得する。

fixture-smokeでは、録画の確定後に操作後の静止画を撮影する。同時取得によってボタン文字が欠ける場合を避け、静止画と録画を独立して確認できる順序にする。

任意の操作を記録する場合は、一つのターミナルで`record`を実行し、別のターミナルでNixのsim-useを使う。直接のsim-useやXcode操作はdriverの端末ロックに参加しない。同じUDIDへ別の検証を同時に流さない。

## 成果物とレビュー

| 保存先 | 内容 |
| --- | --- |
| `artifacts/verify/<検証実行ID>/` | 計画・工程結果・所要時間・工程ログ・runへの参照 |
| `artifacts/ios/<UTC日時>-<コマンド>-<ID>/` | 個別runのmanifest・ネイティブログ・xcresult・画面情報・媒体 |
| `artifacts/ios/DerivedData/<UDID>/<ビルド条件のhash>/` | 構成別のビルドキャッシュ |
| `artifacts/ui-observations/<観測ID>/` | sim-useを直接使って保存した画面情報 |
| `artifacts/ui-review/<確認ID>/` | 閲覧用画像と原本・変換条件を示す`preview.json` |

すべてGit管理対象外で、新しいcheckoutには含まれない。失敗した記録も残す。キャッシュの存在だけではソースとの対応を保証できず、各build・test・launchでXcodeの増分検査を行う。

[証跡手順](review-evidence.md)に従い、対象ソース・実行結果・媒体を照合し、実際に開いた画像・録画の観測と閲覧条件を`review.json`へ記録する。単独撮影は補助資料であり、インストール済みアプリのソースを証明しない。

## 検証時間を比較する

[benchmark_verification.py](../scripts/benchmark_verification.py)は、JSONで指定したコマンド列を一巡の検証サイクルとして連続実行する。各工程とサイクルの時間、成功回の中央値・最小・最大・ばらつき、測定時間窓内の完了数を`results.json`へ保存する。失敗は記録して停止し、自動再試行しない。

次は起動済みの専用端末でfixtureのtestとfixture-smokeを測る例。測定するキャッシュ条件に合わせて準備実行を済ませ、`--condition`へ実際の条件を記載する。

```sh
mkdir -p artifacts
cat > artifacts/verification-commands.json <<JSON
[
  ["python3", "scripts/ios.py", "test", "--project-config", "validation/project.json", "--device", "$NIBBLE_SIMULATOR", "--configuration", "Release"],
  ["python3", "scripts/ios.py", "fixture-smoke", "--device", "$NIBBLE_SIMULATOR", "--configuration", "Release"]
]
JSON
python3 scripts/benchmark_verification.py \
  --commands artifacts/verification-commands.json \
  --output artifacts/verification-benchmark --samples 3 \
  --condition 'Release、起動済み専用Simulator、依存取得済み、準備実行済みのキャッシュ、ソース変更なし'
```

出力先には新しいディレクトリを使い、測定中はソースを固定する。初回、ソース変更なし、代表編集、失敗と修正後は別条件にする。対象ソース・依存lock・端末・構成・キャッシュ状態・データ・負荷・試行数を記録し、初回の依存取得や人による修正・媒体レビューを通常反復の時間と混ぜない。各コマンドの個別時間と一巡の合計を記録する。アプリ自身の性能は[性能手順](performance-verification.md)で別に測定する。

runの`timing`は経過時間、外部コマンドの合計、manifest書込、終了処理の内訳を持つ。入れ子の工程があるため単純に合算しない。`xcodebuild`ログの`-showBuildTimingSummary`も工程分析に使える。benchmarkはコマンドの成否とソースの安定を集計するもので、媒体の整合性や目視は[証跡手順](review-evidence.md)で確認する。

## 検証範囲

共通fixtureの合格は製品の操作・権限・表示の合格を意味しない。製品の受け入れ条件は[製品仕様・要件](product-specification.md#機能要件と受け入れ条件)、未確認条件は[検証範囲](testing.md#検証範囲と制約)に従う。Simulatorと実機の性能は異なる条件として扱う。製品の受け入れに実機は含めず、配布後の確認は[TestFlight手順](testflight.md)の担当者が行う。
