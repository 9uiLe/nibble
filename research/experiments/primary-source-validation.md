# 文献・公開API・配布要件の確認結果

nibbleの入力・共有・保護・同期・配布を設計するために、公開仕様と原著で確定できる事項を整理する。資料の確認日は2026-09-13。P01〜P13を問いの識別子とし、引用元をR01〜R26で管理する。

対象領域は[呼び出し導線](../01-invocation-and-platform.md)、[データとアーキテクチャ](../02-data-and-architecture.md)、[UI/UXと性能](../03-ux-and-performance.md)、[保護と配布](../04-security-distribution-and-operations.md)である。製品の実行検証はiOS 26.5、deployment targetは26.0とする。端末上の結果は[ResearchProbeの実行検証](ios-26-5-validation.md)を参照する。

## 根拠の範囲

Apple公式DocCの本文・metadata・参照ノード、App Review Guidelines、配布要件、出版社のPDFと書誌を照合する。文書上のAPI契約、原著の実験条件、個別の製品構成で確かめることを分けて示す。

本文を確認できた事項には、その資料が説明する範囲の根拠がある。書誌だけを確認した原著、実機・実装で評価する条件、製品の宣言・個別審査の判断は、別の状態として記録する。文書確認をiOSの機能試験、提出結果、利用者実験の成功とは扱わない。

取得資料・抽出テキスト・取得記録はGit管理対象外の`artifacts/research/sources/`に保存する。新しいcheckoutには外部資料の全文を含めず、引用リンクと閲読範囲から根拠を追える形にする。

## 問いと確認結果

判定は、確認できた根拠の種類と、実測・取得・宣言・審査が必要な条件を示す。表の01〜04と節番号は上記の領域別文書を指す。

| ID | 対応する疑問 | 判定 | 確認結果と残る条件 |
| --- | --- | --- | --- |
| P01 | 03 §7：KLM原著の実験条件・係数・精度 | 本文未取得 | Card / Moran / Newell、1980年、DOIと出版社側書誌を照合。ACMのPDF URLはアクセス確認画面となり本文を取得できなかった。係数・精度は未検証のまま設計根拠に採用しない。正規の全文を取得して方法・結果・限界を読む。[R01] |
| P02 | 03 §7：Jotaらの直接タッチ遅延原著 | 本文未取得 | Jota / Ng / Dietz / Wigdor、CHI 2013、DOIを出版社の登録書誌で照合。ACM本文は取得不能。マウス研究から直接タッチの閾値を代入しない。正規の全文を取得し、装置・遅延水準・課題・標本・結果を確認する。[R02] |
| P03 | 03 §7：Altmann / Traftonの中断・再開原著との照合 | 原著確認済み | 2007年原著を出版社PDFの全6ページで確認。375人、13,377回の中断、戦術ゲーム、30〜45秒の分類課題による中断。再開後の約10応答にわたる回復という条件を確認した。nibbleの効果量ではない。[R03] |
| P04 | 01 Keyboard / 02 §5：Full AccessなしでApp Groupを読めるか | 実測条件あり | 現行UIKitがread-onlyを明記。書き込み・ネットワークを許すFull Accessとは分かれる。記事にはこの仕様の導入OSがなく、26.5でのentitlement・保護属性・実DBの初期化は実測が必要。[R04] |
| P05 | 01 Keyboard / 04 §3：スニペット挿入だけで最低入力機能を満たすか | 個別審査未実施 | 4.4.1の入力機能・切替・Full Access不要・他アプリ起動禁止を確認。特定のスニペット専用UIを合格とする具体的な基準・承認例は本文にない。実装と実演手順を用意し、提出した構成への審査結果が必要。[R05] |
| P06 | 01 Clipboard：`localOnly`の相反する記述 | 不整合確認 | 親ページは`false`でHandoff除外と記載し、個別APIは`true`で端末限定と明記する不整合が現存する。設定値の根拠は個別APIとする。Handoff転送の成否は別の実機試験。[R06][R07][R08] |
| P07 | 01 Clipboard / V5：期限後に後続コピーBを消さない契約があるか | 実測条件あり | `expirationDate`はpasteboard itemの期限。確認した個別APIには後続書き込み・同一文字列・再起動・転送先での処理の厳密な保証がない。後追い全消去timerを採用する根拠にはならない。A→B→A期限の試験が必要。[R08][R09][R10][R11] |
| P08 | 02 §7：SwiftData/Core Dataの自動同期で競合UXを制御できる範囲 | 実測条件あり | SwiftDataの同期は`NSPersistentCloudKitContainer`による。Core Data公式説明は単一文字列の衝突で片方を残す例と、関係・独立した変更をモデル化する例を示す。公開された同期ガイド・API一覧にはSwiftDataへCloudKitの三者競合を渡して採否を決めるcallbackを確認できなかった。端末間での無損失要件は追加試験が必要。[R12][R13][R14] |
| P09 | 02 §7：`CKSyncEngine`の独自競合制御と責務 | 文書確認済み | `serverRecordChanged`はアプリが処理する。client / server / ancestorを比較し、server recordへmergeして再保存する。同期状態・受信変更・アカウント切替のローカル処理はアプリ責務。実装・運用量と収束は試作で評価する。[R15][R16][R17] |
| P10 | 04 §4：required reason API・理由コードの現行範囲 | 製品宣言未確定 | 現行の5カテゴリと、候補となる用途の理由コードを個別文書まで確認。対象APIを使うbundleごとに実用途を宣言する。製品の最終API・SDK・配布物が確定していないため、製品の宣言そのものは未確定。[R18][R19][R20] |
| P11 | 04 §4：Privacy Manifest / SDKの配置・署名・検証要件 | 文書確認済み | app / framework / Swift Packageの配置、対象SDKと再包装版の要件、バイナリ依存への署名要件を確認。最終archiveの内容・署名・提出結果は別の配布検証。[R21][R22][R23] |
| P12 | 04 §4：App Privacyを「収集なし」と回答できる条件 | 製品回答未確定 | 端末内だけの処理は収集に含めない。Appleサービスを使う場合も開発者が得るデータを区別する。同期・診断・第三者コードを含む製品のデータフローを確定しないと最終回答はできない。[R24] |
| P13 | 04 §6：App Store Connectの提出SDK条件 | 文書確認済み | 確認日の要件は2026-04-28以降Xcode 26以上、iOS 26 SDK以上。iOS実行検証を26.5に限定する方針やdeployment target 26.0とは別の条件。提出直前にも更新を確認する。[R25] |

