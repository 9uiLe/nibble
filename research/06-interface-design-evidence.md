# UI要素と画面構成の設計根拠

この資料は、nibbleの情報構造、操作、入力、外観、アクセシビリティを設計するための一次資料台帳である。R番号で根拠を識別し、[UI設計](../docs/design/README.md)から参照する。各項目には出典、閲読範囲、要約、製品への示唆または適用限界を記す。

## 対象と確認方法

| 項目 | 範囲 |
| --- | --- |
| 対象製品 | nibbleの日本語iPhone UI、本体・共有拡張・Keyboard |
| OS | 最低対応iOS 26.0、実行評価iOS 26.5 Simulator |
| 資料確認日 | Apple HIG・WWDC・W3Cは2026-09-17。R13の日本語文言資料は2026-09-20 |
| Apple HIG | 公式ページに対応する公開DocC JSON本文の共通節とiOS/iPadOS節 |
| WWDC | 公式transcriptの記載範囲。動画の連続視聴・サンプルの実行は未実施 |
| W3C | 成功基準の説明、目的、適用対象と例外 |
| 保管 | 要約と出典はGit、取得本文はGit管理対象外の`artifacts/design-research/` |

HIGは継続更新され、確認日の内容には2026年の改訂を含む。指針の内容と、iOS 26.0で利用できるAPIは分けて確認する。APIの適合性は公式availability、対象SDK、ビルドで評価し、画面の振る舞いは対象OSで実行する。

指針の要約は外部の根拠であり、製品仕様ではない。採用理由と代替案は[UI設計](../docs/design/README.md)、未確認条件は[評価課題](../docs/design/audit.md)に置く。APIのavailabilityと実画面は別に確認する。

## 情報構造とナビゲーション

### R01 タブバー

出典：[Apple HIG — Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)。閲読範囲：導入、Best practices、iOS/iPadOS。

タブはアプリ内の領域へ移動するための部品であり、実行操作の入口として扱わない。領域の状態を保ち、短いラベルを付け、空の領域でも入口を消さないことを勧めている。

### R02 検索

出典：[Apple HIG — Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)。閲読範囲：Best practices、scope、iOS/iPadOSの配置と起動。

検索対象をplaceholderで伝え、可能なら入力とともに結果を更新する。すぐ検索を始める入口と、候補を探索する検索ページを使い分ける。対象を絞る場合は広い範囲から始める。

### R03 レイアウト

出典：[Apple HIG — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)。閲読範囲：Visual hierarchy、Adaptability、Guides and safe areas。

重要度と読み順で内容を配置し、整列と字下げで関係を示す。画面幅、方向、文字、言語へ適応し、システムのsafe areaを尊重する。

### R04 リスト

出典：[Apple HIG — Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)。閲読範囲：導入、Best practices。

文字中心の項目はリストで読み比べやすい。項目を識別できる簡潔な内容を選び、グループと階層に適した行・リストスタイルを使う。

### R05 ツールバー

出典：[Apple HIG — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)。閲読範囲：Best practices、Titles、Navigation、Actions、Item groupings。

画面タイトルは現在地を示す。バーには主な操作を優先し、関係する操作をまとめ、戻る・閉じるなどの標準部品を使う。独自背景や過密なボタン配置を抑える。

### R06 設定

出典：[Apple HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)。閲読範囲：Best practices、General settings、System settings。

初期設定で利用できるようにし、設定数を抑える。アプリ全体の低頻度な変更は設定へ、現在の作業に関係する変更はその画面へ置く。システム設定を重複して作らない。

## 操作、入力、復旧

### R07 ボタン

出典：[Apple HIG — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)。閲読範囲：Best practices、Style、Content、Roleの一般的な意味。

目的の分かるラベルと十分な間隔を設け、強調ボタンを増やしすぎない。一般則として44×44 pt以上の操作領域を勧める。同列の選択肢の優先度は大きさだけで表さない。

### R08 メニューと長押し

出典：[Apple HIG — Menus](https://developer.apple.com/design/human-interface-guidelines/menus)、[Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)。閲読範囲：ラベル、順序、Best practices。

メニュー項目には操作結果が分かる短い名前を付ける。長押しメニューは隠れているため、同じ操作をメインUIからも利用できるようにすることを勧める。

### R09 シート

出典：[Apple HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)。閲読範囲：Best practices、iOS/iPadOS。

単独で完結する作業を親画面の上で行う。終了方法を明確にし、単一画面では取消を先頭側、完了を末尾側に置く。iOSではスワイプ終了の期待にも対応する。

### R10 確認とエラー

出典：[Apple HIG — Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)、[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)。閲読範囲：Best practices、Buttons、iOS/iPadOS。

自ら始めた操作の選択肢には確認ダイアログ、予期しない重要な問題にはalertを使い分ける。中断を必要最小限とし、何が起きるか分かるボタン名と安全な取消方法を用意する。

### R11 フィードバックと取り消し

出典：[Apple HIG — Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)、[Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo)。閲読範囲：Best practices、iOS/iPadOS。

結果は文脈内で伝え、視覚・触覚・読み上げなどを併用する。取り消し対象と結果を予測できるようにし、標準ジェスチャーの意味を変えない。

### R12 進行状態

出典：[Apple HIG — Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)。閲読範囲：Best practices。

進捗が分かる場合はそれを表し、不明な場合は不定進行表示を使う。実際の処理と一致しない進捗を表示しない。

### R13 文言

文言設計では、操作結果の正確さ、利用者が理解できる語彙、画面内で実行できる回復方法、入力条件の読み取りやすさを確認する。以下は公開されている一次資料の要約であり、nibbleの利用者評価の結果ではない。

| 出典と確認範囲 | 指針 | 製品への適用と限界 |
| --- | --- | --- |
| [Apple HIG — Writing](https://developer.apple.com/design/human-interface-guidelines/writing)のtone、Best practices、空状態・エラー・入力欄。2026-09-17に公開DocC JSON本文を確認 | 短い表現で操作結果を伝え、空状態には次の行動、エラーには回復方法を示す。ラベルとhintを使い分ける | 画面の対象・状態・操作を区別する根拠とする。日本語の具体的な語彙や理解度を保証する資料ではない |
| [Apple WWDC24 — UXライティングでアプリにパーソナリティを追加](https://developer.apple.com/jp/videos/play/wwdc2024/10140/)の日本語トランスクリプト。ボイスとトーンに関する説明 | 製品全体のボイスを保ち、状況に合わせてトーンを調整する | 平常時は穏やかな説明、失敗時は事実と回復方法を中心に書く。確認範囲はトランスクリプトであり、動画視聴や効果測定は含まない |
| [SmartHR — 基本的な考え方](https://smarthr.design/products/contents/writing-style/)の公開本文 | 冗長さ、過剰な敬語、一般的でない用語を避け、助詞と表記を整える | 「下書きに残る」「コピー回数と日時」のように、利用者が判断する対象を具体的に表す。社内資料は確認範囲に含めない |
| [SmartHR — その他のUIテキスト](https://smarthr.design/products/contents/ui-text/app-writing/)の説明文・ラベル・見出し | 説明、操作、対象名を役割に応じて書き分ける | 見出しは対象・状態、ボタンは操作、補足は条件と結果を伝える。同社固有の語尾規則をiOSへ一律に適用しない |
| [デジタル庁 — インプットテキストの使い方](https://design.digital.go.jp/dads/components/input-text/usage/)の入力条件・サポートテキスト・エラー | 入力条件と訂正方法を具体的に説明する | 任意・必須・長さ制限を入力中も読めるラベルと補足で伝える。Webの配置をそのままiOSへ適用しない |

日本語トランスクリプトとSmartHR・デジタル庁の公開本文の確認日は2026-09-20。HIGの要約は2026-09-17のDocC本文に基づき、2026-09-20のHTML取得ではJavaScriptが必要なため本文を確認できていない。

nibbleの語彙、文体、表記と優先順位は[文言とデータの原則（F09）](../docs/design/foundations.md#f09-文言とデータ)に定める。具体的な文言は[文言設計](../docs/design/copy.md)、理解度と読み上げの評価は[検証記録](../docs/copy-validation.md)で扱う。

## 外観とアクセシビリティ

### R14 文字

出典：[Apple HIG — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)。閲読範囲：Conveying hierarchy、built-in text styles、Supporting Dynamic Type。

システムの文字スタイルで階層と拡大を維持する。重要なアイコンも拡大に追従させ、狭い横並びは大きな文字で組み替える。読める内容を残し、切り詰めを抑える。

### R15 色と素材

出典：[Apple HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)。閲読範囲：一般的な色の選択、Liquid Glass、standard materials、iOS/iPadOS。

色の意味を一貫させ、light/darkで判読できるようにする。Liquid Glassは内容の上にある操作・ナビゲーションの層として使い、本文への過剰な適用を避ける。

### R16 アクセシビリティ

出典：[Apple HIG — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)。閲読範囲：Vision、Hearing、Mobility、motionへの対応。

色以外の手掛かり、文字拡大、VoiceOver、単純な操作とジェスチャーの代替を提供する。Reduce Motion等のシステム設定へ対応し、支援技術で確認する。

**数値の注意**：確認日のiOS/iPadOS control size表にはdefault 44×44 pt、minimum 28×28 ptがある。R07の一般則と併記し、nibbleでは独自の反復操作の基準を44×44 pt以上とする。44 ptを全OS・全状況の絶対最小値とは説明しない。

### R17 コントラストと色依存

出典：W3C WCAG 2.2 Understandingの[1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)、[1.4.11 Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)、[1.4.1 Use of Color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)。閲読範囲：成功基準、intent、適用対象・例外。

通常の文字4.5:1、大きな文字3:1、識別に必要な操作部品・状態の非テキスト表現3:1という基準を比較の参考にする。色だけで状態や操作を伝えない。

**適用限界**：Webの基準であり、iOSアプリの認証・法令適合の宣言には使わない。本文の目標は保守的に4.5:1とし、大きい文字の緩和に頼らない。透明素材と背景が変わる組み合わせは別に測る。[Target Size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)の24 CSS pxをiOSの24 ptへ読み替えない。

## ネイティブ実装への接続

### R18 iOS 26の設計体系

出典：[Apple WWDC25 — Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)。閲読範囲：公式transcriptのbars、navigation、visual effects。

機能層と内容を分け、バーの項目は機能と頻度でまとめる。タブのaccessoryは持続する機能向けで、個別画面の操作と混在させないことを説明している。

### R19 SwiftUIでの実装

出典：[Apple WWDC25 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)。閲読範囲：公式transcriptのTab views、Toolbars、Search、Liquid Glass。

標準コンテナ、toolbar、検索role、検索欄の適用位置によって、iOS 26の外観と振る舞いを構成する方法を説明している。

**適用限界**：transcriptはnibbleの特定コードの動作保証ではない。採用するAPIのavailability、検索終了時の遷移、キーボードとの配置は別に確認する。
