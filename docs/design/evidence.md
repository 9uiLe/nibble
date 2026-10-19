# UIと全体構成の設計根拠

この台帳は、要求、実装から分かる仕組み、対象環境での観測、効果の仮説を区別する。過去の規範や試作の一部成功を、現在の製品全体の受入へ格上げしない。外部APIの制限は[OS境界](../reference/platform.md)、実行結果の照合は[証跡手順](../review-evidence.md)を参照する。

## R01 一連の利用を成果とする要求

[製品仕様](../product-specification.md)は、作成・取込から保存、発見、内容確認、実際の使用と回復までを成立条件にする。ユーザー原文の作業資料の保存例は`artifacts/redesign-request.md`である。保存件数、画面数、既存機能の維持を成果にしない。

役割ごとに使える部品があっても、元の作業へ戻るまでを実行していなければ完成とは判断しない。時間や判断負担の改善は同条件の比較を必要とする。

## R02 原文とOS標準入力の実装境界

sourceは[NativeDocumentField](../../app/Shared/Editing/NativeDocumentField.swift)、[WorkDraft](../../app/Shared/Domain/WorkDraft.swift)、[TextTemplate](../../app/Shared/Domain/TextTemplate.swift)。標準UITextView、marked textの照合、UTF-8での入力比較、明示指定の差し替えとliteralの分離という仕組みを確認できる。差し替え指定は本文から推論せず、既定オフで原文を使う。

これは自然な日本語入力、訂正、確定、原文の保持を目指す実装上の根拠であり、実入力や全Unicode条件の検証済み証拠ではない。OSキーでの入力と訂正、選択、背景化、保存、再開までを対象OSで確認する。

## R03 確定済み文章と作業の分離

sourceは[WorkspaceRepository](../../app/Shared/Persistence/WorkspaceRepository.swift)、[DraftSessionModel](../../app/Shared/Application/DraftSessionModel.swift)、[UseSessionModel](../../app/Shared/Application/UseSessionModel.swift)。作業checkpointと文章の確定を分け、対象のversion、作業のsequenceと同一入力を照合する。

失敗時の保持と競合回復を説明する仕組みである。SQLite transaction内の整合性と、別プロセスの読取やOS外部作用の成功は別に検証する。コピー後の片付け失敗を再コピーへ接続しないことも、実画面で結果と照合する。

## R04 Keyboard内部の標準入力試作

2026-10-19、iOS 26.5専用Simulator、Releaseの独立試作で、Keyboard内部のUITextFieldの状態表示がfirst responderであってもOS標準日本語キーは現れなかった。OSの次のKeyboardへ切り替えると内部フォームは消え、「か」は外部入力欄Aへ入り、Bは空だった。

記録の保存例は`artifacts/redesign-probe/P1-focused-no-system-keys.png`、`P1-switch-replaces-local-field.png`、`ui-024.json`。観測IDは`obs-3bd73b664f5a4282bd6c71aa508754a8`、結果はfail。画像とUIの入力値が、標準入力欄の表示やfocusだけでは能力を証明できないことを示す。

標準入力欄にOS標準IMEを呼ぶ構成を採用しない根拠であり、独自IME一般の不可能性を示さない。今回の本体での標準入力＋固定文Keyboardという担当分離を支えるが、本体側の実入力の合格は別に確認する。

## R05 読取専用と一度の挿入の試作

同日、iOS 26.5専用Simulatorの独立試作では、Full AccessなしでApp Groupの44 UTF-8 bytesの固定文を読み、入力先変更A→B→Aで旧確認を失効させ、新しい確認から一度挿入した。Aは日本語・絵文字・改行を含む期待本文と一致し、Bは空、繰返し操作後も同じ内容だった。

記録の保存例は`artifacts/redesign-probe-2/P2-read-no-full-access.png`、`P2-A-B-A-refused.png`、`P2-once.png`、`P2-exact-results.json`と元のUI記録である。観測IDは`obs-d34c9923ebd249d398876f2fa6eeac27`、結果はpassだが範囲はその試作・入力欄・操作条件に限る。

方式Bを選ぶ根拠の一部になる。製品のSQLite/WAL、最終実装、全ホスト、全入力先変更の成立を証明しない。これらのパスは記録の場所の例であり、最終headの最新の受入証拠を指す固定リンクではない。受入時には対象sourceと条件を持つ製品runを照合する。