## 中断・再開研究を使える範囲

Altmann & Trafton, **Timecourse of recovery from task interruption: Data and a model**, *Psychonomic Bulletin & Review* 14(6), 1079–1084 (2007)は、単純な「アプリが開くまでの時間」ではなく、中断終了後に作業の速度が回復する過程を調べている。[R03]

参加者はMichigan State Universityの学部生375人。戦術ゲームを主課題とし、20分のblockを3回実施した。中断課題はレーダー画面上の項目分類で、30〜45秒続く。再開時には主課題を中断前の状態へ戻す。13,377回の中断から、再開後1〜10番目の応答時間を測定した。最初の応答だけでなく約15秒にわたる回復があり、累積の追加時間は4〜5秒と報告する。

この数値を、iPhoneのアプリ切替、短いコピー操作、日本語入力、高齢者や支援技術利用者にそのまま当てはめることはできない。警告中に主課題を見せる条件が、見せない条件より必ず良いという結果でもない。著者は知覚的手掛かりの効果が課題によって異なることを議論している。

nibbleでは「コピー完了」で測定を止めず、元の作業で最初の正しい操作を行うまでを測る根拠として使う。フォーカス・編集中の本文・スクロール位置を保持する案は、主要タスクを正しく再開できるかという仮説として比較する。「状態を保持すれば4〜5秒短縮できる」という製品効果は主張しない。

KLMとJotaの2本は書誌の同定までであり、本文を読んだ原著の本数に加えない。アクセス確認画面や二次資料の要約を原著本文として扱わない。

## Keyboardの権限と審査を分ける

UIKitは、`RequestsOpenAccess`がfalse、または利用者がFull Accessを許可しないときも、containing appの共有containerをread-onlyで使えると説明する。[R04] この契約はSQLiteのsidecar生成、SwiftDataのschema確認、migration、保護されたファイルを読むタイミングの成立までを保証しない。選んだDBをそのまま共有する方式と、containing appが原子的に公開する版付きsnapshotを読む方式は、別々に検証する必要がある。

