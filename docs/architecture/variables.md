# 変数の編集と利用

変数は保存済み本文に含まれる `{{宛名}}` のような印である。利用者は編集時に印の位置と名前を決め、コピーまたはキーボード入力の直前に値を指定する。保存する本文と、値を当てはめた出力は別のデータとして扱う。名前・値・取消の製品契約は[製品仕様](../product-specification.md#無料機能とnibble-pro)が定める。

名前の有効条件は`VariableName.issue(_:)`が一つの結果型で返し、新規作成シートはその結果を利用者向けの理由へ変換する。入力文字列は有効な`VariableName`に変換してから本文へ挿入する。既存名との重複だけは編集中の本文に依存するためシートで判定する。印の解析、新規作成、本文への挿入は同じDomainの有効条件を使う。

## 編集から利用まで

1. 本文のカーソル位置または選択範囲を決め、「変数を追加」で既存名の追加行か新規名の作成を選ぶ。両方法とも同じ挿入規則を使い、選択中の文字は印に置き換わる。本文に位置がない場合は末尾に加え、追加後のカーソルは印の直後へ置く。追加シート右上の「閉じる」では本文を変えず編集画面に戻る。
2. 保存時は印を含む原文を保持する。同じ名前の印が複数あっても、利用時の入力欄は一つにする。
3. コピーまたはキーボード入力を選ぶと、対象の項目名、印と入力の関係を示す一つの説明、名前ごとの入力欄、入力前の原文を示す。値が全て揃うと原文表示を完成文に切り替える。省いた文章は「全文を確認」で開ける。
4. 通常の確定操作は文章の直後に置き、文章とともにスクロールさせる。本体シートで入力欄にフォーカスがある間はキーボード上のセーフエリアに背景と同色の操作面を確保し、スクロール領域と重ねない。未入力時は利用不可を輪郭と文字で示し、値が揃ったら強調する。閉じる操作を含む確定前の取消ではコピー、挿入、使用記録を行わない。確定後の出力だけに値を適用し、保存済み本文は変えない。

本体は[VariableFillView](../../app/Shared/Interface/VariableFillView.swift)のTextFieldとOSの文字入力を使う。Keyboardは[KeyboardVariableFillView](../../app/NibbleKeyboard/KeyboardVariableFillView.swift)を入力面内に表示し、ボタンで選ぶ値欄と局所キーから[KeyboardValueBuffer](../../app/Shared/Domain/KeyboardValueBuffer.swift)を編集する。外部アプリのfirst responderを維持するため、Keyboard内に別の`UITextInput`を作らない。局所のreading、候補、選択と編集操作は[S11](../design/screens.md#s11-キーボード内の変数値入力)、変換と挿入資格の責務は[Keyboard設計](keyboard.md)に定める。

両入口とも入力欄・文章・通常の確定操作は一つのスクロール領域に置く。本体シートで入力中だけ確定操作をセーフエリアへ移す。本文が160文字または4行の表示範囲を超える場合は短く示し、全文への入口を付ける。項目名と原文を先に示すことで、利用者が差し替え先を確かめてから値を確定できる。

折りたたんだ完成文は印の展開結果から表示範囲と超過の有無だけを求め、長い本文全体を入力のたびに生成しない。全文を開いたときと確定時は同じ印と値から全文を生成する。表示の切り詰めは原文・入力値・確定する文章を変えない。

## 責務と状態

| 所有者 | 正本と役割 |
| --- | --- |
| [VariableNameとSnippetVariables](../../app/Shared/Domain/SnippetVariables.swift) | 入力された名前の検証・正規化、原文からの初出順の名前抽出、型付きの名前に対応する値の全出現箇所への展開。展開結果を保存データへ書き戻さない |
| [EditorBodyField](../../app/Shared/Editing/EditorBodyField.swift) と [MarkdownSourceInput](../../app/Shared/Editing/Markdown/MarkdownSourceInput.swift) | `UITextView` のUTF-16選択範囲をシート表示前に保持し、挿入後のカーソルを反映する。シート取消では本文を変えない |
| [EditorModel](../../app/Shared/Application/EditorModel.swift) | 下書きの編集状態を確認し、選択範囲を印で置換する。位置が未設定なら末尾を使い、無効な位置では本文を変更しない |
| [LibraryModel](../../app/Shared/Application/LibraryModel.swift) と [KeyboardModel](../../app/Shared/Application/KeyboardModel.swift) | 保存済み原文を読み、利用対象と権限を固定し、確定時に原文・対象・入力先を再確認して外部作用を実行する |
| `VariableFillView` | 本体の値入力、原文または完成文、全文確認、確定中と利用不可の表示。コピーと記録の成否はモデルに委ねる |
| `KeyboardVariableFillView`と`KeyboardValueBuffer` | 名前ごとの局所値、UTF-16選択範囲、未確定reading、候補の選択、原文確定と取消。入力先の資格を所有せず、最終確認時だけ値辞書を`KeyboardModel`へ渡す |

変数入力は、対象を開いた初期状態、値の編集中、全値が揃った状態、確定中、利用不可の状態を持つ。読み込みと処理失敗は各入口のモデルが扱い、表示に仮の完成文を作らない。Keyboardでは入力先の文書が変わった場合に挿入を拒否する。利用資格の判定は[収益と機能アクセス](monetization.md)、入力先の寿命は[Keyboard設計](keyboard.md)が所有する。

## 検証

[EditorMarkdownTests](../../app/NibbleTests/EditorMarkdownTests.swift)はUTF-16選択範囲、絵文字、末尾への追加と無効な位置を検査する。[KeyboardValueBufferTests](../../app/NibbleTests/KeyboardValueBufferTests.swift)は局所値の原文、Character境界、選択方向、readingの確定と取消を検査する。[SnippetStoreTests](../../app/NibbleTests/SnippetStoreTests.swift)は名前と原文を保持した展開、[OperationTests](../../app/NibbleTests/OperationTests.swift)はコピーの確定境界、[KeyboardTests](../../app/NibbleTests/KeyboardTests.swift)は入力先の変更を検査する。シートと実際のカーソルの往復、原文と完成文、取消と利用不可の表示は[iOS操作手順](../ios-verification.md#変数の編集と利用を確認する)でiOS 26.5 Simulator上で確認する。
