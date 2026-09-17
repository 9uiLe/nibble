# UI要素と画面構成の設計根拠

この資料は、nibbleの情報構造、操作、入力、外観、アクセシビリティを設計するための一次資料台帳である。R番号で根拠を識別し、[UI設計](../docs/design/README.md)から参照する。各項目には出典、閲読範囲、要約、製品への示唆または適用限界を記す。

## 対象と確認方法

| 項目 | 範囲 |
| --- | --- |
| 対象製品 | nibbleの日本語iPhone UI、本体と共有拡張 |
| OS | 最低対応iOS 26.0、実行評価iOS 26.5 Simulator |
| 資料確認日 | 2026-09-17 |
| Apple HIG | 公式ページに対応する公開DocC JSON本文の共通節とiOS/iPadOS節 |
| WWDC | 公式transcriptの記載範囲。動画の連続視聴・サンプルの実行は未実施 |
| W3C | 成功基準の説明、目的、適用対象と例外 |
| 保管 | 要約と出典はGit、取得本文はGit管理対象外の`artifacts/design-research/` |

HIGは継続更新され、確認日の内容には2026年の改訂を含む。指針の内容と、iOS 26.0で利用できるAPIは分けて確認する。APIの適合性は公式availability、対象SDK、ビルドで評価し、画面の振る舞いは対象OSで実行する。

## 根拠と判断の区別

| 種類 | 扱い |
| --- | --- |
| 指針 | 発行主体が推奨する設計。対象OSと利用場面を確認して候補の評価に使う |
| APIの事実 | 公式文書が定義する能力と制約。採用コードへの適合性を別に確認する |
| 製品判断 | nibbleの目的と制約に基づく選択。採用理由と代替案の負担を記録する |
| 仮説 | 配置、寸法、文言、色による効果の予測。期待を確かめる条件を付ける |
| 観測 | 記録した対象ソース・端末・データ・手順で得た結果。その条件に結び付けて解釈する |

「設計への示唆」は、指針を製品へ適用する際の判断材料である。採用構成は[画面構成](../docs/design/screens.md)と[部品台帳](../docs/design/components.md)、実装との適合状況と改善候補は[設計監査](../docs/design/audit.md)に定める。指針への適合と、利用者が作業を完了できることは、それぞれ評価する。

## 情報構造とナビゲーション

### R01 タブバー

出典：[Apple HIG — Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)。閲読範囲：導入、Best practices、iOS/iPadOS。

タブはアプリ内の領域へ移動するための部品であり、実行操作の入口として扱わない。領域の状態を保ち、短いラベルを付け、空の領域でも入口を消さないことを勧めている。

**設計への示唆**：一覧・設定・検索を領域、新規作成を操作、ピン留めを同じ一覧の対象変更として区別する。設定タブがnibbleで最適か、タブを常時展開するかは製品判断。

### R02 検索

出典：[Apple HIG — Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)。閲読範囲：Best practices、scope、iOS/iPadOSの配置と起動。

検索対象をplaceholderで伝え、可能なら入力とともに結果を更新する。すぐ検索を始める入口と、候補を探索する検索ページを使い分ける。対象を絞る場合は広い範囲から始める。

**設計への示唆**：保存済み本文・タイトルの検索へ即座に入力できる構成を選ぶ。履歴・候補表示の必要性は、検索対象と利用場面から判断する。下書きと削除項目の扱いは製品のデータ契約で定める。

### R03 レイアウト

出典：[Apple HIG — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)。閲読範囲：Visual hierarchy、Adaptability、Guides and safe areas。

重要度と読み順で内容を配置し、整列と字下げで関係を示す。画面幅、方向、文字、言語へ適応し、システムのsafe areaを尊重する。

**設計への示唆**：タイトル→対象選択→内容の読み順で構造を示す。操作の到達性、内容の識別性、キーボードとの共存をそれぞれ評価する。

