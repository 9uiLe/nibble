# スニペットキーボードのUI設計根拠

nibbleキーボードは、入力中のアプリを離れずに保存済み本文を識別し、挿入またはコピーする入力面である。本書はAppleの一次資料、構成の比較、製品の採用判断、評価すべき仮説を整理する。採用仕様は[キーボード設計](../docs/decisions/0005-snippet-keyboard.md)、実施結果は[検証記録](../docs/keyboard-validation.md)を正とする。

## 資料の適用範囲

| 項目 | 条件 |
| --- | --- |
| 資料の参照記録 | 背景・構成は2026-09-18、動作名は2026-09-19 |
| 製品 | 日本語の任意長スニペットを選択し、直接挿入・個別コピーする。文字入力キーの再実装は対象外 |
| OS | 最低iOS 26.0、実行評価iOS 26.5 Simulator |
| 一次資料 | Apple HIGの共通節・iOS/iPadOS節、UIKit公式API文書 |
| 観測資料 | iPhone 17 Pro / iOS 26.5のrun `20260918T140332Z-keyboard-ui-f0351c`にある標準英語キーボードのライト表示PNG |
| 未測定 | 利用者の識別性、誤タップ率、操作時間、実機性能 |

HIGは継続更新されるため、参照日の指針とAPIのavailabilityを区別する。APIが提供する能力、製品固有の配色・寸法、特定条件の観測から得た仮説は、それぞれ別の根拠として扱う。非公開のRGB値や寸法をAppleの標準仕様と呼ばない。

## 外部指針と採用判断

### キーボードと本体の役割

Appleは、固有の入力方法をシステム全体へ提供する用途にカスタムキーボードを位置付け、利用可能な領域への適応と別キーボードへの切替を求めている。長い使い方の説明は本体へ置く。[Virtual keyboards](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards)、[Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)

**採用判断**：入力面は選択・挿入・コピーに集中させ、設定手順と全文確認は本体が担う。「入力」はボタンの動作名として常設し、独立したチュートリアル行は置かない。権限が必要な操作の結果として、設定案内をその場で返す。

### 背景とOS所有の操作

`UIInputView.Style.keyboard`は背景のぼかしと色調をキーボードへ合わせるAPIであり、項目の形・文字・配置まで決めるものではない。`needsInputModeSwitchKey`がtrueなら切替キーを提供する。[UIInputView.Style.keyboard](https://developer.apple.com/documentation/uikit/uiinputview/style/keyboard)、[needsInputModeSwitchKey](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/needsinputmodeswitchkey)

**採用判断**：keyboardスタイルの入力面へ透明なSwiftUIホストを重ねる。OSの切替・音声入力を重複して実装せず、必要な地球儀は標準の切替操作へ接続する。

### 対象集合の選択

セグメントは関連する選択肢をまとめ、現在の選択を示す部品である。短いラベルと揃った幅で意味を識別できるようにする。[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)

**採用判断**：「すべて／ピン留め」は同じ一覧への排他的な条件なので、全幅の標準segmented Pickerを使う。更新は実行する操作であり、選択肢には入れない。選択面にチェックマークを重ねない。

### 識別する文字と実行するボタン

文字中心の候補は一列の行で比較できる。ボタンには直ちに行う操作を表す短い動作名、押下状態、隣接する操作と区別できる空間を与える。一般的な44×44ptの操作領域は記号自体のサイズとは異なる。[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

**採用判断**：タイトル・本文要約で対象を識別し、「入力」で押した結果を示す。三つを同じButtonに含め、コピーを別の面へ分ける。詳細へ移動する開示矢印を挿入の説明に使わない。タイトルと要約の始点を揃え、ピンは末尾の属性として扱う。

### 読み順と余白

整列・余白・形状は関連するものをまとめ、役割の違いを示す。重要な内容の面積を補助情報で圧迫しない。[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

**採用判断**：上段は集合、中央は対象、下段は結果・補助操作とする。1ページならページ移動を省略し、短い結果は待機時の製品名と同じ領域に表示する。長い結果の折返しを許し、中央の一覧が高さを調整する。

### 色、素材、文字

Appleはシステム色の意味を保ち、外観へ適応し、一つの色を異なる意味に使わないことを勧めている。主文字・補助文字の階層、少数の文字スタイル、内容とナビゲーションの素材を分ける。[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

**採用判断**：OSの入力面と、押せるキーの面を公開システム色で分ける。`tertiarySystemBackground`は入力面に重なるキー、青は「入力」、secondaryは要約とピンに使う。権限不足は鍵の記号と説明文で伝える。各キーにLiquid Glassを重ねず、本体の[固定表示方針](../docs/design/decisions/0002-fixed-interface.md)を適用する。

[`tertiarySystemBackground`](https://developer.apple.com/documentation/uikit/uicolor/tertiarysystembackground)は階層を表す公開色であり、文字キー専用色ではない。nibbleがキーへ割り当てることは製品判断で、背景との識別は実画面で評価する。

### 権限と操作の独立

AppleはFull Accessなしの共有コンテナ読み取りと、利用者による明示的なFull Accessの許可を説明している。[Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)

**採用判断**：直接挿入は権限なしで使え、コピーだけがフルアクセスを必要とする。権限不足をキーボード全体の利用不能と表現せず、コピーキーから設定案内を表示する。入力先変更と権限取消への処理は[操作の契約](../docs/decisions/0005-snippet-keyboard.md#状態と操作の寿命)に従う。

## 構成の比較

| 構成 | 利点 | 負担と採否 |
| --- | --- | --- |
| 区切り線のリストとセグメント | 文字の横幅と密度を保ちやすい | 即時挿入の操作面とコピーとの境界を別途説明する必要がある。読み取り中心の用途では有力だが、本用途では採らない |
| 一列の入力キー、独立コピー、セグメント | 長いタイトルと要約の幅を保ち、二つの操作を面で分けられる | 行間と面のために面積を使い、押下状態の実装・確認が必要。本文の識別と直接挿入を両立する構成として採用 |
| 二列以上のタイルとカテゴリバー | 短い語を位置で選ぶ用途に向く | 任意長の日本語と似た内容の識別、独立コピーの面積に不利。短いラベルを前提としないため採らない |

一列のキーは文字キーの複製ではない。標準英語キーボードの観測では、ライト表示の背景と明るいキー面、隙間が操作単位を分けていた。この観測を参考に、本文を読み比べる一列の構造と、即時操作を示す面を組み合わせる。単一端末のPNGからAppleの設計意図や全端末の表示を断定しない。

## 設計仮説と評価

| 仮説 | 確認する条件 |
| --- | --- |
| 「入力」と独立したコピー面で結果を識別しやすい | 利用者が初見で操作結果を説明できるか。二つの領域の誤タップ、押下・成功・拒否の識別 |
| 一列の整列で似た文章を読み比べやすい | 同じ先頭、長い日本語、無題、絵文字、ピンあり・なしでの判別 |
| 少数の余白と三領域で位置を把握しやすい | 縦横・狭幅、0件・複数ページ、長い結果文で主要操作へ到達できるか |
| 公開システム色で背景と操作を区別できる | ライト／ダーク、押下・選択・無効、権限有無を実表示で識別できるか |
| 1ページと必要時の本文取得で負荷を限定できる | 同条件の初回表示・スクロール・利用応答・メモリの測定 |

採用は妥当性の測定完了を意味しない。見た目は原本画像、遷移は再生または時刻付きフレーム、原文はUTF-8、性能は対象環境での測定で評価する。実施していない条件は[検証記録](../docs/keyboard-validation.md)へ残す。
