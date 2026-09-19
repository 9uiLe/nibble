# 表示設定の固定

状態：採用。判断日：2026-09-18。

## 目的と対象

nibbleは文字の階層、一覧の密度、操作の位置、説明の動きを製品の設計値で表示する。本体・共有拡張・キーボードは、端末の文字サイズ・太字・コントラスト設定によって表示を組み替えない。アクセシビリティ設定を変えても同じ構成で使えることを、F02・F03・F08、S01〜S07・S09・S10の表示方針とする。

これはOS設定への追従を採用しない製品判断であり、アクセシビリティ上の推奨ではない。文字拡大、高コントラスト配色、動きを減らした説明は提供しない。画面幅と内容に応じた折返し、スクロール、ライト・ダーク外観、利用者が選ぶ操作ボタンの左右位置は維持する。

## 設計値と実装境界

| 対象 | 採用する表示 | 所有者 |
| --- | --- | --- |
| 文字サイズ | Dynamic Typeの`large`。文字スタイルの階層は保持する | 共通の`NibbleInterface` |
| 太字設定 | `legibilityWeight=regular`。見出しに明示したbold/semiboldは保持する | 共通の`NibbleInterface` |
| コントラスト設定 | `accessibilityContrast=normal`。ブランド色はライト・ダークの二組 | 共通の`NibbleInterface`と`NibbleTheme` |
| 一覧の配置 | 内容と操作を横並びにし、タイトル・要約は各2行まで | `LibraryScreen` / `SnippetRowContent` |
| 通知の動き | シート内は160 msのopacity遷移。上部の通知ウィンドウは表示・消去アニメーションなし | シート内は`Library.Notice`のAnimationScope、一覧・検索の専用ウィンドウは[通知の設計](0004-result-notices.md) |
| 説明イラスト | `motionAllowed=true`、6.2秒の自動ループ | `AboutIllustration` |
| 表示範囲・画面寿命 | 不可視・バックグラウンドではフレーム停止。同じSessionで復帰 | ホストとRiveCanvas |

SwiftUIでは`dynamicTypeSize`と`legibilityWeight`を設定する。ネイティブ部品にはUIKitの公開`traitOverrides`で同じ値を渡す。本体は自分のWindowScene、共有拡張とキーボードは自分のViewControllerとUIHostingControllerを境界とする。共有元のアプリや端末の設定を書き換えない。個々のViewに端末設定を監視する処理を分散させない。

RMLの`motionAllowed=false`と`Overview`は、アセットの明示的な静止表示契約として保持する。nibbleはこの入力をOS設定へ接続しない。再利用するRivePresentationは製品の固定方針を持たず、別のホストは自分の表示方針を接続できる。

## OSが所有する表示と操作

画面全体のズーム・色フィルタ・反転、VoiceOverの操作方式、システムキーボード、標準部品の透明素材・ボタン形状・色の濃淡補正・遷移はiOSの制御を受ける。これらを一括して無効化する公開APIは提供されていないため、内部APIやOS設定の書換えを使わない。これらを含めた画面全体の完全一致は保証しない。

操作対象の読み上げラベル、見出し、選択状態、通知のannouncementは保持する。これらは表示の拡大や配置変更を行う仕組みではなく、標準部品の意味と操作対象を伝える情報である。

## 選択肢と判断

| 選択肢 | 利点と負担 | 採否 |
| --- | --- | --- |
| OS設定へ追従 | 利用者の視認・動作条件へ合わせられる。配置と演出に複数の状態を持つ | 採用しない |
| 製品の表示値を入口で固定 | 各画面で同じ文字・色・配置を使い、条件分岐を限定できる。拡大・動作軽減は提供できない | 採用 |
| 標準部品をすべて独自描画へ置き換える | 表示を独自に制御できる範囲が広がる。入力・ナビゲーション・保守の負担が増え、OS全体の設定は抑止できない | 採用しない |

## 検証と見直し

- UIKitの親階層の文字サイズ・太字・コントラストを変えても、固定境界内の文字・入力・操作の描画が変わらないことをテストする。
- 一覧、編集シート、設定、製品情報を、標準・最大・最小の文字設定とコントラスト強調で操作し、要素位置と画像を比較する。
- Reduce Motionを有効にして起動した場合と、表示中に切り替えた場合の両方で、自動ループが続くことを録画で確認する。
- 比較ゲート単体は外観・文字サイズの環境更新を遮断しないことを検査する。アプリの固定方針は入口に適用し、部品単体の比較契約とは分ける。
- ライト・ダーク、入力、保存、コピー、フィルター、画面復帰を回帰確認する。設定操作の後は専用Simulatorの設定を復元する。
- 標準部品の挙動はOS更新時に再評価する。支援機能への追従を提供する際は、この判断と製品側の検査条件を一緒に変更する。

APIの確認対象はXcode 26.5のiOS 26.5 SDK。`dynamicTypeSize`、`legibilityWeight`、`UITraitOverrides`の公開宣言とビルドで適合性を確認する。SwiftUIの読取専用環境値を内部APIで書き換えない。

公式APIの参照：[UIWindowScene.traitOverrides](https://developer.apple.com/documentation/uikit/uiwindowscene/traitoverrides-1klo1)、[Traitsと階層](https://developer.apple.com/documentation/uikit/traits-and-the-trait-environment)。確認日：2026-09-18。