App Review Guidelines 4.4.1は「Provide keyboard input functionality (e.g. typed characters)」、次のキーボードへの切替、ネットワークやFull Accessなしでの動作を要求する。Settings以外のアプリの起動は禁止する。[R05] キーボードから本体の編集画面を開くURLを設ける案は、この条件に適合する構成として扱えない。

「スニペットを挿入できれば必ず入力機能の要件を満たす」「通常文字キーボードを必ず全て再実装する必要がある」のどちらも、確認した規約には明記されていない。採用UIの具体的な操作、初期データなし・Full Access拒否・キーボード切替の実演を用意し、必要ならApp Reviewへ説明して評価を受ける。問い合わせや提出はこの文献検証では実施していない。

## Clipboardの契約と検証条件

| API | 文書から確定できる範囲 | 文書にない保証 |
| --- | --- | --- |
| `localOnly` | `true`はこの端末だけ、`false`はHandoffで他端末から利用可能。[R07][R08] | 同端末の正当なペーストや、ペースト後の共有の禁止。Handoffの配送成功。 |
| `expirationDate` | 指定した日時にpasteboard itemを取り除くようシステムへ指定する。[R08][R09] | ペースト先・書き出し先のコピーの回収、正確な実行時刻、転送先端末の保持時間。 |
| `setItems(_:options:)` | item群とそのprivacy optionsを指定する。[R10] | 古い期限と後続コピーの関係を網羅した時系列の保証。 |
| `changeCount` | itemの追加・変更・削除で増加する。event loop終端まで更新が遅れる場合、再開時の反映、再起動時の0への復帰がある。[R11] | 永続的な所有権token、値比較と削除を原子的に行うcompare-and-clear。 |

したがって、Aを期限付きでコピーし、別アプリでBをコピーした後、Aの期限を越えてもBが残るかを調べる。BをAと同じ文字列にした条件も必要である。アプリの背景化・終了、端末ロック・再起動、Handoffのオン・オフと切断・再接続は別条件とする。Simulatorで成立したケースを、実機のロックや2端末のHandoffまで検証済みとはしない。

## 同期の制御範囲

SwiftDataの自動同期ガイドは、`NSPersistentCloudKitContainer`を利用すること、unique constraintと必須relationshipがCloudKitと両立しないこと、relationship処理の順序や即時同期を保証しないこと、production schemaを加算的に管理することを説明する。[R12]

Core Dataの2019年の公式セッションは、単一の文字列へ2端末が同時に書き込む場合にlast writer winsで片方を残す例を示し、変更を独立した関連objectとしてモデル化して合成する案を説明する。端末時計だけに依存する問題にも言及する。[R14] これは2019年時点の設計説明であり、26.5での全競合ケースの実測ではない。

現在のSwiftData同期ガイドと`NSPersistentCloudKitContainer`の公開API一覧からは、CloudKitのclient / server / ancestor recordをSwiftDataの同期競合callbackで直接受け取り、利用者に両本文を提示してから適用を決める仕組みを確認できなかった。[R12][R13] Core Dataの履歴読取やview contextへのmergeはローカル更新を取り込むAPIであり、CloudKitのサーバー競合を横取りする権限と同一視しない。[R26] 自動同期に任意の競合UXが組み込まれているという前提は採らない。

`CKSyncEngine`を同期の担当にする場合は、`serverRecordChanged`への対応をアプリが実装する。返されたserver recordへ変更を統合し、変更tagを維持して再保存する。clientやancestorへ統合して再送すると古いtagのため再び競合する。[R15][R16] Appleのサンプルも参考にできるが、採用するschema・削除・履歴保持・アカウント分離・状態の永続化は製品側で定義する。[R17]

本文消失を防ぐには、単一mutable本文の同期だけを採用条件にせず、編集版を別objectとして保持する方式も比較する。どちらの同期方式も、同時編集、削除対編集、長期オフライン、アカウント切替、同期再開の2端末試験を完了するまで無損失を主張しない。

## Privacy Manifestと提出条件の具体化

確認日のrequired reason APIは、File Timestamp、System Boot Time、Disk Space、Active Keyboards、User Defaultsの5カテゴリ。[R19] 製品候補に関係する用途とコードを次に示す。採用前の候補表であり、この表を全てmanifestへコピーしてよいわけではない。

