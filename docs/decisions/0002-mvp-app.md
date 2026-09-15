# 0002：nibble MVPの製品設計

状態：採用。設計基準日：2026-09-15。対象は日本語UIのiPhoneアプリ`Nibble`と共有拡張`NibbleShare`。最低対応OSはiOS 26.0、実行評価はiOS 26.5 Simulatorとする。

## 目的と設計原則

nibbleは、よく使うテキストを端末内に保存し、必要なときに探してコピーするツールである。利用者は入力先のアプリへ戻り、本文をペーストして作業を続ける。少ない操作で本文へ到達できること、作成・編集・削除に迷わないこと、入力・検索・描画を待たせないことを優先する。

製品を支える契約は次のとおりとする。

- 原文と検索用の値を分け、保存・編集・コピーで本文の空白・改行・Unicodeを保持する。
- 非同期操作は完了まで待てる`async` APIで提供し、呼出元がタスクとして開始するかを選ぶ。
- UIがタスクの所有者・寿命・重複方針を持ち、モデルが操作と表示状態、保存層が永続化と整合性を担う。
- 入力を下書きとして保持し、保存・閉じる・破棄は永続化の結果が確定してから画面を閉じる。
- アニメーションの適用範囲を明示し、入力やスクロールへ不要な表示変化を伝えない。
- 採用技術は使いやすさ、性能、OS制約、保守・運用、移行の負担で判断する。

この文書は機能・画面・データ・実行時の責務を定義する。コードを書く際の制約は[実装規約](../library-policy.md)、操作と期待結果は[MVP手順](../mvp.md)、実施済みの確認は[検証結果](../mvp-validation.md)を参照する。

## 利用シーンと提供範囲

| 利用シーン | 提供する機能 |
| --- | --- |
| 定型文を探して使う | タイトル・本文の部分一致検索、ピン留め、保存済み本文のコピー |
| テキストを作成・編集する | 任意タイトルとプレーンテキスト本文、明示保存、下書きの保存・再開・破棄、編集競合からの回復 |
| 不要な項目を整理する | 削除、直後の取り消し、削除一覧からの復元、確認付きの完全削除 |
| 他アプリの内容を保存する | 共有シートからテキストまたはURLを1件読み、内容を確認・編集して保存 |
| 作業中にnibbleを開く | 本体起動、Apple「ショートカット」の標準URLアクションによる一覧・作成画面の表示 |

日常操作にアカウントと通信を必要としない。入力先への復帰とペーストは利用者が行う。同期、独自バックアップ、書式付きテキスト、画像・ファイル、変数展開、AI、課金はMVPの提供範囲外とする。キーボード拡張、Widget、Controls、App Shortcutsの自動登録、任意アプリへの重ね合わせ表示、自動挿入も構成に含めない。

## 画面とフィードバック

本文の読み取りとコピーを画面の中心に置く。システムフォントとDynamic Type、標準の一覧・入力・シート・メニュー・確認ダイアログを使う。ライト外観はクリーム色の背景と錆色のアクセント、ダーク外観は暗いグレーの背景と明るいオレンジのアクセントとする。

| 画面 | 表示・操作 | 状態と回復 |
| --- | --- | --- |
| 一覧 | 検索欄、「すべて／ピン留め」、スニペット行、作成ボタン。行右端でコピー、行タップで編集 | 空の一覧には作成への入口、検索0件には語句変更の案内を表示。検索語が空で削除一覧以外の場合に下書きを表示 |
| 編集 | 任意タイトル、複数行本文、保存・閉じる・キーボードを閉じる操作。その他メニューに本文共有と下書き破棄 | 本文領域は内容に応じて伸び、ページ全体をスクロール可能。保存処理中は終了操作を無効化し、失敗時は入力とエラーを保持。シートのスワイプ終了は無効 |
| 削除した項目 | 一覧のその他メニューから開き、復元または確認付きの完全削除を行う | 通常の一覧・コピーから除外。自動消去は行わず、完全削除時は関連下書きも消去 |
| 共有拡張 | 取り込んだ本文を本体と共通の編集画面で確認・編集する | 永続化に成功したら共有元へ戻る。閉じる操作で残した下書きは本体で再開可能 |

ピン留め・削除は長押しメニューまたはスワイプから選ぶ。スワイプし切るだけでは実行しない。コピー・検索クリア・復元の操作領域は44 pt以上とする。

