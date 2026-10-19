# テストの設計と選択

テストは、原文を変える、途中作業を失う、確認していない文面や入力先へ作用する、失敗を完了として通知する不具合を検出するために置く。製品の正本は[製品仕様・要件](product-specification.md)、実行と証跡の契約は[検証基盤](architecture/verification.md)と[証跡手順](review-evidence.md)にある。

## 保証の置き場所

| 配置 | 保証する境界 | 実行 |
| --- | --- | --- |
| [WorkspaceRepositoryTests](../app/NibbleTests/WorkspaceRepositoryTests.swift) | 実SQLiteの原文保持、単調なチェックポイント、複数接続の競合、公開と作業の分離、削除・回復、失敗後の再試行、検索のページ上限 | 製品targetの全テスト |
| [WorkspaceSessionTests](../app/NibbleTests/WorkspaceSessionTests.swift) | await直後の保存、保存中の入力、再開時の元の版、取消、コピーの重複防止、コピー後の片付け失敗 | 製品targetの全テスト |
| [NativeDocumentFieldTests](../app/NibbleTests/NativeDocumentFieldTests.swift) | 実際にマウントした入力部品のBinding接続変更、Unicodeと選択、marked rangeを持つ間のSwiftUI更新 | 製品targetの全テスト |
| [ViewTestHost](../app/TestSupport/ViewTestHost.swift) | 実windowとUIHostingControllerを使う共通fixture | 回帰・性能target |
| `scripts/tests/` | CLIの誤判定、証跡の取り違え、静的規約、UI driverの不十分な確認と失敗時の後片付け | Nix共通検査 |
| `validation/VerificationApp*` | 独立した入力先A/B、反映した内容とUTF-8バイト列、共通CLI・撮影の成立 | fixture-test / fixture-smoke |
| `scripts/check_*_ui.py` | 製品の実操作から、保存・検索・確認・OS作用・回復までの接続 | 下表のUI工程 |
| [WorkspaceMeasurements](../app/NibblePerformanceTests/WorkspaceMeasurements.swift) | 5,000件の検索・ページ走査、長文確認の安定した描画、反復時の保持量 | 明示したRelease性能工程 |

通常回帰は製品と検証基盤を対象とする。`verify.py plan`は差分から工程を選び、`--scope regression`は通常回帰全体を選ぶ。性能は`--scope performance`で明示する。時間の閾値を通常回帰へ混ぜない。

## 残す・統合する・削除する基準

削除すると見逃す具体的な不具合を各テストに対応させる。同じ契約を同じ境界で確認する重複は統合し、永続化・モデルへの反映・取消・入力先の資格など異なる境界をまとめて成功扱いしない。モックは失敗や順序を制御するために使い、設定した値の読み戻しを成果の証明にしない。

非同期の順序は継続のゲートで制御し、隠れたTaskや短いsleepで競合を偶然起こさない。製品の操作は直接awaitした直後に結果を確認する。保存・コピー・挿入が完了した後の取消を、その作用が取り消された結果として扱わない。

## 入力・一覧・保存の回帰

保存した原文と作業中の入力は別に検査する。空白、LF/CR/CRLF、NUL、結合文字、絵文字を含む入力をUTF-8で照合する。検索だけをUnicode・大文字小文字・幅へ正規化し、保存本文の正規化を認めない。カードはページ単位で取得し、5,000件でも検索結果の一致、件数、ページ間の重複・欠落を確かめる。

差し替えは明示して有効にしたカードでだけ行う。通常の文章やコードにある `{{ }}` は原文の一部として扱う。有効なひな型では、途中の値が独立して保持され、元の版が変わった場合は古い完成文をコピーしない。完成文を別カードとして残すときは、元のひな型を変更せず、独立した文面として識別できることを確認する。

mountedテストの`setMarkedText`はUIKit境界への状態注入であり、日本語IMEの操作証拠ではない。OSのかな入力、変換候補、訂正、確定、入力先変更は[実操作](ios-verification.md#製品の操作検証)で別に確認する。

## 製品UI工程の責務

公開工程名は検証記録との対応のため維持する。

| 工程 | 実際に確認する一連の結果 |
| --- | --- |
| `library-ui` | 作成→閉じる→作業再開→SQLite保存失敗→同じ入力の再試行→検索→全文確認→コピーの完了通知→外部fixtureでOSのPaste→AのUTF-8完全一致とBの不変 |
| `notice-ui` | 固有名の削除取消→ごみ箱への移動→同じUUIDのUndo→再度削除→ごみ箱から回復。版番号と本文を照合し、実際の完了内容を通知する |
| `controls-ui` | 長い原文の入力・保存・確認・コピー、標準と最大のシステム文字サイズでの折返しと説明全体の到達、管理画面からの帰還 |
| `interface-ui` | 現在の製品の適応表示と操作可能性。固定表示の旧仕様を合格条件にしない |
| `about-ui` / `keyboard-guide-ui` | コピーからPasteへの手順、任意の固定文キーボード、端末内保存とクリップボードの範囲を読み、ごみ箱の管理へ実際に到達 |

`about-ui`のrun名`rive-about`と`rive-keyboard`は既存の証跡契約に合わせた互換名で、Riveを製品で採用・検証した意味を持たない。

UI driverは毎回固有名のダミー入力を使い、対象を識別してから操作する。保存失敗は専用Simulatorの実App Group DBへ、その固有名だけに作用するSQLite ABORT triggerを入れて観測し、例外・中断時にもfinallyで除去する。製品へ試験用の保存失敗入口は設けない。テキストの貼付けで日本語IMEの成立を代用しない。

## 検証範囲と制約

検査の存在は現在のビルドでの合格を意味しない。対象ソース・head・run・媒体hashを[証跡手順](review-evidence.md)で照合する。画像・録画の取得、実際に開いて確認した内容、性能の合否を分けて記録する。既存版より良いと述べるには、同条件の比較値が必要である。

製品の実行評価は専用のiOS 26.5 Simulatorで行う。最低対応OSは26.0で、実機は製品受入に含めない。日本語IME、共有シート、任意のキーボード追加とフルアクセス無しでの利用、入力先変更・OS制約からの回復は自動driverだけでは完了しない。

複数scene、長時間利用、1 MB本文の入力追従、フレーム時間・hitch、電力、ロック時保護、すべての外部アプリのKeyboard受理は、対応する実測や実操作を行うまで未確認とする。Releaseの性能測定の範囲は[性能検証](performance-verification.md)に定める。
