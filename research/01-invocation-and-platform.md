# 呼び出し・共有・挿入のOS境界

nibbleは本体のコピー、Share Extension、一覧・作成URL、Keyboard Extensionを提供する。採用仕様は[製品設計](../docs/decisions/0002-mvp-app.md)と[Keyboard設計](../docs/decisions/0005-snippet-keyboard.md)に定める。以下は2026-09-13に確認した公開APIの制約で、実機と各ホストでの動作保証ではない。

## 入口ごとの能力

| 入口 | 提供できること | 保証しないこと |
| --- | --- | --- |
| 本体＋コピー | 利用者が選んだ本文をpasteboardへ書く | 他アプリへの自動ペースト、入力focusの復元 [I15][I18] |
| Share Extension | ホストが渡すテキスト・URLを確認して保存 | 任意の選択範囲の取得、相手の入力欄への書込 [I13] |
| custom URL | 検証したURLから一覧・作成を開く | schemeの独占、呼出元の操作。Universal Linksには関連ドメインの運用が必要 [I16][I17] |
| Custom Keyboard | 対応欄へ`textDocumentProxy`で本文を挿入 | secure欄、一部電話番号欄、第三者キーボードを拒否するホスト [I07][I08][I10] |

本体は他アプリの画面・選択範囲・入力欄を自由に読み書きできない。[I18] App Intents・Widget・ControlsのSDKコンパイル成功も汎用挿入権限を与えない。これらは製品に採用していない。

## Keyboardの権限

UIKitの公開契約では、Full Accessなしでも共有group containerを読み取り専用で利用できる。書き込みとネットワークにはFull Accessが必要。[I09] nibbleは本体がDBを初期化し、Keyboardは既存DBを読む。権限を許可した場合だけコピーとピン更新を提供する。WAL・schema・競合の契約は[Keyboard設計](../docs/decisions/0005-snippet-keyboard.md#共有データと読み取りの契約)に従う。

キーボードは別プロセスで、非表示が終了を意味しない。メモリ上限を全端末共通の固定値とは扱わない。[I07] 本体起動を編集導線にしない理由、入力機能・切替・権限なし動作の審査条件は[公開条件](04-security-distribution-and-operations.md)を参照する。全ホスト・実機・再ロック後の成立は未確認。

## Clipboardの保護範囲

`localOnly=true`は他端末へのHandoff転送を禁止する。個別APIの説明がこの真偽を明示する一方、親ページI15には逆の説明があるため、値の根拠には個別APIを使う。[I23][I26] 同一端末のペーストや、利用者が後で共有することは禁止できない。

期限APIはpasteboard上のitemの寿命を扱い、貼付済みの本文を回収しない。[I24] 独自timerでgeneral pasteboardを空にすると後続コピーを消す危険がある。`changeCount`も原子的なcompare-and-clearや永続的な所有権を提供しない。[I27] 製品の通常コピーへ期限による消去を追加する根拠とはしない。

## 確認方法

共有は入力型とキャンセル、本体コピーは原文の全UTF-8、Keyboardは挿入回数と権限拒否を別々に確認する。[MVP手順](../docs/mvp.md)の実操作を使い、SDKコンパイル、AXの表示、実機・ホストでの受理を区別する。実機のHandoff・ロック・ホスト拒否は未確認。

## 出典

[I07]: <https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard>
[I08]: <https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface>
[I09]: <https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard>
[I10]: <https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards>
[I13]: <https://developer.apple.com/documentation/foundation/nsextensioncontext>
[I15]: <https://developer.apple.com/documentation/uikit/uipasteboard>
[I16]: <https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content>
[I17]: <https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app>
[I18]: <https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web>
[I23]: <https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly>
[I24]: <https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate>
[I26]: <https://developer.apple.com/documentation/uikit/uipasteboard/setitemproviders(_:localonly:expirationdate:)>
[I27]: <https://developer.apple.com/documentation/uikit/uipasteboard/changecount>