コピー完了は触覚と2秒間の通知、削除完了は6秒間の取り消し操作で伝える。通知文はアクセシビリティのannouncementにも送る。コピー処理の完了と通知の表示期間は独立させ、コピーの呼出元を通知消去まで待たせない。

## 構成と責務

本体と共有拡張は別プロセスで動作し、App Group内のSQLiteを共有する。各プロセスは`SnippetStore` actorで自身の接続を管理する。actor間では値型を渡し、SQLiteの接続・statement・ポインタをUIへ公開しない。

```mermaid
flowchart TB
    Events[一覧の操作・sceneイベント・URL] --> View[LibraryView / LibraryTaskOwner]
    View -->|開始した操作をawait| Library[LibraryModel]
    Library -->|Draft| Editor[SnippetEditor]
    Host[共有元アプリ] --> Share[ShareViewController]
    Share --> Editor
    Editor -->|操作・snapshot書込をawait| Model[EditorModel]
    Library --> Store[各プロセスの SnippetStore actor]
    Model --> Store
    Share --> Store
    Store --> DB[(App Group / SQLite)]
    Library --> Clipboard[端末内のクリップボード]
```

| 構成要素 | 責務 |
| --- | --- |
| `LibraryView` | `@State`で一覧モデルと`LibraryTaskOwner`を保持。画面・フォーカス・シート・sceneイベント・通知scopeを接続 |
| `LibraryTaskOwner` | 一覧UIの非構造化タスクを所有し、明示的な`startTask`で開始。ID・寿命・重複方針・キャンセルを管理 |
| `LibraryModel` | MainActor上の検索条件・一覧・編集入口・通知状態。読込、コピー、項目更新を待機可能な操作として提供 |
| `SnippetEditor` | 編集モデルと終了操作のTasking storeを保持。入力snapshotの書込をSwiftUI `.task`で待ち、終了操作の成功後にdismissまたは共有元へ完了通知 |
| `EditorModel` | MainActor上の入力・sequence・busy・終了・競合・エラー状態。snapshot書込と保存・閉じる・破棄の完了を提供 |
| `ShareViewController` | UIKitの拡張入口。provider読込タスクの所有、入力検証、共通編集画面の表示、共有元への完了通知 |
| `SnippetStore` actor | 接続、検索、トランザクション、revisionとsequenceの検査、永続化 |

SwiftUI・Observationで表示状態を扱い、UIモデルには`@MainActor`を明示する。Swift language mode 6、strict concurrency complete、default isolation nonisolatedを使う。SQLiteの処理は専用actor内で実行し、トランザクション中に中断点を置かない。プロセス間の排他はSQLiteが担う。

## データの意味と永続化

| 用語・型 | 意味 |
| --- | --- |
| スニペット / `Snippet` | 保存済みのUUID・タイトル・本文・ピン留め・revision・更新日時・削除状態を持つ項目 |
| 一覧用要約 / `SnippetSummary` | 一覧に必要な属性と本文プレビュー。コピー時には保存層から本文全体を読む |
| 下書き / `Draft` | 独立したUUIDを持つ編集内容。既存項目の編集では対象UUIDと読込時のrevisionを持つ |
| revision | 保存済み項目の変更を識別し、編集開始後の競合を検出する値 |
| sequence | 下書きの入力変更ごとに増える番号。遅れて届いたsnapshotによる上書きを防ぐ値 |
| snapshot | ある時点の下書きを値として固定したもの。非同期の書込中にUIの入力が進んでも変化しない |

保存先はApp Group `group.dev.nibble.app`の`Library/snippets.sqlite`。WAL、`synchronous=FULL`、2秒のbusy timeoutを設定する。schema version 1は`snippets`と`drafts`で構成し、起動時に`user_version`を確認する。未知の新しいschemaや破損DBではエラーを返し、既存データを削除して空のストアを作らない。

タイトルと本文は空白・改行・タブ・Unicodeを保持する。保存時の上限はタイトル512 UTF-8 bytes、本文1,000,000 bytes。空白・改行だけの本文は保存不可とし、失敗時は入力を編集画面に残す。

編集開始時に下書きを作り、対象項目の下書きがあれば再開する。作成ボタンは新しい下書きを作る。保存は、対象項目が削除されておらず読込時のrevisionと一致する場合に受理する。競合時は入力を保持し、「新しい項目として保存」で別UUIDへ保存できる。

