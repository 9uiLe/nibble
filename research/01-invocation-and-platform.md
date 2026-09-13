# 呼び出し導線と iOS の境界

調査日: **2026-09-13**。対象: **iOS 26.0 以上**。これは一次資料から設計の選択肢と検証項目を整理した調査であり、各導線の採用決定や、実機での動作保証ではない。

## 先に押さえること

**「呼び出せる」「内容を受け取れる」「相手アプリの入力欄に挿入できる」は別の能力である。** iOS は第三者アプリを sandbox に隔離し、他アプリの情報へのアクセスには OS が明示的に提供するサービスを要求する。nibble の本体から、任意のアプリの画面・選択範囲・入力欄を読み書きできる設計は前提にできない。[I18]

入力中の別アプリへ公開 API で文字列を挿入する有力な候補は Custom Keyboard の `textDocumentProxy.insertText(_:)` だが、利用者による有効化と切り替えが必要で、secure text field、電話番号用の一部入力欄、第三者キーボードを拒否するアプリでは使えない。したがって「全シーンで直接挿入」を単一の導線で保証せず、呼び出し・取り込み・挿入・復帰を場面ごとに評価する必要がある。[I07] [I08] [I10]

**見落としやすい現行仕様:** Full Access を許可しないキーボードでも、本体アプリの shared group container は**読み取り専用で利用可能**と現行 UIKit 文書に明記されている。共有領域への書き込みとネットワークには Full Access が必要である。「キーボードで既存スニペットを読むだけでも Full Access 必須」と決めつけない。iOS 26.0 で実際に採用する保存形式・更新方法・保護設定を使った検証は別途必要。[I09]

## 導線の比較

表の「読取」は取得可能な内容、「挿入」は**他アプリの入力欄に入れる能力**を示す。設定負担は資料を踏まえた相対的な設計評価で、操作数・所要時間の測定値ではない。「候補」は未実装・未検証を表す。