### R04 リスト

出典：[Apple HIG — Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)。閲読範囲：導入、Best practices。

文字中心の項目はリストで読み比べやすい。項目を識別できる簡潔な内容を選び、グループと階層に適した行・リストスタイルを使う。

**設計への示唆**：本文をカードへ全面展開せず、タイトルと短い要約を整列する。区切り線と共通背景を選ぶこと、2行に制限すること、ピンを先頭にすること自体はnibbleの判断。

### R05 ツールバー

出典：[Apple HIG — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)。閲読範囲：Best practices、Titles、Navigation、Actions、Item groupings。

画面タイトルは現在地を示す。バーには主な操作を優先し、関係する操作をまとめ、戻る・閉じるなどの標準部品を使う。独自背景や過密なボタン配置を抑える。

**設計への示唆**：ルートの短いタイトル、編集の閉じる・保存、その他メニューを役割で分ける。タイトルの左寄せやサイズはブランドと可読性を比較して決める。

### R06 設定

出典：[Apple HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)。閲読範囲：Best practices、General settings、System settings。

初期設定で利用できるようにし、設定数を抑える。アプリ全体の低頻度な変更は設定へ、現在の作業に関係する変更はその画面へ置く。システム設定を重複して作らない。

**設計への示唆**：操作位置は設定、フィルターは一覧に置く。文字サイズ、ダークモード、Reduce Motionをアプリ独自の設定として増やさない。

## 操作、入力、復旧

### R07 ボタン

出典：[Apple HIG — Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)。閲読範囲：Best practices、Style、Content、Roleの一般的な意味。

目的の分かるラベルと十分な間隔を設け、強調ボタンを増やしすぎない。一般則として44×44 pt以上の操作領域を勧める。同列の選択肢の優先度は大きさだけで表さない。

**設計への示唆**：表示シンボルと操作領域を分ける。新規作成56 pt、コピー44 ptは役割に合わせて比較する製品の設計値である。role APIの採用には個別のavailability確認が必要。

### R08 メニューと長押し

