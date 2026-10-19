# ローカルiOS検証の手順

`verify.py`で計画・実行し、個別調査には`ios.py`とUI driverを使う。結果は`artifacts/verify/`の`result.json`、各iOS runは`manifest.json`へ保存する。正しい入力・保存・OS作用を一連の操作で確かめたうえで、媒体を実際に開いて観測を残す。基盤と証跡の契約は[検証基盤](architecture/verification.md)と[証跡手順](review-evidence.md)を参照する。

## 検証対象と前提

[セットアップ](../README.md#セットアップ)を完了し、ローカルMacのXcode・iOS 26.5 Simulatorを使う。最低対応OSは26.0、実行検証は26.5だけで、実機を製品の受入に含めない。自分が確保した専用Simulatorとダミーデータを使い、既存端末を消去・削除しない。秘密情報・Keychain・配布設定は対象にしない。

| 対象 | shared scheme / 設定 | 目的 |
| --- | --- | --- |
| 製品・共有・任意のKeyboard | `Nibble` / [app/project.json](../app/project.json) | 原文の再利用と回復 |
| 外部入力先fixture | `VerificationApp` / [validation/project.json](../validation/project.json) | 独立したA/B入力先と結果のUTF-8照合 |
| 性能 | `NibblePerformance` / [app/performance-project.json](../app/performance-project.json) | 検索・ページ取得・長文表示・反復の保持量 |

以下はリポジトリルートのNix環境で行う。

```sh
nix develop
export NIBBLE_UI_FORMAT=json
python3 scripts/ios.py doctor
python3 scripts/ios.py devices
```

stdoutの結果とstderrの進捗を分ける。表示障害を理由に実行済みの業務操作を再試行しない。Xcodeを切り替える場合は、実際に導入した場所を`DEVELOPER_DIR`へ指定する。

## Simulatorの作成と選択

通常は`verify.py run --temporary-device`を使う。結果先を確保してiOS 26.5の専用Simulatorを作成し、失敗・中断を含めて回収結果を記録する。回収に失敗した場合は記録されたUDIDの所有端末だけを調べる。強制終了後は残存する所有端末を照合し、回収まで完了扱いにしない。

手動操作ではUDIDを明示する。狭幅はiPhone SE（第3世代）、通常幅はiPhone 17 Proを別々に確保する。暗黙の`booted`や端末名で操作しない。

```sh
python3 scripts/ios.py create --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  --name 'nibble Verification 26.5'
export NIBBLE_SIMULATOR='作成結果のUDID'
python3 scripts/ios.py boot --device "$NIBBLE_SIMULATOR"
```

自分で作成した端末は媒体の確定後に回収する。再利用した既存端末を削除しない。UI操作は端末ごとの既存排他制御で直列実行し、ビルド・操作中にソースを変えない。

## 変更から検証を実行する

```sh
python3 scripts/verify.py plan --base origin/main
python3 scripts/verify.py run --base origin/main --temporary-device
```

計画はコミット済み・未コミット・未追跡・削除を含む差分から必要な工程を選ぶ。`run`は実行時に再計画する。`--scope regression`は共通静的検査、基盤、製品target全テスト、各UI工程を選び、`--scope performance`は専用Release測定を選ぶ。文書・静的検査だけならSimulatorを使わない。合格後は追加変更・失敗・未解決の懸念へ絞って再計画する。

個別実行は原因調査や、計画で残った責務の確認に使う。

```sh
python3 scripts/ios.py test --device "$NIBBLE_SIMULATOR" --configuration Release
python3 scripts/ios.py run --device "$NIBBLE_SIMULATOR" --configuration Release \
  --project-config validation/project.json
python3 scripts/check_library_ui.py --device "$NIBBLE_SIMULATOR"
python3 scripts/check_notice_ui.py --device "$NIBBLE_SIMULATOR"
python3 scripts/check_controls_ui.py --device "$NIBBLE_SIMULATOR"
python3 scripts/check_about_ui.py --device "$NIBBLE_SIMULATOR"
python3 scripts/check_about_ui.py --device "$NIBBLE_SIMULATOR" --story keyboard
```

`library-ui`の外部PasteにはVerificationAppの事前インストールが必要である。通常回帰はfixture工程を先に行う。製品だけのscopeや個別実行では上のfixture `run`を先に実行する。未準備なら失敗を残し、クリップボードへの書込みだけで外部利用の成功にしない。

各driverは固有名のダミー文章だけを操作する。`library-ui`の保存失敗は、`simctl get_app_container`が返した製品のApp Group内の既存DBへ、対象の固有名だけに作用するSQLite ABORT triggerを入れる。失敗UIと同じ下書きの完全なUTF-8を照合し、finallyでtriggerを除去してから同じ画面の保存を再試行する。製品の試験用入口や、無関係な保存物の破壊を使わない。

公開工程名`about-ui`と`keyboard-guide-ui`のrun名は互換性のため`rive-about` / `rive-keyboard`を維持する。現在は説明の読取と管理への到達を確認する工程で、演出再生の検査ではない。

### 検証状態を確認する

```sh
python3 scripts/verify.py status --result artifacts/verify/対象ID/result.json
```

成否・失敗理由、開始時からの変更、工程とrun、未実施の手動確認を読む。`status`の終了コード0は読取成功で、検証成功の意味ではない。現在ソースと終了snapshot、媒体hash、最終headのCIは[証跡手順](review-evidence.md)で照合する。

### 成功結果からの再計画

```sh
python3 scripts/verify.py plan --since artifacts/verify/対象ID/result.json
python3 scripts/verify.py run --since artifacts/verify/対象ID/result.json --device "$NIBBLE_SIMULATOR"
```

`--since`は開始と終了ソースが一致する成功結果を使う。過去の媒体を新しいソースの合格へ読み替えない。失敗run・未開始工程を残し、修正後は新しい保存先で実行する。

### 検証時間を比較する

resultの各工程時間、runのコマンド時間、build cacheの有無を区別する。同じデータ・端末・Release構成・測定回数をそろえ、初回準備と反復を分ける。driver全体の時間を利用者の課題完了時間やフレーム時間へ換算しない。詳細は[性能検証](performance-verification.md)。

## 検証対象の切り替え

`--project-config app/project.json`が製品、`validation/project.json`が外部fixture、`app/performance-project.json`が性能targetである。設定ファイルとscheme、bundle IDを照合する。fixtureの合格は製品targetの合格ではない。

## 個別の画面読取と操作

```sh
python3 scripts/ios.py ui --device "$NIBBLE_SIMULATOR"
python3 scripts/inspect_ui.py tree artifacts/ios/対象run/画面.json --text-limit 0 --frames
```

[画面観測CLI](simulator-inspection.md)の既存入口を使い、観測していないラベル・座標を操作に使わない。実データ・原画像はrunの中で保持し、閲覧用の加工物は別ディレクトリへ保存する。

## 画面要素の要約と差分

`inspect_ui.py tree`で必要なIDを`--id`へ指定し、`--before`で比較する。要約で切り詰めた値を原文一致の証拠にしない。原文は保存DB、コピー後の`pbpaste`、外部fixtureの反映結果とUTF-8ラベルで照合する。画像は全体と細部を確認し、動画は対象操作の連続性まで読む。

## 製品の操作検証

自動driverの成否に加えて、次の利用全体を実際の操作で確認する。

1. 自分で作成、または他アプリの共有から取り込む。保存して後から検索し、全文を確認して使う。
2. 編集中に閉じる・背景へ移る。作業中から再開し、元の保存文を取り違えず意図した文面で使う。
3. 差し替えを明示的に有効にし、相手と用件を入れる。中断・再開して完成文を確認し、一度コピーする。取消ではコピーもカード公開も起きない。
4. 固有名の文章を削除してUndoする。ごみ箱から同じ原文を戻し、通常一覧とキーボードへの復帰を確認する。
5. 保存障害、元カードの版変更、入力先変更、OSの利用制約を起こす。入力と意図を保持し、失敗の説明から続行する。

少量・5,000件、短文・長文、Unicode、通常幅・狭幅、標準・最大文字サイズで条件を分ける。正しい原文、意図しない作用の防止、作業保持が成立してから時間・操作判断の負担・読みやすさを評価する。

### 日本語IMEを確認する

OSの日本語かな／ローマ字キーボードを選び、実際のキーから日本語を新規入力する。変換候補を選び、未確定文字の訂正・選択置換・確定、タイトルと本文の移動、背景復帰、閉じて再開を行う。未確定中は保存・コピーを実行せず、確定後の全文を確認してコピーする。外部入力先へのPaste後、反映したUTF-8を照合する。

`sim-use paste`、`setMarkedText`、入力欄の存在は、このOS入力・訂正・確定の証拠にならない。操作したキー、候補、訂正前後、保存・作用の結果を動画と観測に残す。

### 変数の編集と利用を確認する

本文へ`{{宛名}}`を入れ、編集の「差し替えを使う」を有効にして保存する。無効のままなら印を含む原文が文字どおり使われることも確認する。有効な文章を選び、値の未入力・空白、中断・再開、完成文確認、取消、コピー、元の版変更からの回復を確かめる。完成文を別カードへ保存した場合は、元のひな型を変えず、名前と由来で識別できることを確認する。

### 共有の操作検証

Safariや[ShareHost](../validation/ShareHost.html)でダミー文章を選び、OS共有シートからnibbleを開く。受け取った文章・URLを確認し、閉じて再開、保存失敗と再試行、保存後の検索・原文コピーまで行う。共有を取消した場合は意図しないカード公開やコピーがないことを確認する。

### キーボードの操作検証

OS設定から任意のnibbleキーボードを追加し、フルアクセスを許可せずに使う。ピン留めした固定文だけが候補に出ることを確認する。外部fixtureのAで候補を選び、全文を確認して一度挿入し、Aの完全な内容とBの不変を照合する。

確認中にAからBへ入力先を変える、選択範囲を変える、元カードを編集・削除する、キーボードを切り替える操作を行い、古い確認から挿入されないことを確認する。パスワード欄、キーボードを拒否するホスト、共有領域へ到達できない場合は入力を変えず、本体のコピーとOSのPasteで続ける。地球儀から通常の日本語入力へ戻れることまで確認する。入力欄の表示だけで拡張内の日本語編集能力を認定しない。

### 説明イラストの検証

この見出しは既存参照用に残す。現在の製品は説明イラストを採用していない。説明工程は、使い方・データの扱いを読み、実際の作成・コピー・Paste、任意のKeyboard追加、管理の利用開始まで到達することを確認する。