| 候補となる実用途 | カテゴリと理由 | 適用条件 |
| --- | --- | --- |
| 自分のcontainerやApp Group内のファイルmetadata | File Timestamp / `C617.1` | 実際に対象APIを呼ぶ場所と対象ファイルを確認する。 |
| document pickerで利用者がアクセスを許可したファイルmetadata | File Timestamp / `3B52.1` | 明示的に許可されたファイル・directoryを扱う。 |
| アプリ内イベント間の時間測定・timer | System Boot Time / `35F9.1` | raw boot timeやその他の派生情報の外部送信を許す理由ではない。アプリ内イベント間の経過時間には記載された例外がある。 |
| 保存前の空き容量確認 | Disk Space / `E174.1` | 容量に応じて利用者が観察できる動作を変える。任意の分析収集用途へ拡張しない。 |
| 自分のアプリのみで使う設定 | User Defaults / `CA92.1` | 他アプリやsystemが書いた設定を読む用途は含まない。 |
| 同一App Group内の本体・extensionの設定 | User Defaults / `1C8F.1` | Group外への読書きは含まない。 |
| active keyboardsを見て入力UIを変える | Active Keyboards / `54BD.1` | 入力・編集欄を持ち、利用者が観察できるUI差があること。 |
| 主機能としてsystemwide keyboardを提供する | Active Keyboards / `3EC4.1` | キーボードがアプリの主機能という条件。extensionを追加しただけで自動的に該当すると考えない。 |

理由コードの用途・制約は個別のPossible Valuesを確認した。[R20] ソース・依存・最終bundleを調べて、呼ぶAPI→用途→理由→その実行コードを含むmanifestを対応させる。使用する各executable / dynamic libraryのbundleに宣言が必要で、第三者SDKがホストのmanifestへ全面的に依存してよいわけではない。[R18]

iOS appとframeworkはbundleのrootへ`PrivacyInfo.xcprivacy`を含める。Swift Packageはresourceを明示する。指定された第三者SDKの全versionと、それを再包装したSDKにも要件が及び、該当SDKをバイナリ依存として使う場合は署名も必要である。[R21][R22][R23] 最終archiveでの配置・署名・宣言内容の一致を点検し、App Store ConnectのValidate / 提出結果を別に記録する。

App Privacyでは端末上だけで処理するデータは「収集」に含めない。一方、外部へ送る派生情報、開発者がAppleのサービスから取得するデータ、SDKの収集は個別に確認する。[R24] `PrivacyInfo.xcprivacy`を作ったことは、privacy policyやApp Privacyの最終回答が完成したことを意味しない。

## 一次資料台帳

すべて確認日は2026-09-13。日付不明のWeb文書にcopyright年を出版年として付けない。DocC本文はApple公式JSONから読み、リンクは通常の文書URLを示す。