| 導線 | 呼び出し | 読取 | 挿入 | 必要な操作と復帰 | 主な制約 | 設定負担 |
| --- | --- | --- | --- | --- | --- | --- |
| 本体アプリ + コピー | アプリアイコンやアプリ内の導線 | 自分のスニペット。外部の内容は明示的ペーストで受け取る | pasteboard へコピー後、相手側でペースト | 本体を開く → 選ぶ → コピー → 作業先へ戻る → ペースト | 直接挿入・作業先の入力フォーカス復元を保証しない。[I14] [I15] [I18] | 低。常に利用できる基礎候補 |
| App Intents / App Shortcuts / Siri | Siri、Shortcuts、Spotlight 等からアプリの action を実行 | 自分のデータと、intent の入力として渡された値 | 他アプリの入力欄への汎用の直接挿入権限は得ない。文字列を次の Shortcuts action に渡す構成は候補 | 音声または action を選択。足りない引数・認証・本体表示で追加操作 | システムが実行場所を決める。初回未起動・ロック・言語・無効な ID を扱う。[I01] [I02] [I03] [I04] [I21] | App Shortcuts 自体は利用者によるショートカット作成が不要。個人用の複数段 workflow は別途設定 |
| Spotlight | 検索してアプリの action や公開した内容へ到達 | nibble がシステムに公開した内容・action | 検索結果は他アプリへの挿入機構ではない | 検索 → 結果を選ぶ → action または本体 → 必要に応じ作業先へ復帰 | 本文・タイトルをどこまで公開するか、削除・更新をどう反映するかの設計が必要。検索への露出と日本語での発見性は未検証。[I01] [I02] [I18] | 利用者負担は比較的低い。開発側は公開データの管理が必要 |
| Controls / Action Button | Control Center、Lock Screen、対応機器の Action Button | 自分の action / 設定 / 状態 | 汎用の直接挿入はできない。ライブラリや作成画面を開く候補 | 利用者が control を配置・割り当て → タップ等 → 必要に応じ認証 | OS 定型の button / toggle。自由な一覧編集画面ではない。背景でのコピー成立は別途実機検証。[I05] [I04] [I18] [I22] | 中。初回配置と、Action Button を他用途に使う場合の競合 |
| Widget | Home Screen / Lock Screen 等の配置済み widget | timeline に載せる自分のデータ | 汎用の直接挿入はできない | 項目リンクで本体へ、または button / toggle で intent を実行 | 自由な TextField やアプリと同じデータ binding 更新は前提にしない。ロック中の button / toggle は認証後。データ更新を確定してから intent を返す。[I06] | 中。配置・サイズ選択が必要 |
| Share Extension | host の共有 UI で nibble を選択 | host が提供した text / URL / attachment 等 | 受け取り・保存に向く。相手入力欄への任意挿入は保証されない | 内容を選ぶ / 共有 → nibble → 確認・保存 → host に復帰 | host が提供するデータ型・内容に依存。選択本文とページ URL が同じとは限らない。Share の適合性は prototype と配布方針で確認。[I11] [I13] | 中。共有先の表示・並び順に依存 |
| Action Extension | host の共有 UI の action 領域 | iOS では host が明示的に渡した内容のみ | 編集済み item を host へ返す API はあるが、任意の入力欄への差し込みを保証しない | 共有 → action → 操作 → 完了 → host に復帰 | host の対応次第。macOS の選択内容編集と iOS の説明を混同しない。[I12] [I13] | 中。対応 host とデータ型の見極めが必要 |
| Custom Keyboard | 入力中にキーボードを切り替える | 自分のスニペット、proxy が返す選択文字列・周辺文脈 | 対応入力欄の現在位置へ文字列を挿入・後方削除できる | 設定で有効化 → 入力欄を選ぶ → 切り替え → スニペット選択 → 元のキーボードへ | secure / phonePad / namePhonePad / host の拒否。別プロセス・メモリ制限。Full Access なしの共有領域は読取専用。Settings 以外の他アプリ起動を審査規約が禁止。[I07] [I08] [I09] [I10] [I20] | 高。キーボード設定・切り替え・信頼の説明が必要 |
| Universal Links / custom URL scheme | 他アプリやリンクから指定画面へ | URL に明示的に含められた ID や引数 | リンクを開くだけで呼び出し元の入力欄は操作できない | リンクを選ぶ → nibble 内の該当画面 → 利用者が復帰 | Universal Links は関連ドメインの運用が必要。custom scheme は他アプリと衝突し得る。入力検証と危険な action の制限が必要。[I16] [I17] [I18] | 利用者は低、Universal Links の開発・運用側は中 |

## 事実として確認できた設計上の境界

### App Intents は共通の action 表現であり、万能の他アプリ操作 API ではない

App Intents はアプリの action とデータを構造化して、Siri、Spotlight、Shortcuts、Widget、Controls、Action Button 等へ公開する仕組みである。本体の「検索」「特定スニペットを開く」「文字列から新規作成」などを、入口ごとに重複実装しないための候補になる。ただし後半は nibble への**設計提案**で、採用決定ではない。[I01]

App Shortcuts はアプリのインストール後に利用者のショートカット作成なしで利用できると WWDC22 で説明されている。そこで紹介される「本体の初回起動前にも action が実行され得る」という条件は、データ未初期化時の扱いを検討する根拠になる。**2022 年当時の Spotlight の掲載条件・Siri の UI 制約を、iOS 26 の現行仕様として転用しない。** 現行の発見性・言語・実行条件は実機で確認する。[I02]

`AppIntent.supportedModes` は DocC の availability metadata で **iOS 26.0 導入**を確認した。前景・背景での実行希望を表すが、実際の実行先はコードを配置した bundle、intent の型、システム状態にも依存する。App Intents extension は背景実行であり、「画面を開く action」を extension に置くだけでは成立しない。特定の新 API を採用する際は、その型・各 member の availability を個別に確認する。[I03] [I21]

`authenticationPolicy` の既定値は `alwaysAllowed` で、端末がロック中でも認証なしの実行を許す。**推奨:** 本文表示、共有・コピー、変更・削除はそれぞれ情報露出と誤操作の影響を評価し、認証・確認・Undo の方針を決める。Widget のロック時制約だけを見て、Siri や他の intent 入口も自動的に保護されると思わない。[I04] [I06]