スニペットの保存と下書きの除去は1トランザクションで確定する。下書きの更新はsequenceが新しい既存行だけに適用する。保存・破棄後の遅れた書込で下書きを再生成しない。削除と復元は同じUUIDの削除状態を変更し、本文とピン留めを保持する。完全削除は項目と関連下書きを1トランザクションで消去する。

## 検索と一覧の性能

検索キーはタイトルと本文からNFCと日本語localeのcase/width foldingで生成し、原文と別に保存する。検索入力のたびに全本文を正規化しない。

| 項目 | 契約 |
| --- | --- |
| 一致条件 | 検索語の前後空白・改行を除き、SQLiteの`instr`で部分一致。日本語1文字から検索可能 |
| 文字の扱い | 英字大小・半角/全角を同一視。ひらがな／カタカナ、清音／濁音は区別。`%`・`_`・バックスラッシュは通常文字 |
| 並び順 | ピン留め優先、更新日時降順、UUID昇順 |
| 取得範囲 | 先頭100件。「さらに表示」で上限を100件増やし、先頭から再取得。次ページの有無を調べるため追加1件を読む |
| 一覧の本文 | `substr(body,1,180)`のプレビュー。コピーはDBから本文全体を取得 |
| 結果の反映 | 要求世代とキャンセル状態を照合し、有効な要求だけ一覧・loading状態へ反映 |

下書き一覧は本文を含めて取得するため、件数と長文に対するメモリ評価をスニペット一覧と分ける。検索測定は保存層の要求から返却までと、IME・状態更新・描画を含むUI応答を分ける。[検証結果](../mvp-validation.md)のSimulator測定値を実機の性能保証へ換算しない。

## 非同期操作の完了契約

モデルの`async` APIは、受理した操作の処理と結果反映を待ってから戻る。呼出元は既存タスクから直接awaitでき、同期UIイベントではUI所有者に開始を要求する。モデルはTaskingのstoreや開始用closureを保持しない。同期setter・initializerは同期的な状態初期化・更新だけを行う。

| 操作 | 呼出元が待つ範囲 |
| --- | --- |
| `refresh()` | 検索・下書き取得と、有効な要求世代の状態反映 |
| `open(id:)` | 下書きの選択または作成と、編集状態への反映。既に開いている場合や二重開始は受け付けない |
| `copy(_:)` | 保存済み本文の読込、pasteboardへの書込、通知状態の更新。通知の期限待ちは含めない |
| `pin`・`delete`・`restore`・`permanentlyDelete` | DB更新と一覧の再取得。表示するエラー・通知も操作内で扱う |
| `persist(_ snapshot:)` | 指定した不変snapshotのDB更新。終了済みeditorや別の下書きIDは受け付けない |
| `save(asNew:)`・`keepForLater()`・`discard()` | 最新入力を使う永続化と終了状態の確定。成功をBoolで返し、UIが画面を閉じる |
| `expireNotice(id:)` | 通知の期限待ちと、同じ通知IDの場合の消去 |

編集開始・コピー・項目更新・編集終了操作は開始時にキャンセルを確認する。重複・終了済み状態などで受け付けない要求は処理を始めず戻る。下書きのsnapshot書込は呼出元のキャンセルで破棄せず、DBのsequence比較で適用を判断する。業務上の失敗はモデルの表示状態へ変換し、入力を保持して再試行や競合からの回復を可能にする。

### 入力から編集終了まで

タイトル・本文のsetterは入力値とsequenceだけを更新する。`SnippetEditor`は描画時のsnapshotを取得し、`.task(id: snapshot.sequence)`から`persist(snapshot)`を直接awaitする。SwiftUIが入力更新を集約するため、全キーストロークを独立して永続化する契約にはしない。

保存・閉じるは自動保存の開始に依存せず、その時点の入力を直接永続化する。閉じる際は下書きを保持し、タイトル・本文がともに空の場合と、変更していない既存項目の編集では下書きを除去する。保存・閉じる・破棄を同じ終了操作IDで扱い、複数の終了操作を同時に受理しない。

受理済みのSQLite書込は完了まで進める。永続化が成功した終了操作には、途中でキャンセルが届いてもUIの終了通知を返す。異常終了直前に永続化が終わっていない入力の保持は保証しない。

## 操作の寿命と整合性