| ID | 資料 | 閲読範囲・制約 |
| --- | --- | --- |
| R01 | Card, S. K., Moran, T. P., Newell, A. (1980), [The keystroke-level model for user performance time with interactive systems](https://doi.org/10.1145/358886.358895), *Communications of the ACM* | [出版社登録書誌](https://api.crossref.org/works/10.1145/358886.358895)の題名・著者・出版日・DOI。本文取得不能。係数・精度は未検証。 |
| R02 | Jota, R., Ng, A., Dietz, P., Wigdor, D. (2013), [How fast is fast enough?: a study of the effects of latency in direct-touch pointing tasks](https://doi.org/10.1145/2470654.2481317), CHI 2013 | [出版社登録書誌](https://api.crossref.org/works/10.1145/2470654.2481317)の題名・著者・出版日・DOI。本文取得不能。装置・人数・効果量は未検証。 |
| R03 | Altmann, E. M., Trafton, J. G. (2007), [Timecourse of recovery from task interruption: Data and a model](https://link.springer.com/article/10.3758/BF03193094), *Psychonomic Bulletin & Review* 14, 1079–1084 | [出版社PDF](https://link.springer.com/content/pdf/10.3758/BF03193094.pdf)の全6ページ。CMU ACT-Rの[著者別登録から案内するPDF](https://act-r.psy.cmu.edu/wordpress/wp-content/uploads/2012/12/830interruptions.pdf)とも書誌を照合。補足データの再解析はしていない。 |
| R04 | Apple, [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) | Overview、Determine whether you need open access、Gain user trust。読取権限の導入OS記載はない。 |
| R05 | Apple, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | 4.4–4.4.1、5.1.1の関連節。個別構成の承認を保証しない。 |
| R06 | Apple, [UIPasteboard](https://developer.apple.com/documentation/uikit/uipasteboard) | Sharing pasteboards between devices。localOnlyに関する個別APIとの不整合を確認。 |
| R07 | Apple, [UIPasteboard.OptionsKey.localOnly](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly) | 概要・Description。 |
| R08 | Apple, [setItemProviders(_:localOnly:expirationDate:)](https://developer.apple.com/documentation/uikit/uipasteboard/setitemproviders(_:localonly:expirationdate:)) | 全引数の説明。特にtrue / falseとexpirationDate。 |
| R09 | Apple, [UIPasteboard.OptionsKey.expirationDate](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate) | 概要・Discussion。 |
| R10 | Apple, [setItems(_:options:)](https://developer.apple.com/documentation/uikit/uipasteboard/setitems(_:options:)) | 概要・引数説明。 |
| R11 | Apple, [UIPasteboard.changeCount](https://developer.apple.com/documentation/uikit/uipasteboard/changecount) | Discussion全体。event loop、再開、再起動。 |
| R12 | Apple, [Syncing model data across a person’s devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) | 全節。同期担当、schema、capability、`.none`、初期化。 |
| R13 | Apple, [NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer) | 概要・公開API一覧。公開APIが将来増える可能性はある。 |
| R14 | Nick Gillett / Apple, [Using Core Data With CloudKit](https://developer.apple.com/videos/play/wwdc2019/202/), WWDC19 | transcriptの26:20頃〜30:54：競合、last writer wins、関連object、causal tree。2019年の説明で、26.5の挙動全体の保証ではない。 |
| R15 | Apple, [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) | Overview、send/fetch、scheduling、Error Handling、Accounts。 |
| R16 | Apple, [CKError.Code.serverRecordChanged](https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged) | Discussion全体。3種類のrecordと再保存。 |
| R17 | Apple, [CloudKit Sync Engine sample](https://github.com/apple/sample-cloudkit-sync-engine) | R15が案内する公式sampleの存在。sample本体を検証・実行した結果ではない。 |
| R18 | Apple, [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) | 全文。用途とbundle単位の宣言、承認理由、対象一覧の更新。 |
| R19 | Apple, [NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) | 5カテゴリのPossible Valuesと対象API。 |
| R20 | Apple, [NSPrivacyAccessedAPITypeReasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) | Possible Valuesの全理由。本文の候補表は製品に関係する用途を抜粋。 |
| R21 | Apple, [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) | 概要、ファイル名、各宣言。 |
| R22 | Apple, [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) | manifest validation、app / framework / package / static library / XCFramework配置。 |
| R23 | Apple, [Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/) | 対象SDK一覧の全項目、任意version・再包装、バイナリ署名の条件。 |
| R24 | Apple, [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/) | Data collection、tracking、Additional guidanceのon-device / Apple services / free-form text / ephemeral handling。 |
| R25 | Apple, [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) | SDK minimum requirements（Since April 28, 2026）。配布直前に再確認する。 |
| R26 | Apple, [Consuming relevant store changes](https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes) | transaction token、変更のfilter、view contextへのmerge、tombstone、履歴削除。 |

[R01]: https://doi.org/10.1145/358886.358895
[R02]: https://doi.org/10.1145/2470654.2481317
[R03]: https://link.springer.com/article/10.3758/BF03193094
[R04]: https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
[R05]: https://developer.apple.com/app-store/review/guidelines/
[R06]: https://developer.apple.com/documentation/uikit/uipasteboard
[R07]: https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly
[R08]: https://developer.apple.com/documentation/uikit/uipasteboard/setitemproviders(_:localonly:expirationdate:)
[R09]: https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate
[R10]: https://developer.apple.com/documentation/uikit/uipasteboard/setitems(_:options:)
[R11]: https://developer.apple.com/documentation/uikit/uipasteboard/changecount
[R12]: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
[R13]: https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer
[R14]: https://developer.apple.com/videos/play/wwdc2019/202/
[R15]: https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5
[R16]: https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged
[R17]: https://github.com/apple/sample-cloudkit-sync-engine
[R18]: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
[R19]: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
[R20]: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons
[R21]: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
[R22]: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
[R23]: https://developer.apple.com/support/third-party-SDK-requirements/
[R24]: https://developer.apple.com/app-store/app-privacy-details/
[R25]: https://developer.apple.com/news/upcoming-requirements/
[R26]: https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes
