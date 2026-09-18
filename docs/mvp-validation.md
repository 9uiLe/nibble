# 製品の検証結果

本書は、本体`Nibble`と共有拡張`NibbleShare`の評価記録を案内する。設計の正本は[製品設計](decisions/0002-mvp-app.md)、再現する操作と期待結果は[MVP手順](mvp.md)とする。各記録は対象ソース・環境・確認方法を持ち、設計上の契約と実施した検証を区別する。

## 製品構造・応答・容量

対象ソースは`c84280c3c26b6cf0a8cbf75dd46e8d3ee78e40e2`。保存資源、OS作用、画面の責務、Release構成を[製品基盤の検証](product-architecture-validation.md)で評価した。

| 確認項目 | 結果と範囲 |
| --- | --- |
| Release製品テスト | iOS 26.5 Simulatorで67件成功、失敗・skipなし |
| 本体UI | 作成・下書き再開・保存・編集・原文コピー、検索・フィルター、設定・About、削除・Undo・復元 |
| 行の操作 | 左右のフルスワイプ、同じUUIDと本文での復元 |
| 共有拡張 | Safariからテキストを保存し共有元へ復帰。本体のコピーでUTF-8完全一致 |
| 性能 | 同一Simulatorの保存層・編集モデルを比較。描画と実機性能は含めない |
| 容量 | 同じ条件のunsigned Release archiveで、本体・共有拡張を含むファイル合計を比較 |
| 共通検査 | Nixの7検査が成功。iOS tooling 101件、共通UI設計ツール35件を含む |
| 証跡 | Releaseテストと3種類のUI runを対象コミットと照合。画像と抽出フレームを観察。公開先への添付・閲覧確認は未実施 |

本体`nibble.9uiLe.com`、共有拡張`nibble.9uiLe.com.share`、App Group `group.nibble.9uiLe.com`を使う。実行はXcode 26.5・Swift 6.3.2・iPhone 17 Pro Simulator・iOS 26.5（23F77）。性能・容量の数値、比較元、失敗run、画像の確認時刻は詳細記録に集約する。

## 契約ごとの詳細記録

表の文書は、それぞれの対象コミットに対する評価である。特定の画面や依存を確認するときは、文書の冒頭で対象ソース・版・端末を確認する。

| 契約・対象 | 参照先 |
| --- | --- |
| 文字・太字・独自配色・演出の固定、OS部品に残る表示差 | [表示設定](interface-validation.md) |
| 説明文、Riveの接続、自動ループ、画面寿命、配色、配布 | [Rive](rive-validation.md) |
| 取得待ち・空表示・失敗回復、行の識別、削除対象の提示 | [UI操作と回復](ui-ux-validation.md) |
| 標準タブ、上部フィルター、共通背景 | [標準ナビゲーション](native-navigation-validation.md) |
| 一覧区分、左右位置、再起動後の設定保持 | [一覧と設定](library-settings-validation.md) |
| すべて・ピン留め・下書きの選択 | [一覧フィルター](library-filters-validation.md) |
| 見出し、ボタン寸法、背景 | [ナビゲーションバーとリスト](navigation-header-validation.md) |
| 検索中の見出し、検索欄、キーボード | [検索画面](search-layout-validation.md) |
| 要約読込、下書き照合、編集終了、入力の比較 | [一覧と編集](library-validation.md) |
| 操作APIの完了、所有者、通知期限 | [非同期API](async-policy-validation.md) |
| 表示値の比較、入力と環境の更新 | [比較View](app-macros-validation.md) |
| Tasking・ScopedAnimationの採用構成 | [タスクとアニメーション](library-policy-validation.md) |
| SPM解決、マクロ承認、採用版の互換性 | [Swift Package構成](spm-validation.md) |
| 署名・送信・内部配信と実機確認 | [TestFlight](testflight-validation.md) |
| 初期構成のビルド、日本語入力、URL、共有、検索測定 | [初期構成の検証](mvp-initial-validation.md) |

文字拡大や動作軽減へ追従する構成の観測を、固定表示方針の評価として扱わない。表示比較View単体の環境テスト、OS設定を変えた画面操作、利用者の操作確認も別々の結果として読む。

## 証跡の参照方法

1回の検証実行をrunと呼ぶ。`artifacts/ios/<run>/manifest.json`が、入力ファイルのhash、ツール、端末、コマンド、終了コード、媒体を記録する。未コミットのソースを実行した場合も、コミット後のファイル照合で対応を確認する。

画像の目視、動画の抽出フレーム、全編再生、アップロード、ブラウザーでの閲覧は独立した確認である。`review.json`に実際の方法と範囲を記入し、[証跡検査](review-evidence.md)で形式と整合性を確認する。

生ログ・画像・動画はGit管理対象外のため、新しいcheckoutに含まれない。公開済みの記録は詳細文書に示すPR添付を使う。未公開の記録はローカル媒体を必要とする。録画に含まれるdriverの待機時間をアプリの応答時間へ換算しない。

## 検証範囲の制約

- 最低対応OSは26.0、実行評価は26.5 Simulator。最低OSへの適合と、実行したOSでの結果は区別する。
- Simulatorの測定から実機の描画時間・電力・触覚・ロック時保護を推定しない。unsigned archiveは署名・配信・インストール成功を示さない。
- 1 MB入力のsetterと保存可能判定の測定は、キーボード入力や画面描画の測定を含まない。
- VoiceOverの実操作、横向き、長時間利用、表示設定の全組み合わせは、上記`c84280c3c26b6cf0a8cbf75dd46e8d3ee78e40e2`の評価範囲に含めていない。設定別の観測は各詳細記録の対象ソースに限る。
- 共有の操作hostはSafari。サードパーティアプリが提供する全形式を網羅しない。
- URL呼び出しの観測と、ホーム画面・コントロールセンターへの配置操作は別の確認である。
- 別ソースのテスト件数や画面結果を合成して、同じ構成で全条件を確認済みとは扱わない。同期・独自バックアップなど提供範囲外の機能は受け入れ項目に含めない。