Taskingの`ActionID`は重複判定の単位、`ActionLifetime`はキャンセル対象を分類する値とする。lifetimeはsceneやviewを自動監視しない。所有者が終了イベントを`cancel(lifetime:)`へ接続する。

| 操作 | 所有者・ID | 寿命 / 重複方針 |
| --- | --- | --- |
| 一覧読込 | `LibraryTaskOwner` / `library.refresh` | sceneBound / cancelExisting |
| コピー | `LibraryTaskOwner` / `library.copy` | sceneBound / cancelExisting |
| 編集開始 | `LibraryTaskOwner` / `library.open` | screenBound / ignoreNew |
| ピン・削除・復元・完全削除 | `LibraryTaskOwner` / 操作種別と項目UUID | sceneBound / ignoreNew。同じ項目の同じ操作を抑止 |
| 保存・閉じる・破棄 | `SnippetEditor` / `editor.finish` | screenBound / ignoreNew |
| 共有provider読込 | `ShareViewController` / `share.load` | screenBound / ignoreNew |
| 下書き書込 | `SnippetEditor`の`.task(id: snapshot.sequence)` | SwiftUIが入力ID変更とview終了に応じてキャンセル |
| 通知期限 | `LibraryView`の`.task(id: noticeID)` | SwiftUIが通知ID変更とview終了に応じてキャンセル |

一覧読込は表示、検索・フィルタ・取得上限の変更、active復帰、編集終了で要求する。sceneBound操作はシート表示や一時的な非active化をまたいで完了する有限処理であり、一覧viewの`onDisappear`でキャンセルしない。sceneのbackground化では`endScreen()`で編集開始をキャンセルし、`clearNotice()`で通知ID・本文・取り消し操作を消す。

編集の終了操作は`SnippetEditor.onDisappear`、共有provider読込は`ShareViewController.viewDidDisappear`でscreenBoundをキャンセルする。コピーとprovider読込は読込の前後でキャンセルを確認し、通知期限は待機後にキャンセルと通知IDを確認する。キャンセルは停止要求であり、確定済みDB変更を取り消さない。

## アニメーションの適用範囲

アプリが指定するアニメーションはswift-scoped-animationで管理する。通知の表示・消去だけを`Library.Notice`という名前の`AnimationScope`で囲み、0.16秒のopacity遷移を使う。Reduce Motion有効時はdurationを0秒にする。

`LibraryView`と`SnippetEditor`の外側には`animationBarrier(warnsOnLeaks: false)`を置き、OSのシートtransactionが内容へ伝わるのを防ぐ。内側の`detectAnimationLeaks`と、入力領域の警告付きbarrierでアプリ内部の伝播をDebug実行時に診断する。標準シート・メニュー・キーボード自体の遷移はOS部品が管理する。診断だけで全表示変化の正しさを判定せず、対象導線を画像・録画で確認する。

## 呼び出しと共有の契約

| 入口 | 契約 |
| --- | --- |
| `nibble://library` | 検索語を空にし、「すべて」の一覧を表示 |
| `nibble://new` | 新しい下書きを作成し、編集画面を表示 |
| 編集中のURL受信 | 開いている編集内容を維持 |
| URLの許可条件 | 上記2種類だけを受理。path・query・fragment・認証情報・port付きURLを拒否し、本文や保存・削除指示を受け取らない |
| Share Extension | 共有元が渡す最初の対応providerから1件取得。plain textを優先し、URLは文字列として扱う。非対応形式・無効入力はエラー表示 |
| コピー | DBから読んだ本文を`localOnly`でpasteboardへ書込。pasteboardの読取・自動取り込みは行わない |

共有元のアプリをhostと呼ぶ。対応形式はhostの提供内容に依存し、URLを受け取ってWebページをダウンロードすることはない。providerのcallbackはchecked continuationで待機可能な読込に接続する。custom URL schemeに所有権の保証はないため、本文や機密情報の輸送には使わない。標準ペースト操作と`PasteButton`による取り込みは利用者が開始する。

## 技術選定と保守