### Controls と Widget は短い action と入口に適する

Controls は widget extension で提供する定型の button / toggle で、Control Center・Lock Screen・Action Button から action または本体の特定画面を開ける。`OpenIntent` による起動には intent の target membership を本体と widget extension の両方に置く必要があると公式手順に記載されている。`ControlWidget` 自体は metadata で iOS 18.0 導入を確認した。[I05] [I22]

Widget は別プロセスで view の表現を保存し、timeline を通じて表示する。画面を表示する瞬間に通常アプリのようにコード実行や binding 更新をする仕組みではない。action の完了に必要な保存を `perform()` の返却前に終わらせ、更新後の値を timeline が読めるようにする必要がある。[I06]

**推奨:** 「新規作成を開く」「よく使う項目を開く」など、短く説明できる入口を先に比較する。Control や Widget からのクリップボード操作は、背景実行・データ保護・完了フィードバックを含めた実機検証が必要であり、「タップだけで常にコピーできる」とはまだ約束しない。

### Share / Action Extension は host が渡す内容に限定される

Share / Action の詳細な公式ガイドは **Documentation Archive、2017-10-19 更新**である。Share は共有 UI から渡された内容を扱い、Action は表示・変換を行う。iOS の Action が得るのは host が明示的に供給した内容であり、選択範囲の自動取得は保証されない。[I11] [I12]

現行 `NSExtensionContext` も、host が送るデータは `inputItems` にあると説明している。現行 `completeRequest(returningItems:completionHandler:)` は結果 item を host に返し、最終的に extension の view controller を閉じる。この照合から維持できるのは**受け渡しの契約**であり、古いガイドの UI 外観やコード断片のまま現行 Xcode で動くとはしていない。[I13]

**推奨:** 「選択内容を nibble に保存」について Share と Action を小さく比較し、Notes、Safari、メッセージ系の代表的な host から実際に届く型と内容を観察して一方を選ぶ。対応していない型、複数 item、長文、キャンセルを扱う。両方を同時採用して共有 UI に似た項目を増やすことは初期状態にしない。

### キーボードには読取専用の案と編集可能な案で大きな差がある

現行 UIKit ガイドは、独立プロセスのキーボードが `UITextDocumentProxy` 経由で選択文字列・前後の文脈を読み、文字列挿入・後方削除・挿入位置調整を行えることを説明している。これは入力対象の view 自体や別アプリの全データへのアクセスではない。得られる文脈を文書全文として扱わない。[I07] [I10]

`RequestsOpenAccess = false`、または利用者が Full Access を拒否した場合でも shared group container を読める一方、共有領域への書き込みとネットワークは許可されない。したがって、**本体で作成・編集・削除し、キーボードは検索・選択・挿入を担当する案**を、Full Access を要求しない最小候補として検証できる。キーボードから共有データを変更する案は、権限要求と保存競合を追加する。[I09]

ただし、App Review Guidelines 4.4.1 は、キーボードに入力機能、次のキーボードへの切り替え、ネットワークや Full Access がなくても機能することを要求し、**Settings 以外の他アプリを起動することを禁止**している。キーボードから URL で本体の編集画面へ飛ぶ案を API の可否だけで採用しない。また、スニペット選択・挿入だけの UI が要求する「keyboard input functionality」を十分に満たすかは、この調査では確定していない。[I20]

キーボードのメモリ上限は端末ごとに異なり、超えるとプロセスが終了する。非表示になっても終了するとは限らない。固定の「全端末で何 MB」という値を設計基準として引用せず、対象実機で測る。[I07]

**未確認:** read-only 共有領域を、選定する DB がロック・journal・migration の書き込みなしに開けるかは未検証。キーボード用に本体が生成する小さな読み取り用 snapshot も比較対象になる。Full Access を途中で切った場合、アプリ更新直後、本体で編集中、端末のロック・再起動直後の整合性も実験する。

### コピーとペーストを明示的な操作として設計する

