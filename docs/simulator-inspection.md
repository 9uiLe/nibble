# Simulator観測データの確認

画面確認では、操作の状態をaccessibility情報で読み、外観を画像で、時間変化を録画で確認する。実行時のJSON・PNG・MP4は原本として保存し、AIには判断に必要な要素・領域・時刻を渡す。原文の保持、表示の細部、未確認範囲を区別しながら入力を抑えるための構成である。

この文書は、保存済みデータを扱う`inspect_ui.py`の公開インターフェースと開発方法を定義する。原本の取得は[iOS実行手順](ios-verification.md#個別の画面読取と操作)、観測内容の記録は[証跡手順](review-evidence.md#画像動画のレビュー記録)、責務と保証範囲は[基盤設計](decisions/0001-local-ios-verification.md#画面の観測と閲覧用データ)を参照する。

## 実行環境と入出力

[READMEのセットアップ](../README.md#セットアップ)を済ませ、リポジトリルートのNixシェルで実行する。

```sh
nix develop
export NIBBLE_UI_FORMAT=json
python3 scripts/inspect_ui.py --help
```

`tree`はPython標準ライブラリで動作する。`image`はmacOS付属の`/usr/bin/sips`を使う。保存済みファイルの加工にSimulatorの起動は不要である。

CLIは引数とファイルを入力に取り、成功時に結果JSONをstdoutへ1件出す。処理の成否表示は`script_ui`経由でhamioがstderrへ出力する。`--help`と引数の構文エラーはargparseが直接表示する。終了コードは成功0、処理失敗1、引数エラー2。表示障害で加工を再試行しない。詳細は[入出力設計](script-tooling.md#出力と成否の契約)を参照する。

## 画面要素の読取

`tree`の入力には、`sim-use ui --json --no-raw`の応答、または`Run.ui()`が返す`data`オブジェクトを保存したJSONを指定する。失敗応答、不正な要素型、重複するJSONキー、非有限数は拒否する。原本のhashは解析するバイト列から計算する。

次の同梱サンプルは架空のダミー画面情報で、Simulator実行の証跡ではない。Nix環境だけでコマンドの出力を確認できる。

```sh
python3 scripts/inspect_ui.py tree scripts/examples/ui-after.json \
  --before scripts/examples/ui-before.json --id fixture.input --text-limit 0
```

`added.items`に入力後の文字列、`removed.items`に空文字が出る。文字列の空白・改行・Unicodeは保持される。原文照合には完全な`value`を使う。`label`やoutlineは表示用に整形されるため、原文として比較しない。

| 引数 | 仕様 |
| --- | --- |
| `source` | 確認するJSONファイル |
| `--before ファイル` | 比較元を指定し、追加・削除された要素を返す |
| `--id uniqueId` | 元データの識別子に一致する要素へ限定する。複数指定できる |
| `--frames` | 座標をpoint単位で表示・比較する |
| `--limit 件数` | 各結果群の要素数上限。正の整数、既定30 |
| `--text-limit 文字数` | label・valueの表示文字数上限。既定160、0で全文 |

比較対象は要素の`uniqueId`・`role`・`label`・`value`・`states`と、指定時の`frame`。完全な値と同じ要素の出現個数を比較してから、結果の表示量を制限する。値の変更は変更前がremoved、変更後がaddedとなる。並び順は比較しない。操作には最新の観測のIDを使う。

### 結果JSON

| 項目 | 意味 |
| --- | --- |
| `schema_version` / `kind` | `1` / `accessibility` |
| `mode` | 単一読取は`snapshot`、比較は`difference` |
| `source.path` / `source.sha256` | 解析した原本とそのhash |
| `context` | アプリ名・bundle ID・向き・画面座標。原本にある項目だけを含む |
| `selection` | ID、座標の有無、件数上限、文字数上限 |
| `observed_count` / `missing_ids` | 原本の要素数と、現在の観測にない指定ID |
| `elements` | 単一読取の結果群 |
| `before` / `before_context` / `context_changed` | 比較元の原本情報・画面情報と、画面情報の変化 |
| `added` / `removed` | 差分の結果群 |

各結果群は`items`・`total`・`omitted`を持つ。`total`は表示制限前の件数、`omitted`は件数制限で省略した件数。要素の識別子は`id`、座標は`frame_points`として出力し、その他の比較項目は元の名前を使う。文字列を短縮した要素の`text_lengths`には、該当フィールドの元の文字数を記録する。文字数はUnicode codepoint数で数える。

`missing_ids`、`omitted`、`text_lengths`を見て、対象IDや上限を調整する。空の観測や差分がないことは、アプリの合格判定を意味しない。座標を含めても、色・重なり・描画だけの要素は画像で確認する。

## 閲覧用画像の作成

`image`は原本PNGをデコードし、切出し・縮小した閲覧用画像（preview）を作る。原本は変更せず、出力にはどのrunにも属さない新しいディレクトリを指定する。

```sh
export NIBBLE_RUN='artifacts/ios/対象run'
python3 scripts/inspect_ui.py image "$NIBBLE_RUN/before.png" \
  --output artifacts/ui-review/before-overview

# 原本が600×300px以上の場合に左上を切り出す。
python3 scripts/inspect_ui.py image "$NIBBLE_RUN/before.png" \
  --crop 0 0 600 300 --output artifacts/ui-review/before-top
```

ファイル名・出力先・範囲は対象に合わせて指定する。`--crop X Y WIDTH HEIGHT`は原本左上を原点とするpixel座標で、原本内の正の大きさに限る。切出し後に長辺を`--max-edge`以下へ縮小する。既定は960pxで、拡大しない。原寸で確認する領域には、その長辺以上の上限を指定する。

### 結果と生成物

| 項目 | 意味 |
| --- | --- |
| `schema_version` / `kind` | `1` / `image_preview` |
| `source` / `preview` | それぞれの`path`・`sha256`・`size_pixels`（幅、高さ） |
| `transform.crop_pixels` | 原本内の切出し範囲 |
| `transform.max_edge` | 長辺上限 |
| `transform.source_pixels_per_preview_pixel` | 横・縦それぞれの原本pixel数 / previewの1pixel |
| `record` | 加工記録`preview.json`のパス |

画像ツールで`preview.path`を開く。`preview.json`には結果と、実行した変換コマンド・終了コード・ツール出力を保存する。変換は原本のバイト列を複製した作業ファイルで行い、終了時に原本hashの一致を確認する。作業ファイルは処理後に削除するため、記録内のコマンドは実行内容の記録として扱う。

PNGの構造・デコード・出力寸法・原本の一致を確認できた場合に加工記録を確定する。既存出力先、run内への出力、範囲外の切出しは拒否する。出力先を作成した後の失敗は`failure.json`へ残し、成功の`preview.json`を作らない。失敗後も同じディレクトリを上書きしない。

画像生成は目視の実施を示さない。全体像と必要な細部を開き、確認した範囲と未確認項目を[レビュー記録](review-evidence.md#画像動画のレビュー記録)へ残す。previewのpixel座標とSimulator操作のpoint座標は異なるため、画像内座標をtapへ直接渡さない。

## 構成と開発

| ファイル | 責務 |
| --- | --- |
| [inspect_ui.py](../scripts/inspect_ui.py) | 引数、結果JSON、終了コード、hamioへの表示接続 |
| [ui_observation.py](../scripts/ui_observation.py) | 原本の解析とhash、要素選択、差分、省略の明示 |
| [ui_preview.py](../scripts/ui_preview.py) | 出力先の保護、PNGデコード・変換、加工記録と失敗記録 |
| `scripts/examples/ui-*.json` | Simulatorを必要としないCLIのサンプル入力 |
| `scripts/tests/test_ui_*.py` / `test_inspect_ui.py` | 解析・証跡保持・失敗処理・入出力・サンプルの回帰 |
| `scripts/tests/macos/` | Apple sipsを使うデコード・座標・縮小の受入試験 |

共通検査はUbuntu CIでも実行する。macOSの試験はローカルMacで実行し、Simulatorや認証情報を必要としない。

```sh
python3 scripts/verify.py plan --scope inspection
python3 scripts/verify.py run --scope inspection
```

`inspection`は`nix flake check`と`preview-native`を実行し、結果を`artifacts/verify/`へ保存する。自動計画ではCLI・画像加工・macOS試験の変更に`preview-native`を選び、要素解析だけの変更には共通検査を選ぶ。画面取得・アプリ操作を変更した場合は、対象driverと専用iOS 26.5 Simulatorでも確認する。

効率の評価には、同じ確認項目を判定できたか、AIへ入力した画像数・寸法・テキスト量を使う。token数や料金は使用環境の実測として記録し、画素数やファイル容量の減少率で代用しない。