出典：[Apple HIG — Menus](https://developer.apple.com/design/human-interface-guidelines/menus)、[Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)。閲読範囲：ラベル、順序、Best practices。

メニュー項目には操作結果が分かる短い名前を付ける。長押しメニューは隠れているため、同じ操作をメインUIからも利用できるようにすることを勧める。

**設計への示唆**：長押し・スワイプだけをピン留めや削除への入口にしない。常設メニューボタンと編集画面の操作のどちらが適切かを比較する。

### R09 シート

出典：[Apple HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)。閲読範囲：Best practices、iOS/iPadOS。

単独で完結する作業を親画面の上で行う。終了方法を明確にし、単一画面では取消を先頭側、完了を末尾側に置く。iOSではスワイプ終了の期待にも対応する。

**設計への示唆**：作成・編集をシートにする。「閉じる」は下書きを保持して中断する操作として定義し、保存済みへの確定と編集内容の破棄を区別する。スワイプ終了の無効化は保存契約に基づく例外として検証する。

### R10 確認とエラー

出典：[Apple HIG — Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)、[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)。閲読範囲：Best practices、Buttons、iOS/iPadOS。

自ら始めた操作の選択肢には確認ダイアログ、予期しない重要な問題にはalertを使い分ける。中断を必要最小限とし、何が起きるか分かるボタン名と安全な取消方法を用意する。

**設計への示唆**：完全削除と下書き破棄に対象の分かる確認を置く。復元可能な削除には毎回確認を追加せず、回復手段を提示する。

### R11 フィードバックと取り消し

出典：[Apple HIG — Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)、[Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo)。閲読範囲：Best practices、iOS/iPadOS。

結果は文脈内で伝え、視覚・触覚・読み上げなどを併用する。取り消し対象と結果を予測できるようにし、標準ジェスチャーの意味を変えない。

**設計への示唆**：コピーの結果通知、削除直後の「元に戻す」、期限後の削除一覧を設ける。2秒・6秒は製品の調整値。単一削除の復元通知を汎用Undo/Redo履歴の実装とは呼ばない。

### R12 進行状態

出典：[Apple HIG — Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)。閲読範囲：Best practices。

進捗が分かる場合はそれを表し、不明な場合は不定進行表示を使う。実際の処理と一致しない進捗を表示しない。

**設計への示唆**：読込や保存が完了する前に成功表示を出さない。小規模なローカル保存に架空の割合表示を追加しない。

### R13 文言

出典：[Apple HIG — Writing](https://developer.apple.com/design/human-interface-guidelines/writing)。閲読範囲：tone、Best practices、空状態・エラー・入力欄。

操作結果が分かる短い表現を使い、空画面では次の行動を示す。エラーは問題の近くで、利用者を責めずに回復方法を伝える。入力欄のラベルとhintを使い分ける。

**設計への示唆**：「保存」「下書きを破棄」「完全に削除」を区別する。ブランドの文章は空状態や製品情報に限定し、失敗時の説明を曖昧にしない。

## 外観とアクセシビリティ

### R14 文字

出典：[Apple HIG — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)。閲読範囲：Conveying hierarchy、built-in text styles、Supporting Dynamic Type。

システムの文字スタイルで階層と拡大を維持する。重要なアイコンも拡大に追従させ、狭い横並びは大きな文字で組み替える。読める内容を残し、切り詰めを抑える。

**設計への示唆**：タイトル、本文、補足を意味で選ぶ。固定ptのアイコンや最大2行がすべての文字サイズに適切とは断定しない。

### R15 色と素材

出典：[Apple HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)。閲読範囲：一般的な色の選択、Liquid Glass、standard materials、iOS/iPadOS。

色の意味を一貫させ、light/darkで判読できるようにする。Liquid Glassは内容の上にある操作・ナビゲーションの層として使い、本文への過剰な適用を避ける。

**設計への示唆**：文字の一覧面と浮く操作を分ける。クリーム色・錆色はブランド仮説。ガラスの背景合成を含め、実画面でコントラストを確認する。

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

**設計への示唆**：新規作成を全タブ共通のaccessoryにせず、一覧・検索の文脈で領域を確保する。

### R19 SwiftUIでの実装

出典：[Apple WWDC25 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)。閲読範囲：公式transcriptのTab views、Toolbars、Search、Liquid Glass。

標準コンテナ、toolbar、検索role、検索欄の適用位置によって、iOS 26の外観と振る舞いを構成する方法を説明している。

**適用限界**：transcriptはnibbleの特定コードの動作保証ではない。採用するAPIのavailability、検索終了時の遷移、キーボードとの配置は別に確認する。

## 研究を製品へ適用する条件

操作時間、片手操作、中断からの再開に関する原著と条件は[UI/UXと性能](03-ux-and-performance.md)に記載する。端末、入力方法、参加者、課題が異なる実験は、その条件を確認して適用範囲を定める。

| 判断対象 | 適用する条件 |
| --- | --- |
| 配置・選択肢の数 | 利用場面、対象の識別、到達性、占有面積を比較する |
| pt・秒などの数値 | 役割と制約を説明し、文字・画面幅・入力・表示条件をそろえて評価する |
| 操作時間・効果量 | 原著の測定対象、参加者、端末、試行条件を確認する。製品での期待は仮説として検証する |
| 他製品の画面 | 目に見える構成を比較対象にする。内部の設計意図、利用者評価、APIは別の資料で確認する |
| 参照画像 | 個人情報を含む画像をリポジトリへ転載せず、必要な構成をダミーデータで表す |

SDK、主要OS、利用場面、操作の契約を変える場合は、関連するR番号の出典と適用条件を確認し、設計判断と評価条件を更新する。