`UIPasteControl` は iOS 16.0 以降で、利用者が押すことで本体アプリに pasteboard の内容を取り込むための control である。公式文書は、プログラムによる pasteboard 読取には許可 alert が出る一方、この control の明示的なペーストではその prompt が不要と説明している。これは**nibble の中への取り込み**であり、別アプリに勝手にペーストする機能ではない。[I14]

`UIPasteboard` の一般的なフローは、コピーしたアプリが書き込み、受取側アプリが利用者のペースト操作で読み出すもの。型の有無を知るだけなら `hasStrings` 等を使い、本文を読むことで不要な取得・通知・alert を起こさないことが公式に推奨されている。[I15]

**推奨:** 開くたびに clipboard を自動収集する体験を初期仕様にせず、「ペーストして作成」と「コピー」を分けて明示する。保存済みデータの閲覧・編集は clipboard の許可と独立させる。コピーは成功表示を出し、続く他アプリ側でのペースト操作も含めて所要時間を測る。

### Clipboard の端末間転送と期限を区別する

個別 API を照合した結果、`localOnly` は **`true` でこの端末だけ、`false` で Handoff 経由の他端末での利用を許す**。`UIPasteboard.OptionsKey.localOnly` は「他端末で利用不可にする Boolean」と説明し、`setItemProviders(_:localOnly:expirationDate:)` の引数説明が true / false の意味を明記している。`setItems(_:options:)` は `OptionsKey` で全 pasteboard item の privacy options を指定する。親ページ I15 の「Handoff を除外するには false」という一文はこの個別 API と矛盾しており、設定値の根拠には採用しない。**API の設定方向は照合できたが、Apple による親ページの訂正は確認していない。**[I23] [I25] [I26]

`localOnly` は Handoff / Universal Clipboard による端末間転送の制御であり、同じ端末での他アプリによる正当なペーストや、利用者がその後に共有することまで禁止する仕組みではない。**推奨:** 通常コピーで端末間転送を許すか、機密用の「この端末のみ」操作を設けるかは利用シーンから決め、名称と実際の設定を一致させる。「安全なコピー」のように保護範囲が分からない表現は避ける。[I15] [I23] [I26]

`expirationDate` の公式な契約は「指定日時に pasteboard から item を取り除くようシステムへ指定する」ことである。期限を指定した元データの**pasteboard 上の寿命**を扱う API であり、期限前に他アプリへペースト・保存されたコピーの回収や、その後の情報流通の停止を保証するとは記載されていない。正確な削除時刻の許容誤差、転送先端末での保持期間や切断中の動作についても、確認した個別 API 文書には保証がない。これらを「期限になればどこからも消える」と説明しない。[I24] [I26]

**新しいコピーを消さない配慮:** アプリ独自の timer で後から `UIPasteboard.general` を空にすると、途中で別アプリがコピーした内容を消す危険がある。`changeCount` は内容の追加・変更・削除で増えるが、イベントループ終端まで更新を待って通知がまとめられる場合があり、他アプリによる更新はアプリ再開時にも反映され、端末再起動で 0 に戻る。したがって値の一致は永続的な所有権 token ではなく、「値を確認してから消す」を原子的に実行する compare-and-clear の保証も、この API 文書にはない。書込直後の値を無条件に保存する実装も、更新タイミングの検証が必要である。[I27]

**推奨:** 期限はコピー時に OS の `expirationDate` へ渡す案を先に検証し、後追いの全消去 timer を標準動作にしない。`changeCount` は内容が変わった場合にアプリ独自の消去を中止するための追加の手掛かりとしては使えるが、競合がないことの証明にはしない。確認した文書だけでは、後続コピーによって以前の期限がどう更新されるかまで明記されていないため、次の実機検証が必要である。[I24] [I25] [I27]

- nibble が期限付き A をコピー → 別アプリで B をコピー → A の期限後も **B が残る**こと。B を同じ文字列にした場合も確認する。
- A の期限前 / 後、nibble の背景化・終了・端末ロック・再起動後の pasteboard 状態。期限後のアプリ独自処理が不要かも観察する。
- 自分の別端末で Handoff を有効にし、`localOnly: true` と `false` の転送結果を比較する。オフライン・再接続と、期限前に別アプリへ保存した内容が残ることも確認する。