| 採用 | 比較・判断理由 | 見直す条件 |
| --- | --- | --- |
| SwiftUI + Observation | 標準部品と明示的なUI状態で一覧・編集を構成。UIKitは共有拡張の入口で使用 | IME・フォーカス・表示の問題を標準部品で解決できない場合 |
| swift-tasking 0.3.0 | 個別のTask handle管理に対し、所有・寿命・重複方針を共通APIで表現。モデルの操作は独立したasync APIとする | 保守停止、対応条件の不適合、測定した応答の悪化 |
| swift-scoped-animation 0.2.1 | 個別のtransaction管理に対し、表示変化の範囲と伝播を共通APIで表現 | 保守停止、対応条件の不適合、描画の悪化、必要な表現を扱えない場合 |
| Apple同梱SQLite | SwiftData・Core Dataに対し、共有ストア、revision付き更新、下書きとのatomicな確定を直接検査可能。SQLとmigrationは手動管理 | 同期やschema変更で手動管理の負担が増す場合 |
| 保存済み検索キー + `instr` | 日本語1〜2文字の部分一致を原文保持と両立。FTS5 trigram MATCHの短い検索語の制約を避ける | 対象データ量での遅延、高度な検索・ランキングの必要性 |
| Share Extension + 標準URLアクション | host内での取り込みと、一覧・作成への呼び出しを公開APIで提供。利用者がショートカットを設定 | host・形式・件数の拡大、自動登録・音声操作・引数付きアクションの必要性 |
| 端末内保存 | アカウント・通信・同期競合を要しない日常操作 | 複数端末での利用を提供する場合 |

両Swift Packageはexact versionと共有`Package.resolved`で固定し、本体・共有拡張に同じ版をリンクする。MITライセンス通知を両bundleへ含める。補助ツールはNix、Xcode・SDK・runtimeはローカルのApple配布物で管理する。依存更新の手順は[実装規約](../library-policy.md#依存とビルド)に従う。

比較の根拠は[研究資料](../../research/README.md)に保存する。ResearchProbeの保存3方式やAPI試作は比較条件であり、製品の採用構成と区別する。

## データ保護と配布

保存先ディレクトリとDBにはData Protectionのcompleteを指定する。本体は非activeの一覧とbackgroundの編集画面に本文を隠す表示を重ねる。共有拡張は独立したapp sceneを持たないため、このscene状態による隠蔽を適用しない。ロック中のアクセスとアプリ切替画面の実際の露出は実機で評価する事項とする。

本文・検索語をログ、システム検索、analyticsへ送らない。本体・共有拡張にデータ収集・trackingなしのPrivacy Manifestを含める。依存更新と配布時には実際のAPI・データフロー・ライセンスと宣言の整合性を確認する。

schema変更はトランザクション内の明示的なmigrationと旧版fixtureで検証する。保存層を変更する場合はUUID・本文・下書き・削除状態の移行結果を照合する。WALを欠くDB本体のコピーをバックアップとして扱わない。独自のexport/import・バックアップ復旧は提供せず、アプリ削除後の復旧は保証範囲外とする。

署名配布には、本体と共有拡張の同一Developer Team・App Group、bundleのAPI・宣言・署名の点検を要する。配布方法、App Privacy回答、privacy policy、サポート窓口を配布判断に含める。コード公開とPRの運用は[開発ガイド](../../CONTRIBUTING.md)に従う。

## 機械検査と受け入れ条件

`swift-library-policy`で所有するSwiftソースを検査する。生のTask生成・別scheduler・直接アニメーション、モデルや通常メソッド・setterに隠れたタスク開始、store・開始APIの別名化を拒否する。構造化されたasync/await・task group・SwiftUI `.task`・協調用Task APIは利用できる。規則と適用限界は[実装規約](../library-policy.md)を正とする。

Swift Testingでは、モデルの操作を直接awaitして完了と状態を照合する。Taskingの所有者のテストでは寿命・重複・キャンセルを検査する。SQLiteの原文保持・競合・下書き順序・復旧条件も製品の保存層で確認する。

Ubuntu CIは同じNix lockで静的検査を行い、ローカルMacはApple CLIでビルド・テスト・撮影、sim-useでSimulatorを操作する。GitHub ActionsのmacOS runnerは間接起動を含めて禁止する。26.0への適合はdeployment targetとAPI availability、実行時の確認は26.5で行う。

MVPの受け入れはSimulator評価に限定し、実機検証は含めない。画像・動画にはソース・端末・OS・操作手順を付けてPRへ添付する。[検証結果](../mvp-validation.md)は実施した条件と未検証条件を示す。実機性能・ロック時保護・Handoff・署名配布・審査をSimulatorや未署名archiveの成功から保証しない。
