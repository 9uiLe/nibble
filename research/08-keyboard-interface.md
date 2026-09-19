# スニペットキーボードのUI設計根拠

nibbleキーボードは、入力中のアプリを離れずに保存済み本文を識別し、挿入する入力面である。本書は外部指針、構成の比較、製品の採用判断、評価すべき仮説を整理する。操作と実装の契約は[キーボード設計](../docs/decisions/0005-snippet-keyboard.md)、対象ソースごとの実施結果は[検証記録](../docs/keyboard-readability-validation.md)を正とする。

## 資料の適用範囲

| 項目 | 条件 |
| --- | --- |
| 外部資料の参照記録 | 背景・構成は2026-09-18、動作名・フルアクセスは2026-09-19 |
| 製品 | 日本語の任意長スニペットを選び、直接挿入する。詳細で全文確認・コピー・ピン留めを提供する |
| OS | 最低iOS 26.0、実行評価iOS 26.5 Simulator |
| 一次資料 | Apple HIGの共通節・iOS/iPadOS節、UIKit公式API文書 |
| 未測定 | 利用者の識別性、誤タップ率、操作時間、実機性能 |

HIGは継続更新されるため、参照日の指針とAPIのavailabilityを区別する。APIが提供する能力、製品固有の配色・寸法、期待する効果の仮説は、それぞれ別の根拠として扱う。製品の寸法や色の割り当てをAppleの標準仕様とは呼ばない。

## 外部指針と採用判断

### キーボードと本体の役割

Appleは、固有の入力方法をシステム全体へ提供する用途にカスタムキーボードを位置付け、利用可能な領域への適応と別キーボードへの切替を求めている。長い使い方の説明は本体へ置く。[Virtual keyboards](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards)、[Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)

**採用判断**：キーボードは一覧からの挿入と、詳細での全文確認・コピー・ピン留めを担当する。本体は作成・編集・検索・削除と設定手順を担当する。キーボードで内容を確認しても入力先との接続を保ち、確認後にそのまま挿入できる構成とする。

### 背景とOS所有の操作

`UIInputView.Style.keyboard`は背景のぼかしと色調をキーボードへ合わせるAPIであり、項目の形・文字・配置まで決めるものではない。`needsInputModeSwitchKey`がtrueなら切替キーを提供する。[UIInputView.Style.keyboard](https://developer.apple.com/documentation/uikit/uiinputview/style/keyboard)、[needsInputModeSwitchKey](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/needsinputmodeswitchkey)

**採用判断**：keyboardスタイルの入力面へ透明なSwiftUIホストを重ねる。必要な地球儀は標準の切替操作へ接続し、閉じるはOSへ非表示を依頼する。音声入力・ホームインジケータ・セーフエリアはOSの管理対象とし、独自の部品や余白で複製しない。

### 対象集合の選択

セグメントは関連する選択肢をまとめ、現在の選択を示す部品である。短いラベルと揃った幅で意味を識別できるようにする。[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)

**採用判断**：「すべて／ピン留め」は一覧に対する排他的な条件として、コンパクトな2択セグメントにまとめる。各選択肢は44pt以上の高さのタップ領域を持ち、選択状態を見た目と読み上げで伝える。更新は同じ段に置く独立した実行操作とする。

### 識別する文字と実行するボタン

文字中心の候補は一列の行で比較できる。ボタンには操作の意味、押下状態、隣接する操作と区別できる空間を与える。一般的な44×44ptの操作領域は記号自体のサイズとは異なる。[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

**採用判断**：一つの角丸リストを薄い区切り線で分け、タイトルを主情報、1行の本文プレビューを補助情報として読む。タイトルとプレビュー全体を入力Buttonにし、右端の「…」を全文と追加操作への独立したButtonにする。親行のタップ処理と子Buttonを重ねない。ピン印は保存済みの属性を示す。

詳細には「一覧に戻る」、タイトルとスクロール全文、ピン操作、コピー、青い「入力する」を置く。入力する操作名は詳細の主ボタンと行の読み上げ名で伝える。行タップが即時挿入であることを初見で理解できるかは、利用者評価の対象とする。

### 読み順と余白

整列・余白・形状は関連するものをまとめ、役割の違いを示す。重要な内容の面積を補助情報で圧迫しない。[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

**採用判断**：一覧は上段に対象選択、中央に項目、下段に結果・補助操作を置く。詳細では中央を全文のスクロール領域とし、上下の操作は固定する。結果文と待機時の製品名は同じ領域を使い、結果文は2行まで表示する。1ページだけならページ移動は表示しない。

### 色、素材、文字

Appleはシステム色の意味、外観への適応、主文字と補助文字の階層、少数の文字スタイルを示している。[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

**採用判断**：OSの入力面に`tertiarySystemBackground`のリスト・全文領域を重ねる。primaryはタイトルと全文、secondaryはプレビューとピン印、青は詳細の主操作と挿入後の行背景に使う。成功の色と結果文を併用し、権限不足と失敗も文章で伝える。各行にLiquid Glassは使わない。

[`tertiarySystemBackground`](https://developer.apple.com/documentation/uikit/uicolor/tertiarysystembackground)は階層を表す公開色であり、文字キー専用色ではない。nibbleのリストへ割り当てることは製品判断で、背景との識別は実画面で評価する。

文字サイズ・太字・コントラストは本体と共通の[固定表示方針](../docs/design/decisions/0002-fixed-interface.md)を適用し、ライト／ダーク外観へ追従する。VoiceOverの操作名、対象名、状態、結果通知は提供する。固定表示は製品の方針であり、外部指針から導かれるアクセシビリティの推奨とは区別する。

### 権限と操作の独立

AppleはFull Accessなしの共有コンテナ読取と、利用者が許可するFull Accessによる共有領域への書込を説明している。[Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)

**採用判断**：一覧・全文確認・直接挿入はフルアクセスなしで提供し、コピーとピン更新にはフルアクセスを必要とする。未許可の操作は設定案内を表示し、副作用を実行しない。操作中の入力先変更と権限変更への処理は[操作の寿命](../docs/decisions/0005-snippet-keyboard.md#状態と操作の寿命)に従う。

## 構成の比較

| 構成 | 利点 | 負担と採否 |
| --- | --- | --- |
| 単一リスト、行タップで挿入、独立した全文入口 | タイトルの横幅と一覧の密度を確保でき、全文や追加操作をキーボード内で完了できる | 行タップの意味の理解と全文入口の誤タップを評価する。選択と挿入を主目的とする構成として採用 |
| 個別カード、入力・コピーの常設ボタン | 操作名と二つの実行領域が一覧上で見える | カード間の余白とボタン幅が本文の識別領域を圧迫する。採用しない |
| 二列以上のタイル | 短い語を位置で選ぶ用途に向く | 任意長の日本語や似たタイトルを区別できる横幅が少ない。採用しない |
| 全文確認を本体アプリへ集約 | キーボード側の画面構成を小さくできる | 全文を読むために入力作業を中断する必要がある。採用しない |

## 設計仮説と評価

| 仮説 | 確認する条件 |
| --- | --- |
| タイトル中心の単一リストで対象を識別しやすい | 同名・無題・長い日本語・似た本文・絵文字・ピン状態を含む候補から選べるか |
| 行タップと独立した全文入口で選択から挿入までを簡潔にできる | 初見での操作理解、1タップ1挿入、「…」の誤挿入、押下・成功・拒否の識別 |
| 詳細と復帰位置の保持によって確認後も選択を続けやすい | 長文末尾への到達、主操作の発見、フィルター・ページ・スクロール位置の復帰 |
| 固定した操作列と可変の本文領域で表示範囲を使える | 狭幅・縦横・0件・複数ページ・長い結果文で主要操作へ到達できるか |
| 公開システム色で内容・操作・状態を区別できる | ライト／ダーク、押下・選択・無効、権限有無の識別 |
| 1ページと必要時の本文取得で負荷を限定できる | 同条件での初回表示・スクロール・利用応答・メモリの測定 |

採用は妥当性の測定完了を意味しない。見た目は原本画像、遷移は動画の再生または時刻付きフレーム、原文はUTF-8、性能は対象環境での測定によって評価する。未実施条件も[検証記録](../docs/keyboard-readability-validation.md)に明記する。