### Deep link と背景実行を別アプリ操作の抜け道にしない

Universal Links はドメインとアプリの関連付けを検証して指定内容へ到達する仕組みで、未インストール時は Web に fallback する。同じドメインの Safari 内遷移など、常にアプリが開くわけではない条件も公式に記載されている。ドメインを運用する負担と利用シーンを比較する。[I16]

custom URL scheme は登録競合時にどのアプリへ届くかが未定義である。公式文書は URL パラメータの検証と、外部から直接削除や機密アクセスを許さないことを求める。**推奨:** URL は一覧・検索・特定 ID の表示・入力確認画面への遷移を基本候補とし、本文を URL に詰め込んだり、受信だけで破壊的操作を確定したりしない。[I17]

背景実行は OS が提供する API の範囲に限られる。通常の一時的背景処理には時間制限があり、`BGProcessingTask` / `BGAppRefreshTask` の実行時刻はシステムが決める。これらは継続的な clipboard 監視や、任意のタイミングで他アプリ上に nibble を重ねて表示する保証にならない。[I18] [I19]

<a id="availability"></a>

## iOS 26.0 の availability 点検

親 framework の対応 OS から下位 API の対応を推定せず、重要な型・member は以下の**個別 DocC metadata**を確認した。「導入 OS が 26.0 以下」は API 候補を絞る根拠であり、対象 SDK でのコンパイル、extension での利用可否、権限、端末・言語条件、実際の体験を確認したことにはならない。[I03] [I04] [I13] [I14] [I22] [I23] [I24] [I25] [I26] [I27] [I28]

| 個別 API | metadata にある iOS 導入バージョン | 確認資料 |
| --- | --- | --- |
| `AppIntent` / `AppShortcut` / `OpenIntent` | いずれも 16.0 | [AppIntent](https://developer.apple.com/documentation/appintents/appintent)、[AppShortcut](https://developer.apple.com/documentation/appintents/appshortcut)、[OpenIntent](https://developer.apple.com/documentation/appintents/openintent) [I28] |
| `AppIntent.supportedModes` / `authenticationPolicy` | 26.0 / 16.0 | I03 / I04。I21 が例示する全下位 API の対応までは確認していない |
| `ControlWidget` | 18.0 | I22。Action Button の機器条件や全 control initializer の対応とは区別する |
| `UIInputViewController.textDocumentProxy` | 8.0 | [textDocumentProxy](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/textdocumentproxy) [I28] |
| `UITextDocumentProxy.selectedText` / `UIInputViewController.hasFullAccess` | いずれも 11.0 | [selectedText](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/selectedtext)、[hasFullAccess](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/hasfullaccess) [I28] |
| `UIKeyInput.insertText(_:)` / `deleteBackward()` | iOS 対象の記載はあるが、導入バージョン欄はない | [insertText](https://developer.apple.com/documentation/uikit/uikeyinput/inserttext(_:))、[deleteBackward](https://developer.apple.com/documentation/uikit/uikeyinput/deletebackward()) [I28]。現行 keyboard ガイド I10 は利用例を示すが、導入年を推定しない。26.0 SDK でのコンパイルは未確認 |
| `NSExtensionContext` / `completeRequest(returningItems:completionHandler:)` | いずれも 8.0 | I13。host が結果をどう利用するかは API availability の範囲外 |
| `UIPasteControl` / `UIPasteboard.hasStrings` | 16.0 / 10.0 | I14 / [hasStrings](https://developer.apple.com/documentation/uikit/uipasteboard/hasstrings) [I28] |
| `OptionsKey.localOnly` / `OptionsKey.expirationDate` / `setItems(_:options:)` | いずれも 10.0 | I23 / I24 / I25 |
| `setItemProviders(_:localOnly:expirationDate:)` / `changeCount` | 11.0 / 3.0 | I26 / I27 |
| `BGProcessingTask` / `BGAppRefreshTask` | いずれも 13.0 | [BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)、[BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) [I28] |

Universal Links、Share / Action、Widget の導線は複数の API・設定・host の組み合わせである。ガイド記事の説明を単一の availability と見なしていない。採用する実装の全 member と deployment target 26.0 の整合は prototype で確認する。特に現行資料へ後から追加された API を、その親型が使えるという理由だけで取り込まない。

## 最小の実機検証と判断の順番

以下は**推奨する実験計画であり、すべて未実施**。本体と extension の最低 OS を 26.0 にそろえ、iOS 26.0 と採用 Xcode が対応する最新の正式版 iOS をローカル Mac で検証する。使用 API の availability と extension-safe な利用可否を実際の SDK で確認する。クラウドの静的検査はこれらを代替しない。

| 順番 | 小さな検証 | 観測すること | この結果で決めること |
| --- | --- | --- | --- |
| 1 | 本体でダミーの数件を作成・編集・削除・検索・コピーし、Notes と Safari の入力欄へペースト | cold / warm の起動から利用完了・作業復帰までの時間と操作数、日本語変換、長文、許可拒否後の明示ペースト | 共通の基礎体験と、追加導線の比較基準 |
| 2 | 「一覧を開く」「新規作成」を App Shortcuts と Control で公開 | 未起動・データなし・背景・ロック中・機内モードでの実行先、認証、日本語の発見性、Action Button 非搭載時の代替 | App Intents を共有する範囲、Control の価値、不要な権限を避ける構成 |
| 3 | Share / Action で受け取った item の型とダミー内容を確認して保存 | Notes の選択文字列、Safari の URL / 選択本文、複数 item、非対応型、キャンセル、保存失敗時の復帰 | 取り込み用 extension の選択。相手へ戻せる形式の限界 |
| 4 | Full Access **なし**のキーボードで本体の共有データを読み、短文を挿入 | 有効化の分かりやすさ、切替コスト、secure / phonePad / host 拒否、更新反映、低メモリ時の再起動、日本語入力への復帰 | キーボードを初期版に含めるか。snapshot 等の共有方法。審査要件を満たす最小 UI |
| 5 | 採用候補だけを拡張し、Widget と deep link を追加評価 | Widget の古い値・削除済み ID、外部 URL の不正引数、ロック時の露出、リンク起動と作業復帰 | 初期リリースの導線数と運用範囲 |

操作ごとに「入口が反応するまで」「内容が選べるまで」「挿入 / ペースト完了まで」「元の作業に戻るまで」を分けて測る。cold / warm、同じ実機・OS・ビルド構成・データ量で複数回実行し、初回設定時間は日常操作とは別集計にする。数値の受け入れ基準は最初の計測後に決定し、根拠なしに全導線共通の固定ミリ秒値を置かない。

各 prototype は到達手順・対象コミット・端末・OS を付け、画面録画で実際の呼び出し、許可、入力、復帰を確認する。UI の要所はスクリーンショットも取得する。利用者が許可しない場合、使えない入力欄、本体未起動時にも説明可能な振る舞いがあるかを、成功経路と同じ優先度で見る。

## 未確定事項

- どの入口を初期版に含めるか。全候補の採用は決めていない。
- Share / Action の適合性と実際の host 別データ。アーカイブ記載だけで現行の全 host の動作は保証できない。
- Full Access なしのキーボードで選定 DB を直接読めるか、snapshot が必要か。旧ガイドから permission を推定せず、現行資料と実機で確認する。
- スニペット選択専用キーボードの審査要件への適合、日常の日本語入力を妨げない UI の最小範囲。
- 各 action の背景実行時に clipboard 書込と分かりやすい完了表示を両立できるか。
- Spotlight / Siri に公開するタイトル・本文・引数の範囲、更新・削除の反映、ロック時の情報露出。
- 新しい個別 API、Siri / Apple Intelligence の機能、端末固有機能についての iOS 26.0 availability・言語・機器対応。framework の availability だけでは下位 API や全体験の対応を保証しない。

## 資料台帳

すべて一次資料。閲覧日は 2026-09-13。DocC は公式本文の JSON 表現を取得して本文・metadata を読んだ。公開／更新年が本文にないものは「記載なし」とし、OS 導入バージョンを更新年の代わりにしていない。資料中の code sample をビルドしたわけではない。外部本文全文はこのリポジトリに保存していない。

| ID | 組織・著者 / title / 年・更新 | URL | 実際に読めた範囲と制約 |
| --- | --- | --- | --- |
| I01 | Apple — App Intents。更新日記載なし | <https://developer.apple.com/documentation/appintents> | DocC 本文・metadata。導線の概観。全下位 API の availability を保証しない |
| I02 | Michael Sumner / Apple — Implement App Shortcuts with App Intents。WWDC22、2022 | <https://developer.apple.com/videos/play/wwdc2022/10170/> | 公式 transcript 本文。動画を実時間で視聴していない。2022 年固有の UI / 掲載制約は現行へ転用しない |
| I03 | Apple — AppIntent.supportedModes。更新日記載なし | <https://developer.apple.com/documentation/appintents/appintent/supportedmodes> | DocC 本文・metadata。iOS 26.0 導入を確認。配下の全 API を使った実装は未検証 |
| I04 | Apple — AppIntent.authenticationPolicy。更新日記載なし | <https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy> | DocC 本文・metadata。既定の `alwaysAllowed` と iOS 16.0 導入を確認 |
| I05 | Apple — Creating controls to perform actions across the system。更新日記載なし | <https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system> | DocC 本文。配置、実行、`OpenIntent` の target membership。端末での操作は未確認 |
| I06 | Apple — Adding interactivity to widgets and Live Activities。更新日記載なし | <https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities> | DocC 本文。timeline、ロック、intent 実行と保存。新しいサイズや下位 API の全 availability は未確認 |
| I07 | Apple — Creating a custom keyboard。更新日記載なし | <https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard> | DocC 本文。設定・proxy・メモリ制限。機種別上限の固定値なし |
| I08 | Apple — Configuring a custom keyboard interface。更新日記載なし | <https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface> | DocC 本文。secure、phonePad、host の拒否、切替、サイズ、日本語等の入力期待 |
| I09 | Apple — Configuring open access for a custom keyboard。更新日記載なし | <https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard> | DocC 本文。Full Access なしの shared container 読取、書込制約を明示。DB ごとの動作は範囲外 |
| I10 | Apple — Handling text interactions in custom keyboards。更新日記載なし | <https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards> | DocC 本文。挿入・削除・文脈・marked text。host 別挙動の実測なし |
| I11 | Apple — App Extension Programming Guide: Share。2017-10-19 更新、Documentation Archive | <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html> | HTML 本文。古い social sharing 中心の説明・サンプル。I13 と受け渡し契約を照合 |
| I12 | Apple — App Extension Programming Guide: Action。2017-10-19 更新、Documentation Archive | <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Action.html> | HTML 本文。iOS / macOS 差、host が明示提供する内容、結果返却。古いコードの現行ビルドは未確認 |
| I13 | Apple — NSExtensionContext / completeRequest(returningItems:completionHandler:)。更新日記載なし | <https://developer.apple.com/documentation/foundation/nsextensioncontext> / <https://developer.apple.com/documentation/foundation/nsextensioncontext/completerequest(returningitems:completionhandler:)> | 両 API の DocC 本文・metadata。いずれも iOS 8.0 導入。host の受取後の処理は保証しない |
| I14 | Apple — UIPasteControl。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipastecontrol> | DocC 本文・metadata。iOS 16.0 導入、明示的ペーストと prompt の関係 |
| I15 | Apple — UIPasteboard。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipasteboard> | DocC 本文・metadata。copy / paste と型検査。Handoff の `localOnly` 説明に不整合があるため、本章ではその値の設定方法の根拠に使用しない |
| I16 | Apple — Allowing apps and websites to link to your content。更新日記載なし | <https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content> | DocC 本文。関連ドメイン、未インストール、同一ドメインの Safari 遷移 |
| I17 | Apple — Defining a custom URL scheme for your app。更新日記載なし | <https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app> | DocC 本文。競合、入力検証、直接削除等の危険な action の制限 |
| I18 | Apple — Security of runtime process in iOS, iPadOS, and visionOS。2024-12-19 公開 | <https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web> | HTML 本文。sandbox、entitlement、OS が提供する背景 API の境界 |
| I19 | Apple — Choosing Background Strategies for Your App。更新日記載なし | <https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app> | DocC 本文。限られた背景時間と OS の scheduling。iOS 26 の全背景 API を網羅する記事として扱わない |
| I20 | Apple — App Review Guidelines 4.4 / 4.4.1 Extensions。節の更新日記載なし | <https://developer.apple.com/app-store/review/guidelines/#extensions> | HTML の該当節本文。入力機能、切替、Full Access 不要、他アプリ起動制限。個別アプリの審査結果は保証しない |
| I21 | Apple — Configuring the runtime behavior of your app intents。更新日記載なし | <https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents> | DocC 本文。bundle 配置と実行モード。列挙される新 API の全 availability は未確認 |
| I22 | Apple — ControlWidget。更新日記載なし | <https://developer.apple.com/documentation/swiftui/controlwidget> | DocC 本文・metadata。iOS 18.0 導入と定型表示を確認 |
| I23 | Apple — UIPasteboard.OptionsKey.localOnly。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly> | DocC 本文・metadata。Handoff 経由の他端末利用を制限する Boolean、iOS 10.0 導入 |
| I24 | Apple — UIPasteboard.OptionsKey.expirationDate。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate> | DocC 本文・metadata。指定日時に pasteboard item を取り除く指定、iOS 10.0 導入。下流の保存済みコピー回収・正確な時刻の許容誤差の保証なし |
| I25 | Apple — setItems(_:options:)。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipasteboard/setitems(_:options:)> | DocC 本文・引数説明・metadata。全 item の privacy options、iOS 10.0 導入。後続コピーと旧期限の関係の明文は確認できない |
| I26 | Apple — setItemProviders(_:localOnly:expirationDate:)。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipasteboard/setitemproviders(_:localonly:expirationdate:)> | DocC 本文・引数説明・metadata。`false` は Handoff 利用可、`true` は local device のみと明記。iOS 11.0 導入 |
| I27 | Apple — UIPasteboard.changeCount。更新日記載なし | <https://developer.apple.com/documentation/uikit/uipasteboard/changecount> | DocC 本文・metadata。イベントループ終端の更新、再開時の反映、再起動で 0。iOS 3.0 導入。原子的な確認・削除 API の保証は記載されていない |
| I28 | Apple — availability 点検表にリンクした 11 個の API。更新日記載なし | 上記「iOS 26.0 の availability 点検」の各 API 名から個別 URL にリンク | 個別 DocC の title・platform metadata を確認。本文の挙動の新規根拠には使用せず、導入 OS の照合用。`insertText` / `deleteBackward` は導入バージョン欄がない |

[I01]: <https://developer.apple.com/documentation/appintents>
[I02]: <https://developer.apple.com/videos/play/wwdc2022/10170/>
[I03]: <https://developer.apple.com/documentation/appintents/appintent/supportedmodes>
[I04]: <https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy>
[I05]: <https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system>
[I06]: <https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities>
[I07]: <https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard>
[I08]: <https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface>
[I09]: <https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard>
[I10]: <https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards>
[I11]: <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html>
[I12]: <https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Action.html>
[I13]: <https://developer.apple.com/documentation/foundation/nsextensioncontext>
[I14]: <https://developer.apple.com/documentation/uikit/uipastecontrol>
[I15]: <https://developer.apple.com/documentation/uikit/uipasteboard>
[I16]: <https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content>
[I17]: <https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app>
[I18]: <https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web>
[I19]: <https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app>
[I20]: <https://developer.apple.com/app-store/review/guidelines/#extensions>
[I21]: <https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents>
[I22]: <https://developer.apple.com/documentation/swiftui/controlwidget>
[I23]: <https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly>
[I24]: <https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate>
[I25]: <https://developer.apple.com/documentation/uikit/uipasteboard/setitems(_:options:)>
[I26]: <https://developer.apple.com/documentation/uikit/uipasteboard/setitemproviders(_:localonly:expirationdate:)>
[I27]: <https://developer.apple.com/documentation/uikit/uipasteboard/changecount>
[I28]: #availability
