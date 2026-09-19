# テスト削除・統合の判断と検証

通常テストから測定だけの大量処理、依存の生成比較、直接呼ぶモックの自己検証を外し、製品の結果を確認するテストへ集約する。判断は「削除すると、どの現実的な不具合を見逃すか」で行い、テスト件数やカバレッジの維持を目的にしない。製品コード・依存・ビルド設定は変更しない。

## 監査範囲

2026-09-20、基点`bf8b29fada889c4d9110f39a62a59b303f84ea37`の製品Swift 118定義、研究Swift 14定義、検証host Swift 2定義、Python 156メソッド、計290定義を精査した。parameterized caseの展開数は含めない。加えて製品UI driver 4本、研究driver 3本、性能計測・補助Swiftを確認した。依存ライブラリのtestsと過去runは削除対象に含めない。

[全290定義の監査台帳](test-audit-inventory.csv)は基点時点のメソッド名・位置と、残す保証・候補IDを記録する。以下の54候補は部分削除や条件付き候補も含み、削除したメソッドの件数ではない。対象リンクは削除前のコードを特定する。欠番S04・P18は精査で棄却した候補であり、下記の「削減しない保証」に理由を記す。

## 削減しない保証

- 入力ごとの表示変更と元画像への復元を独立に確認する。一度に複数入力を変えると、比較漏れを別入力が隠す（旧S04）。空titleの表示分岐も残す。
- app・scripts・flakeの各入力変更、run中の変更、文書だけの変更を区別する。証跡の入力範囲から特定の種類が抜ける不具合は各々異なる（旧P18）。
- 自作の原文byte比較、SQL再bind、statement lease・再入・eviction、1MB入力上限、旧schemaからの移行を残す。標準ライブラリの再確認ではなく製品の契約である。
- 保存の受付後キャンセル、古い成功／失敗の異なる完了順、権限再確認、DB失敗時の原子性は残す。共通fixtureに寄せるためにこれらの境界を隠さない。
- ファイルを一度だけ読み、assetを分割してhashする契約は[共通ツールキット](../tools/ui-design/README.md)が明示している。P14ではspyを残し、P15では読取サイズを直接観測する。
- `.serialized`の再構成は行わない。UIKit、pasteboardなどの共有状態を使うsuiteの分離は、この重複削減とは別の設計判断になる。

## 候補と実施内容

監査時の提案・費用評価と今回の実装を区別する。監査時の「未計測」は実行前の判断で、今回の観測は末尾へ記録する。統合はfixtureと保証の重複を減らす場合に行い、単にメソッドを連結したことを高速化に数えない。

### S01 10,000件の検索計測

対象：[simulatorSearchMeasurements](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetStoreTests.swift#L186)。

実施：通常テストから削除。単独benchmarkの抽出元を現在の11ファイルへ更新し、比較する両variantを同じ-Osizeにそろえた。実行方法を製品手順に追加した。

監査時の判断：通常のNibbleTestsから外し、明示的に実行する性能計測へ移す。10,000件を保存し、4規模×2検索語×30回を計測するが、遅延の合否基準はない。

失う保証・残す検出手段：削除で失うのは規模別の測定データと大量件数での結果数確認。短い日本語・不一致・ページ上限は既存の検索／ページテストへ集約する。既存benchmark-store.pyは抽出元ファイル一覧が現在の分割構成に追従していないため、そのまま代替可能とは扱わず更新してから計測を移す。

費用との比較：最優先。10,000件のDB書込と240検索を通常テストから除外できる。Swift実時間は未計測。

### S02 closureとBindingを直接呼ぶ自己検証

対象：[replacedCallbacksAndBindingsAreNotEqual](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/RowComparisonTests.swift#L173)。

実施：直接closure呼出し・Binding代入・生成比較のテストを削除。mounted Binding差替えは保持。callbackのmount後差替えは今回新たに保証していない。

監査時の判断：メソッドを削除する。second.performを直接呼ぶカウンタ検査とnewFilter.selectionへの直接代入は、古いViewから新しい入力への差替えを試していない。値コピーの==、UUIDを含む新規Viewの!=も生成比較の反復。

失う保証・残す検出手段：現実の「画面が古いcallbackを保持する」不具合は現状でも検出できない。Bindingの画面上の差替えはmountedFilterTracksReplacementBindingWithoutRetainingTheOldSourceを残す。callback差替えの保証が必要なら実際にmount・差替え・タップする1ケースに置き換える。

費用との比較：実行時間より、内部プロパティと生成比較への修正負担を減らす効果。

### S03 生成された等価比較の項目別反復

対象：[everyDisplayedInputParticipatesInEquality](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/RowComparisonTests.swift#L12)。

実施：裸の比較メソッドを削除。mountedテストへunusedSinceと空title時のpreview単独変更・復元を追加した。

監査時の判断：裸の==／!=列挙を削除し、表示の更新をmountedRowUpdatesAndReturnsToTheSamePixelsに集約する。

失う保証・残す検出手段：unusedSinceの表示変更と、空titleのままpreviewだけを変更する表示は現在のmountedテストに不足するため追加してから削除する。残す保証は「入力が変わると該当表示が変わる」。macroの比較生成そのものの再確認を減らす。

費用との比較：目的は表示入力変更時の二重修正を減らすこと。追加のmounted確認は安価な==より重くなるので、速度短縮候補とは扱わない。

### S05 Riveのオブジェクト同一性

対象：[riveContractAndIndependentSessions](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/RivePresentationTests.swift#L8)。

実施：オブジェクト同一性のassertionを削除し、独立Sessionの状態を確認する。

監査時の判断：fileの===、artboard／stateMachine／dataの!==を削る。片方のSessionを変更してももう片方に影響しない振る舞いと、製品アセットの型契約を残す。

失う保証・残す検出手段：失うのはライブラリ内の共有・割当方式変更の検出。独立Sessionの状態混線は残す振る舞い検査で検出できる。

費用との比較：RivePresentation更新時の内部構造への追従負担を削減。

### S06 Riveの1,200フレーム送り

対象：[riveAssetLoopsAndAllowsExplicitStaticState](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/RivePresentationTests.swift#L34)。

実施：長いadvanceのメソッドを削除。短いmotionのfalse→true復帰をSessionテストへ統合した。

監査時の判断：800回／400回のadvanceと同じactive値の再確認を削る。true→false→trueの短い状態遷移だけ必要ならS05のSession契約テストへ統合する。

失う保証・残す検出手段：activeは状態への入場で設定されるフラグで、アニメーションの位置や周期を検査していない。ループがoneShotになって停止しても同じ状態内にいれば通り得る。周期と見た目はRMLのloop設定およびcheck-about-uiの映像確認へ集約する。

費用との比較：1,200フレームの手動評価とSessionの重複生成を削減。ループを保証しているという誤認も解消。

### S07 存在しないRiveファイルのライブラリ例外

対象：[missingRiveResourceIsAnError](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/RivePresentationTests.swift#L54)。

実施：missing-animationの例外だけを確認するメソッドを削除した。

監査時の判断：製品の回復処理を通らず、RiveResource.loadの任意のErrorだけを要求するテストを削除する。

失う保証・残す検出手段：失うのは依存ライブラリがmissing-animationで例外を返す保証。製品アセットの欠落は実アセットを読むS05とアセット整合検査で検出する。画面の失敗表示はこのテストでは保証していない。

費用との比較：ライブラリの再確認と弱い例外期待を除去。

### S08 名前だけがrapidな保存テスト

対象：[rapidInputAndSaveKeepLatestTextWithoutResurrectingDraft](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OwnedActionTests.swift#L140)。

実施：同期setter反復の保存テストを削除。残すautosave競合へ開始を待つgateを追加し、保存完了後に古いupdateを解放する。

監査時の判断：メソッドを削除する。30回のsetterは同期ループで、進行中の保存との競合を作っていない。

失う保証・残す検出手段：最新値の保存と保存後の下書き再出現防止はadmittedAutosaveAndImmediateSaveCannotResurrectDraft、settersOnlyChangeMemoryAndPersistenceIsAwaitable、DBのdraftOrderingAndLateWritesへ集約できる。残す競合テストではautosave開始をgateで確認し、単にasync letの開始順を仮定しない。

費用との比較：DBとEditorの重複fixtureを1つ減らす。

### S09 再開テストの30入力

対象：[rapidInputCanResumeAfterClose](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OwnedActionTests.swift#L153)。

実施：30回のsetterを2回に縮小し、再開後の最新値を確認する。

監査時の判断：同期setterの30回反復を「旧値→最新値」の2回にする。close後の再開と原文確認を残す。

失う保証・残す検出手段：入力回数依存の負荷特性以外は失わない。これは競合・性能の測定ではなく、keepした下書きが再開できるかの検査。

費用との比較：主にfixture意図の明確化。時間短縮は小さい。

### S10 巨大文字列とDraftだけの検査でのDB生成

対象：[newerSequenceKeepsLongInputAndEqualSequenceRequiresExactBytes](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L7)、[byteComparisonPreservesEmptyNullUnicodeAndLongInput](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L26)、[inputSequenceChangesOnlyWhenBytesChange](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L93)、[libraryReturnsBoundedSummariesAndReopensTheFullBody](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L119)、[untitledDraftsRemainDistinctAndAllLibraryBoundsTheirRows](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L135)、[reusedStatementsReplaceEveryBindingAndKeepOriginalBytes](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/PersistenceBoundaryTests.swift#L50)。

実施：巨大な反復文字列を境界に必要な短文へ、下書きを4件へ縮小。Draftのsequenceとbyte比較を直接生成する1テストへ統合した。

監査時の判断：百万文字の末尾差分、50,000回／100,000回repeatを小さな末尾差分に置換。180文字のpreview境界は181文字以上の最小fixtureへ。20下書きは4件で3件表示・2件ページ・全件展開を検査できる。Draft.sequenceだけの検査はDraftを直接生成し、byte比較側のsequence反復と統合する。

失う保証・残す検出手段：失うのは大容量時だけの性能・メモリ劣化の偶発的検出であり、この群に性能閾値はない。空文字、長さ差、NULより後の差、正規化で同一に見える異なるUTF-8、SQL再bind、実際の1MB入力上限テストは残す。自作memcmpラッパーは独自契約なので丸ごと削らない。

費用との比較：大きな文字列の割当・DB書込・読戻しを削減。削減時間の推計はしない。

### S11 古いピン分割・ページテスト

対象：[pinningAndPageLimits](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetStoreTests.swift#L56)、[librarySectionsKeepSearchIndependentAndRefreshSharedChanges](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L42)、[librarySectionsPreservePagingAndRestoration](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L71)。

実施：古いピン分割・ページの2メソッドを削除。別モデルの検索分離と共有変更の反映は残した。

監査時の判断：pinningAndPageLimitsとlibrarySectionsPreservePagingAndRestorationを削除候補とし、pageLookaheadAndFiltersStayConsistent、globalOrderAndPagingDoNotPartitionPins、削除復元テストに集約する。librarySectionsKeepSearchIndependentAndRefreshSharedChangesは別モデルの更新反映・検索分離だけ残し、otherItemsの分割確認を外す。

失う保証・残す検出手段：ページ境界、ピンfilter、復元、別接続更新はそれぞれ残す。復元後のpin保持はeditingDeletionAndRestorationPreserveUsageが確認している。otherItemsは製品Viewで使われておらず、現在の一覧は使用順の全件表示。pinnedItemsはpinned filterで使用中なのでその保証は削らない。

費用との比較：重複するDBの初期化・CRUD・将来の並び順変更への追従を減らす。

### S12 実pasteboardテスト内のCRUD一式

対象：[directAwaitCompletesEachLibraryOperation](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L11)。

実施：実UIPasteboardへ保存本文をコピーする接続に絞った。Modelの永久削除結果はS16へ統合した。

監査時の判断：保存→実UIPasteboardへのコピーに絞る。pin、delete、restore、permanent deleteを同じテストで再走査する部分は専用のStore／Modelテストに集約する。

失う保証・残す検出手段：実際のSystemLibraryEffectsとOSの接続はここに固有なので残す。Model経由の永久削除後のDB結果・failure==nilはS16の統合先へ移す。Store単体成功だけでModelのawait完了まで保証したとしない。

費用との比較：UIIntegrationの直列区間と長い失敗連鎖を短くできる。

### S13 検索・filter・ページリセットの重複

対象：[changingSearchCriteriaResetsPaginationWithoutViewCallbacks](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L262)、[latestFilterResetsPagingAndKeepsSearchIndependent](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L129)、[supersededRefreshPublishesTheLatestQuery](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L403)。

実施：query・filter各setterのリセットと同値維持を、開始済みreadを逆順で終える1シナリオへ統合した。

監査時の判断：同じ値への代入ではページ維持、query変更／filter変更でページ初期化、最新要求だけ反映、という1系列へまとめる。supersededRefreshの独立テストは削除候補。

失う保証・残す検出手段：queryとfilterは別setterなので両方の変化を残す。古い処理が本当に開始してから新しい処理を開始するgateを使用する。開始前にownerへ連続投入するだけでは読み込み中の競合は保証しない。

費用との比較：fixtureとownerセットアップの重複を減らす。条件を引数化するだけで同じ回数実行するなら時間短縮には数えない。

### S14 実時間で待つ通知期限テスト

対象：[noticeExpiryIsSeparateAndCancellationPreservesNotice](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L499)、[displayStartsDeadlineAndOldExpiryCannotClearReplacement](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/NoticeTests.swift#L135)。

実施：実時間のexpiryテストを削除し、待機開始後にcancelしてからgateを解放する検査をNoticeTestsへ統合した。

監査時の判断：Operation側を削除し、キャンセルしたexpiryが通知を消さないケースをPausedNoticeSleeperのテストへ移す。notice==nil後のundoID==nilは削除する。

失う保証・残す検出手段：通知の差替え、表示開始時の期限、再mount、キャンセルを残せば通知が早く消える／古い通知が最新通知を消す不具合を引き続き検出できる。単にOperation側を消すとキャンセル保証が抜けるので先に統合する。

費用との比較：約2秒の実期限待ちを除去可能。OSのタイマー接続は通知UIスクリプトの実期限確認を残す。

### S15 通知deadlineの壁時計余裕

対象：[displayStartsDeadlineAndOldExpiryCannotClearReplacement](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/NoticeTests.swift#L135)。

実施：製品への時計注入は追加せず、待機開始の前後で採った時計から2秒／6秒の期限範囲を検査する。1秒の実行余裕に依存しない。

監査時の判断：「現在から1秒超／5秒超残っている」の2比較は、注入した時刻から2秒／6秒先であることを1か所で検査する方式に置き換える。

失う保証・残す検出手段：そのまま比較だけ削ると期限計算の誤りを見逃す。現在のテストはマシン停止・負荷による経過でも落ちるため、期限の計算と待機解除の検査を分けて同じ契約を残す。

費用との比較：不安定要因の除去。実際の失敗頻度は測っていない。

### S16 連続削除と通知対象ID

対象：[consecutiveDeletionsKeepTheUndoSubjectAndIdentityTogether](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L459)。

実施：連続deleteと最新undoをNoticeTestsへ統合。Modelの永久削除をawaitした直後のDB欠落・failureなしも同じシナリオで確認する。

監査時の判断：NoticeTests.latestResultKeepsMessageSubjectTargetAndOriginTogetherへ連続delete→undoの1系列を移し、Operation側を削除する。

失う保証・残す検出手段：最新メッセージ・対象名・announcement・undo IDの一体性を残す。copyによる差替えと連続deleteは同一視しない。末尾のModel経由permanentlyDeleteとその対象名も移し、S12の削減と合わせて永久削除後のDB結果・failure==nilも残す。

費用との比較：同じ通知モデルとDBのセットアップを削減。

### S17 本文読取と副作用境界の重複

対象：[bodyReadRejectsDeletedAndMissingRowsAndPreservesBytes](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/PersistenceBoundaryTests.swift#L39)。

実施：本文専用の重複メソッドを削除。副作用境界の成功本文をUTF-8で比較し、NULと分解Unicodeを保持する。

監査時の判断：削除済み／missingの拒否はeffectsFollowSuccessfulReadsAndNeverRunForMissingOrDeletedItemsへ、原文はexactTextSurvivesReopenAndEditとKeyboardのexactBodyIsReadAtUseAndChangesAreRejectedへ集約する。

失う保証・残す検出手段：effects側の成功本文をNUL・分解Unicode付きにし、UTF-8で比較してからこのメソッドを削除する。単なるSwift Stringの==だけにすると正規化差分の保証が弱まる。

費用との比較：同じsavedBody経路のDB fixtureを減らす。

### S18 永久削除失敗の独立fixture

対象：[failedPermanentDeletionPreservesTheSnippetAndItsDraft](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/PersistenceBoundaryTests.swift#L25)。

実施：失敗した永久削除で紐づくdraftが残るassertionを削除復元のStoreテストへ移した。

監査時の判断：SnippetStoreTests.deletionIsRecoverableAcrossLaunchesの「現存項目の永久削除を拒否する」段階に、紐づくdraft保持の検査を移してメソッドを削除する。

失う保証・残す検出手段：draftが先に消えてしまうトランザクション順序の不具合は固有なので、そのassertionは削らない。

費用との比較：保証を維持し、DB生成・項目作成の反復だけを削減。

### S19 汎用transactionのrollback反復

対象：[statementFailureRollsBackAndTheNextTransactionCanCommit](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/PersistenceBoundaryTests.swift#L69)、[failedWriteRollsBackReceiptAndBothUsageFields](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetUsageTests.swift#L91)。

実施：汎用テーブルのrollbackテストとreceipt件数の内部SQL確認を削除。製品のtrigger失敗・同じ操作IDでの再試行・使用日時を確認する。

監査時の判断：汎用テーブルでの重複キー→rollback→次commitは、実際のrecordUseをtriggerで失敗させ再試行するテストへ集約可能。使用記録テストの内部snippet_uses件数0のSQL検査も、同じ操作IDの再試行成功で置き換えられる。

失う保証・残す検出手段：recordUseは同じSQLiteDatabase.writeTransactionを通り、receiptが残れば再試行が早期returnしてuseCount==1にならない。失敗直後のcount==0／lastUsedAt==nilと再試行後のcount・日時を残す。自作transaction wrapper自体の保証を捨てる提案ではない。

費用との比較：schema内部への依存と独立DB fixtureを1つ削減。

### S20 使用時刻の精度と冪等性

対象：[retriesCompareThePersistedTimestampPrecision](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetUsageTests.swift#L10)、[retriesAreIdempotentAndLateRecordsDoNotMoveLastUseBackwards](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetUsageTests.swift#L71)。

実施：冪等性の基準時刻へDateのepoch変換で丸め差が出る小数値を採用し、精度だけのメソッドを削除した。

監査時の判断：後者の基準時刻に前者の丸め差が発生する小数値を採用し、前者を統合する。

失う保証・残す検出手段：SQLiteのepoch表現とDateへの往復で同じ操作をconflictにする現実の不具合は残して検出する。精度ケースを通常の整数秒に置き換えてはいけない。

費用との比較：同じrecordUse再試行のDB fixtureを削減。

### S21 205行の計算で作るソート期待値

対象：[globalOrderAndPagingDoNotPartitionPins](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetUsageTests.swift#L107)。

実施：順序は5件の明示的な期待ID列、ページは201件の既知順へ分割。期待値をソート実装と同形の計算で作らない。

監査時の判断：並び順は5件程度の固定ID・固定期待順で使用回数→更新時刻→IDとpin非分割を検査する。ページ拡張は単純な既知順データで別に確認し、ソート実装と同形のindices.sortedやfirstIndexで期待値を再計算しない。

失う保証・残す検出手段：多ページ拡張・漏れ・重複は必要。現在expandedは100件ずつ増えるため、fixtureだけ5件にして全ページ保証も維持できるとはしない。現行APIのままならページ側の201件以上は残し、ordering側だけを小さくする。

費用との比較：主効果は独立した期待値とschema変更時の修正負担軽減。205件すべてを無条件に削減できるという時間見積もりはしない。

### S22 30挿入／40使用記録の競合反復

対象：[parallelConnectionsKeepEveryInsert](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetStoreTests.swift#L123)、[concurrentConnectionsCountEachCompletedCopyOnce](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetUsageTests.swift#L23)。

実施：2接続の挿入を4件、使用記録を4操作×2接続へ縮小した。

監査時の判断：異なる2接続・複数の一意操作・同一操作IDの重複を保ち、30挿入と20種類×2回の記録を2〜4種類程度に減らす。

失う保証・残す検出手段：失うのは偶然のスケジューリングによるストレス検出率。現状も衝突時点を制御していない。2接続間のlost updateと二重計上という保証を残し、負荷の再現は明示的なstress実行に分離する。

費用との比較：DB書込数を削減。接続数や重複IDまで1つに潰してはならない。

### S23 削除候補の時間境界

対象：[candidateBoundaryUsesElapsedHoursAndRequiresRecordedUse](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/SnippetUsageTests.swift#L138)。

実施：記録なし・pin付き境界直前・境界ちょうどへ縮小。時計進行と未pinのケースは既存のrefreshテストに残る。

監査時の判断：未使用・境界直前・境界ちょうどを核にし、境界後+1と未来時刻など同じ側の例を減らす。pin true/falseの全組合せは止め、pin付きの境界例を1つ残す。

失う保証・残す検出手段：使用記録なし、閾値の>=誤り、pinで候補判定が変わる誤りを残して検出する。refreshReevaluatesTimeWithoutModifyingUsageにある時計進行も重ねて増やさない。

費用との比較：時間短縮は小さい。判定規則の重複表現を減らす。

### S24 同じ分岐のfilterと空白例

対象：[creatingFromFilteredLibraryReturnsToAll](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L267)、[editorExplainsRequiredBodyWithoutChangingOriginalInput](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/OperationTests.swift#L481)。

実施：新規作成filterをdrafts代表へ、空本文を空文字と空白改行混在へ縮小した。

監査時の判断：作成時のfilterリセットは代表1種にする。空bodyの複数空白表現は空文字＋空白改行混在1例へ減らす。

失う保証・残す検出手段：新規作成では現在filterに依存しない同一処理を通る。入力側は完全な空文字とtrimで空になる入力は別の条件なので両方残す。保存前に原文を勝手にtrimしないことも残す。

費用との比較：少量のfixture／assertion反復を削減。

### S25 Keyboardのcopy／insert共通失効条件

対象：[copyHasItsOwnLifetimeAndDoesNotDependOnTheInsertionPoint](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/KeyboardTests.swift#L179)、[lateUseCannotReachAnInvalidDestination](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/KeyboardTests.swift#L222)。

実施：copy側の共通失効反復を削除。入力先のdocumentとrevisionを変更してもcopyできる例と、copy固有の権限再確認を残した。

監査時の判断：copy側のdisappear／reload／cancelの反復は、useの共通guardを通るinsert側に集約する。copy側はdocumentとselectionを同時に変更してもコピーできる1例へまとめる。

失う保証・残す検出手段：copyとinsertで本当に異なる「入力先が変わったらinsertだけ拒否」「copyの権限再確認」は残す。共通guardがswitchより前にある現在の構造に限った削減で、経路を分離する変更時には境界テストを再配置する。

費用との比較：パラメータ化で増えている非同期シナリオを削減。

### S26 Keyboardの件数・長文・revision採番

対象：[savedPagesExcludeDraftsAndTrashAndRemainBounded](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/KeyboardTests.swift#L16)、[pinChangesOnlyTheFlagAndRevisionAndRejectsStaleItems](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/KeyboardTests.swift#L80)、[openingAndClosingPreviewNeverInsertsAndDiscardsLateText](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/KeyboardTests.swift#L276)。

実施：51件でページ境界を検査。短いpreview差替えとstale拒否を残しrevisionの+1固定を削除。挿入直前に読んだ本文がpreviewと異なる例を使う。

監査時の判断：53件は51件に、previewの5,000行は短い旧／新本文にする。revision == old+1の数値固定は外し、古いrevisionの項目を拒否することを残す。

失う保証・残す検出手段：50件の境界・次ページ・全文preview差替え・stale拒否は維持する。失うのは大容量負荷と採番の具体値だけ。previewの長さ制限はこのModelでは処理しておらず、この長文はfake readerから渡した値。

費用との比較：fixtureの割当と内部採番への依存を削減。

### S27 等しいsequenceのUnicode競合

対象：[equalSequenceWithDifferentUnicodeBytesIsAConflict](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/app/NibbleTests/DraftLifecycleTests.swift#L77)。

実施：同じsequenceで異なるUTF-8に対して、keep・saveは競合を返し、updateは何も上書きせず終了する契約を1シナリオへ統合した。

監査時の判断：newerSequenceKeepsLongInputAndEqualSequenceRequiresExactBytesへ、同一sequence・異なるUTF-8のupdate非上書き・save拒否をまとめる。Swift Stringの正規化同値を確認するfirst.body==second.bodyなどのsetup assertionは削る。

失う保証・残す検出手段：updateDraftとsaveは異なるAPIなのでupdateの非上書き・saveの拒否と元データ保持を残す。Swift Stringの==の標準挙動の再確認だけを削る。

費用との比較：共通のdraft作成とライブラリ保証の反復を削減。

### P01 TestFlight設定テストの明確な重複3件

対象：[test_rejects_broad_permissions_and_symlinks](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L130)、[test_check_config_prints_no_values_and_makes_no_native_calls](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L140)、[test_configuration_failure_does_not_print_exception_details](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L151)。

実施：重複3メソッドを削除。既存の強い設定・秘密非露出テストへ集約した。

監査時の判断：それぞれtest_configuration_failures_report_only_fixed_steps_without_reading_keys、test_export_and_additional_fields_use_only_required_values、test_unclassified_errors_and_check_names_cannot_expose_arbitrary_textへ集約して削除する。

失う保証・残す検出手段：権限／symlink拒否、CLI成功時の値非表示・native未実行、例外文非表示を既存のより強い検査が持つ。資格情報を守る条件そのものを削る提案ではない。

費用との比較：3つの設定fixtureと期待文言の保守を削減。Python全体が2.86秒なので速度効果は小さい。

### P02 暗号宣言の3bundle×5不正値

対象：[test_encryption_declaration_must_be_boolean_false_in_all_bundles](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L278)。

実施：代表bundleで4不正値、残り2bundleではtrueの拒否を確認する。数値0の拒否は残した。

監査時の判断：各bundleで検査が呼ばれることは1つの不正値で確認し、missing／true／文字列／数値などの値判定は代表bundleに寄せる。2つの文字列NOとfalseは1つに減らす。

失う保証・残す検出手段：本体・share・keyboardすべてが検査されることは残す。特に0はFalseと==になるため、bool以外を拒否する独自契約の重要なケースとして残す。

費用との比較：全組合せのplist再生成と入力規則変更時の重複修正を削減。

### P03 同じcatch節へ入る3例外

対象：[test_unclassified_errors_and_check_names_cannot_expose_arbitrary_text](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L241)。

実施：同じcatch節は秘密を含むOSError代表へ縮小。任意check名の非露出は別に残した。

監査時の判断：load_credentialsからのOSError／ValueError／DistributionErrorを同じ固定文へ変換する部分は代表1例にする。任意のcheck名が出力へ漏れない別ケースは残す。

失う保証・残す検出手段：現在は3型を同じexcept節で処理している。各型の存在を列挙する保証は失うが、秘密文字列を含む汎用例外が固定文へ変換される保証を残す価値が高い。CredentialErrorの工程別処理は別テストで残す。

費用との比較：3回のmain実行の反復を削減。

### P04 2つの不正条件が混ざるarchive検査

対象：[test_keyboard_is_required_and_its_configuration_and_version_are_validated](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L297)。

実施：keyboardを正常に復元してからunexpected extensionを追加し、その違反単独で落ちる検査へ修正した。

監査時の判断：keyboardを削除したままunexpected extensionを追加する末尾の再検査を削除する。unexpected extensionの拒否を保証したいなら、keyboardを復元した正常archiveから別途1回だけ検査する。

失う保証・残す検出手段：現状はkeyboard欠落だけで失敗できるため、unexpected extensionの拒否が壊れても通る。削除で失う固有の保証はない。

費用との比較：無効なケース増殖と誤った安心を除去。

### P05 配布失敗テストの表示内部

対象：[test_native_errors_and_timeouts_never_return_raw_output_or_inherited_credentials](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_testflight.py#L406)。

実施：配布失敗の細かい表示block期待を削除。終了コードと秘密・生ログ非露出を残した。

監査時の判断：hamio stepの詳細な日本語文言／block配置の重複assertionを外し、失敗・終了コード・秘密と生ログ非露出を残す。

失う保証・残す検出手段：表示adapterのstep成否・例外文非表示はtest_step_propagates_original_failure_and_never_displays_exceptionが担当する。配布側で同じ表示整形を固定する必要はない。

費用との比較：表示文言変更による配布ロジックと無関係な失敗を減らす。

### P06 OS拒否の重複例

対象：[test_every_other_execution_version_is_rejected](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ios.py#L42)、[test_older_os_rejected](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ios.py#L53)。

実施：古いOS単独メソッドと26.0反復を削除。26.5成功と26.4／26.5.1／27.0拒否を残した。

監査時の判断：18.6だけの独立テストを削除し、26.0と26.4は代表1つにする。正確に26.5のみ許可する契約は、26.4／26.5.1／27.0の拒否と26.5成功で検査する。

失う保証・残す検出手段：18.6はminimum比較の別分岐を通るが、製品の観測結果は同じ拒否であり、このテストはminimum専用エラーの契約も検査していない。最低OSの比較処理だけが壊れても26.5限定の拒否が有効なら運用上の漏れはない。

費用との比較：低コスト。内部分岐数を理由に同じ拒否を増やすのを止める。

### P07 native失敗ログのmock／実process二重検査

対象：[test_failed_command_preserves_logs_and_nonzero_exit](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ios.py#L203)、[test_ios_command_retains_native_logs_and_exit_code_with_real_display](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_script_ui.py#L184)。

実施：成功・失敗の実processと実Reporterをtest_iosへ移し、hamio不在で汎用process保証がskipされない形に統合した。

監査時の判断：実際の子processを使う後者を基本にし、stdout／stderrログと元exit codeの保証を1か所へ集約する。

失う保証・残す検出手段：ただし後者はInstalledHamioTestsのskip条件内にある。汎用のprocess保証をskipされないtest_iosへ移し、実hamio接続部分だけを追加検査にした後で重複部分を削る。単純に前者だけ削除するとhamio未提供環境で保証が抜ける。

費用との比較：mockの指定値を戻して検査する反復を減らし、実processで境界を検査。

### P08 Swift policy CLIの二重起動

対象：[test_scan_includes_tests_research_and_new_source_directories](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_swift_policy.py#L225)、[test_swift_check_reports_real_success_and_failure_exit_codes](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_script_ui.py#L153)。

実施：探索テスト内の再CLI起動を削除。診断path:line:columnの期待を実CLI・adapter接続テストへ移した。

監査時の判断：前者はcheck(root)の再帰探索・対象除外だけにし、subprocessで同じ検査をもう1度走らせる末尾を削除する。CLIのpath:line:column表示確認は後者の失敗時assertionへ移す。

失う保証・残す検出手段：新規ディレクトリ、tests、researchの探索とartifacts除外は単体で残る。CLI終了コード・表示・位置の形式は実adapterを通す1組へ集約する。

費用との比較：前者は今回0.156秒。これはメソッド全体の測定で、全量を削減時間とは扱わない。

### P09 診断位置の追加テスト

対象：[test_app_macros_diagnostics_preserve_unicode_positions](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_equatable_policy.py#L105)。

実施：Unicodeが別行にしかない追加位置テストを削除した。

監査時の判断：test_diagnostics_preserve_original_line_and_columnへ位置検査を集約し、このメソッドを削除する。

失う保証・残す検出手段：日本語は前の行のコメントにあるだけで、診断位置のある行はASCII。固有のUnicode列計算の保証になっていない。必要なら残す位置テストの同一行にUnicodeを置く。

費用との比較：診断算出共通経路の反復を除去。

### P10 同一protocol表記×違反種類の全組合せ

対象：[test_main_actor_conformance_preserves_comparison_rules](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_equatable_policy.py#L12)。

実施：protocol表記ごとの成功と代表拒否を残し、違反種類との直積を縮小した。

監査時の判断：EquatableBodyViewとAppMacros.EquatableBodyViewは各1つの成功・代表拒否を残し、両方へ5種類ずつ違反を掛ける全組合せを止める。個々の違反は既存の宣言・extension・隠れた入力テストへ集約する。

失う保証・残す検出手段：修飾名の認識と@MainActor conformanceの解析は自作parserの契約として残す。macroやcompilerが保証するから全部削るという判断ではない。

費用との比較：構文規則変更時の重複fixture修正を減らす。

### P11 コメント・補間・所有Stateの重複fixture

対象：[test_comments_and_strings_do_not_trigger_but_interpolation_does](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_equatable_policy.py#L101)、[test_owned_state_and_environment_do_not_require_parent_revision](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_equatable_policy.py#L117)。

実施：コメント・文字列・補間のEquatable例を共通lexerテストへ、State＋Environmentを正常な値View例へ統合した。

監査時の判断：コメント／文字列／補間の例は共通lexer回帰のtest_comments_strings_raw_strings_and_regex_are_not_codeとtest_string_interpolations_are_checked_including_nested_literalsへ移す。State＋Environmentの正常例はtest_value_only_comparison_views_and_native_values_are_allowedのState例とまとめる。

失う保証・残す検出手段：禁止API名だけを変えて同じlexical除外を反復する必要はない。ただしEquatable規則が補間内にも適用される代表例は移して残す。補間のtask-boundary parserは別経路なので削除しない。

費用との比較：主にケースの責務整理。移動だけなら実行時間の節約とは数えない。

### P12 3path欄×5不正path

対象：[test_paths_cannot_escape_project](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/tools/ui-design/tests/test_engine.py#L254)。

実施：inputで不正pathの5形状を、recordとregistryでは親参照を代表として拒否する。

監査時の判断：input／record／registry各欄で相対path検証が呼ばれる例を残し、絶対path・親参照・不正区切り等の形は代表欄へまとめる。

失う保証・残す検出手段：同じrelative_path関数へ渡す全組合せを減らす。各入口の検証漏れとpath正規化の異なる拒否条件は残す。

費用との比較：15例の直積を減らし、入力規則追加時の掛け算を避ける。

### P13 設計receipt／policyの重複2件

対象：[test_receipt_cannot_shrink_scope](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/tools/ui-design/tests/test_engine.py#L124)、[test_policy_changes_require_review_even_when_files_stay_the_same](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/tools/ui-design/tests/test_engine.py#L212)。

実施：receiptが空の例とpolicy単独変更の重複2メソッドを削除した。

監査時の判断：前者はtest_missing_or_incomplete_receipt_failsへ、後者はtest_narrowed_scope_cannot_reuse_previous_reviewへ集約して削除する。

失う保証・残す検出手段：空filesと1件欠落は同じ入力集合比較で検出し、{}専用の分岐はない。後者の統合先はpolicy.jsonのchanged診断を明示的に要求しているため、policy自体のhash取り忘れも検出する。

費用との比較：同じファイル比較のfixtureを2つ削減。

### P14 読取回数とparser呼出回数の固定

対象：[test_repeated_links_read_and_analyze_each_document_once](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_review_tooling.py#L260)、[test_each_input_is_opened_once_even_with_overlapping_scope](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/tools/ui-design/tests/test_engine.py#L285)。

実施：繰り返すリンクを200件から2件へ縮小。同じファイルのread・anchor解析回数のspyは明示契約なので保持した。

監査時の判断：繰返しリンク200件は2件へ減らす。anchors.call_countや特定のPathメソッドの呼出し方を固定するspyは、公開結果と性能計測へ置き換える候補。重複scopeが正しく扱える小fixtureは残す。

失う保証・残す検出手段：失うのは余分なI/O・再解析の早期検出。tools/ui-design/README.mdには「1回だけ読む」が明示契約なので、単なる内部事情として無条件削除はできない。契約を結果整合性・時間／メモリ上限へ改め、benchmark_docs.py／benchmarks/measure.pyで測る場合に削除する。

費用との比較：既存仕様の見直しを伴う候補。現在のPython全体2.86秒から、速度改善を優先理由にはしない。

### P15 read_bytesを呼ばないだけのstreaming検査

対象：[test_large_asset_is_streamed_and_content_changes_are_detected](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/tools/ui-design/tests/test_engine.py#L299)。

実施：read_bytes禁止spyを、実際のreadサイズが正で128KiB以下という観測へ置換。128KiB＋1 byteで複数chunkと改変検出を確認する。

監査時の判断：700KBのfixtureとread_bytes禁止spyを削り、binary改変検出はtest_source_asset_and_configuration_edits_require_reviewの小fixtureへ集約する。保持量の契約は既存の32MiB asset benchmark等で扱う。

失う保証・残す検出手段：このspyはopen().read()で一括読込しても通るため、bounded memoryを保証していない。分割hashの現行文書契約は残っているので、必要な実測または読取サイズを観測する1検査へ置き換えてから落とす。

費用との比較：実装メソッド名への結合を減らし、保証内容と検査内容を一致させる。

### P16 同一fixtureへの12並行check

対象：[test_concurrent_checks_are_deterministic_and_do_not_cache_between_calls](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/tools/ui-design/tests/test_engine.py#L333)。

実施：同じrootへの12回を、異なる違反を持つ2rootの並行呼出しへ置換。結果の混線と後続変更の反映を検査する。

監査時の判断：同じroot・同じ入力の12回呼出しは、異なる入力と期待結果を持つ2つの独立rootの並行呼出しに置換する。後続の変更反映は1回残す。

失う保証・残す検出手段：同一入力だけでは呼出し間の共有状態の混線を見逃しやすい。公開契約で並行呼出しを許可しているため並行性自体は削らず、混線を検出できる小さい例へ変える。

費用との比較：filesystem走査・解析の反復を減らす。

### P17 証跡検査で毎回Git初期化

対象：[test_tampered_media_failed_run_old_os_or_missing_logs_rejected](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_review_tooling.py#L174)、[test_tolerated_failure_requires_successful_specific_assertion](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_review_tooling.py#L187)、[test_standalone_media_or_build_for_another_target_cannot_certify_source](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_review_tooling.py#L201)、[test_review_bound_to_media_and_access_declaration](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_review_tooling.py#L211)、[test_sampled_video_requires_real_timestamp_and_not_full_playback_claim](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_review_tooling.py#L228)。

実施：軽いEvidenceFixtureと実Gitを扱うEvidenceSourceTestsを分離。媒体・review辞書テストで毎回Gitを初期化しない。

監査時の判断：media／reviewの辞書検証に必要なmanifest・hashを作る軽いfixtureへ分離し、各ケースのgit init/add/commit/rev-parseを外す。Gitを使うsource照合・実行中変更テストはそのまま残す。

失う保証・残す検出手段：対象メソッドは実Gitの履歴変化を検査していない。hashを取り出す接続の保証はtest_reference_compares_files_and_allows_document_only_commitとtest_run_changed_during_execution_fails_and_keeps_manifestに集約する。

費用との比較：assertionを削らず外部processとfixture依存を減らす。156テスト中、Git fixtureを持つ群は実測でも相対的に重い。

### P19 processの採番・poll回数・timeout定数

対象：[test_launch_waits_for_native_target_process](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ios.py#L110)、[test_nested_monitor_labels_match_each_recorded_command](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ios.py#L173)、[test_recording_is_finalized_when_ui_action_fails](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ios.py#L209)、[test_json_is_checked_and_routed_only_to_stderr_without_ambient_secrets](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_script_ui.py#L27)。

実施：成功poll回数・連番の具体値・timeout秒数の固定を削除。一意なログ対応・有限timeout・SIGINT後のfinalizeを残した。

監査時の判断：成功まで3回というpoll回数、command-000/001/002という採番、30秒／3秒というtimeoutの数値固定を外す。PIDの同一性・log名との対応と一意性・SIGINT後のfinalize・有限timeoutを残す。

失う保証・残す検出手段：失うのは内部の待機・命名方針変更の検出。process誤認、ログ上書き、録画の未確定、無限待機は観測可能な契約として残す。missing processが有限回で失敗するテストは削らない。

費用との比較：正常な運用調整による無関係なテスト修正を削減。

### P20 依存CLIのcapabilitiesと無意味な引数表記違い

対象：[test_actual_hamio_version_contract_and_display_of_business_failure](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_script_ui.py#L133)、[test_adapter_does_not_allow_overriding_product_policy](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_ui_design.py#L50)。

実施：capabilitiesの別processと--conf略記の反復を削除した。

監査時の判断：hamio capabilitiesの別subprocessは実render応答のversion契約と重複するので削る。adapterの--configと--confは明示的な--config拒否1例にする。

失う保証・残す検出手段：own adapterのprotocol整合性、business失敗表示、製品policyの上書き不可は残る。ライブラリのcapabilities出力とargparseの未定義略記の再確認を減らす。

費用との比較：外部processの重複起動を削減。--confの省略名特別扱いが将来必要になったときは独自契約として追加する。

### P21 長いUnicode診断fixture

対象：[test_long_unicode_diagnostics_are_preserved_within_string_limit](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/tests/test_script_ui.py#L90)。

実施：診断文字列を1025個の絵文字に縮小し、4096 byte境界・原文連結を確認する。

監査時の判断：3,000回repeatする文字列を4096境界を1回越える最小のUnicode付き文字列へ減らす。分割後の連結が原文と一致し、各blockが上限内にあることは残す。

失う保証・残す検出手段：独自の文字列分割で欠落・重複・Unicode破損を起こす不具合は残して検出できる。多数blockを連続生成する負荷特性だけが失われる。

費用との比較：低コスト。境界が何かを読み取りやすくする効果。

### R01 ResearchProbeの14テスト定義

対象：[environment](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L26)、[crudReopenReadOnly](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L36)、[sqliteFTSAndIndex](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L63)、[sqliteWALAndBackup](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L87)、[coreDataMigrationAndHistory](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L118)、[swiftDataHistory](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L132)、[swiftDataMigration](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L152)、[atomicSnapshotAndProtectionAttribute](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L168)、[invalidImportDoesNotChangeStore](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L183)、[failedSaveRetainsDraftAndRoutesRejectDestructiveInput](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L190)、[archiveRoundTripAndValidation](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L210)、[normalizationCorpusAndMarkedText](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L222)、[staleSearchAndDatasetTiming](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L240)、[pasteboardExpiration](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbeTests/HostedTests.swift#L282)。

実施：保持。研究は終了が決まっておらず、製品とは独立targetである。通常のNibbleTestsへは追加しない。終了時に14定義をtarget単位で削除できる候補として記録する。

監査時の判断：比較研究を閉じる際、14定義を研究targetごと削除候補にする。Core Data／SwiftData移行・history、FTS/index、SQLite backup、atomic snapshot、import/archive、研究Controllerの下書き・route・検索、OS pasteboard期限などは製品コードを通していない。

失う保証・残す検出手段：失うのは研究モデルとAPI調査の再実行性。現在の製品SQLite・原文・migration・競合・検索・copyの保証はNibbleTestsが担う。環境試験とcrudReopenReadOnlyも研究targetだけのもの。研究継続中なら独立targetのまま残す。過去の観測記録・失敗runは削除しない。

費用との比較：pasteboardExpirationには6秒の待機、staleSearchAndDatasetTimingには多方式・多件数計測がある。ただし既にResearchProbeは独立targetであり、削除しても通常NibbleTestsやNixの時間は短くならない。

### R02 研究専用driverとAPI compile probe

対象：[check-research-processes.py:1](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/check-research-processes.py#L1)、[check-research-sdk.py:1](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/check-research-sdk.py#L1)、[check-research-ui.py:1](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/check-research-ui.py#L1)、[SQLiteWorker.swift:1](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/SQLiteWorker.swift#L1)、[SDKCompileProbe.swift:1](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/ResearchProbe/SDKCompileProbe.swift#L1)。

実施：保持。R01と同じ終了条件で研究driver・compile probeを一括削除できる。過去の観測記録は保持する。

監査時の判断：R01の研究を閉じる場合にまとめて削除する。生SQLiteの別process実験、未採用APIのcompile、研究UIKit画面の操作を製品の恒常回帰に持ち込まない。

失う保証・残す検出手段：失うのは各研究条件の再現手段であり、製品のactor・App Group・extension・画面の実装保証ではない。製品を通す既存検査を残す。研究再開の可能性だけを理由に通常実行へ戻さない。

費用との比較：別targetのビルド・OS連携・研究画面の保守が減る。通常テストの時間削減とは別。

### V01 検証fixtureの2つのhostedテスト

対象：[hostIdentity](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/VerificationAppTests/HostedTests.swift#L8)、[exactTextTransfer](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/validation/VerificationAppTests/HostedTests.swift#L14)。

実施：host確認とfixtureへの原文反映を1メソッドへ統合。majorVersion比較だけ削除した。

監査時の判断：hostIdentityとexactTextTransferを、host確認→fixture入力反映の短い1シナリオにまとめる。majorVersion>=26はios.pyの厳密な26.5選択を通す運用では追加保証が弱い。

失う保証・残す検出手段：正しいhost内でテストが実行されたこととfixtureの原文反映は残す。UITextViewに直接設定するだけの検査はsim-use入力を保証しないが、fixture自体の配線退行は検出するので無条件の全削除はしない。

費用との比較：速度効果は僅少。fixtureの目的を1本で表す整理。

### U01 MVP UIに残る古いピンセクション仕様

対象：[check-mvp-ui.py:257](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L257)。

実施：古い独立ピンセクション要求と結果申告を削除。現在のfilterと検索から一覧への復帰を確認する。

監査時の判断：「ピン留め済み」独立セクションを必須にするassertionとpinned_sectionという結果申告を削除する。

失う保証・残す検出手段：現行LibraryScreenはallを使用順で表示し、ピンは専用filterで絞る。古いassertionは正しい現行実装を失敗にする。ピン状態の更新とpinned filterだけを残す。これは実行で再現した失敗ではなく、現行sourceと仕様の不一致を静的に確認したもの。

費用との比較：仕様変更に追従していないテストによる誤失敗を除去。

### U02 Reduce Motion開始時の映像採取の二重実行

対象：[check-about-ui.py:162](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-about-ui.py#L162)。

実施：Reduce Motionでのcold start撮影1枚を残し、7回の重複採取を直後のplaybackへ統合した。

監査時の判断：reduced専用の7回×2.1秒のループを削除し、同じ設定のまま直後に走るflow.playback()の2周期採取に集約する。起動直後の1枚は残す。

失う保証・残す検出手段：Reduce Motion有効のcold startと継続再生の証跡は両方残る。同じdataに対するplayback control不存在の再判定もcheck_illustrationと重複するので外す。

費用との比較：enabledで実行した場合、コード上の固定待機14.7秒と7枚の重複撮影を削減可能。実ランタイムの実測値ではない。

### U03 全画面巡回の文字サイズ最小設定

対象：[check-interface-ui.py:66](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-interface-ui.py#L66)。

実施：全画面の最小文字巡回を削除。通常設定と最大文字・高contrastで比較し、hosted modifierテストではextraSmallを残す。

監査時の判断：default／最大文字＋高contrast／最小文字の3巡回から、最小文字の全巡回を外す。RowComparisonのfixedInterfaceIgnoresInheritedTextAndContrastTraitsではextraSmallを残す。

失う保証・残す検出手段：各画面へのNibbleInterface適用漏れはdefaultと最大設定の比較で検出し、modifierそのものが小さい入力も固定することはhostedテストで検出する。同じ全画面を最小設定でも巡る追加価値は低い。

費用との比較：全4画面への操作・撮影1巡を削減。hosted側も同時にextraSmallを削除してはいけない。

### U04 MVP UIの同じ条件の再assertionと再操作

対象：[check-mvp-ui.py:144](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L144)、[check-mvp-ui.py:225](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L225)、[check-mvp-ui.py:247](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L247)、[check-mvp-ui.py:253](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L253)、[check-mvp-ui.py:337](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L337)。

実施：setup後のOS再判定、wait直後の再assertion、同じ検索語の再入力、変更なしeditor往復を削除した。

監査時の判断：Run.setup後の同じOS確認、wait_uiが満たしたpin／undo条件の即時再判定を削除。検索をclearして同じ語を入れ直すだけの往復、変更せずeditorを再度開いて閉じる寄り道も削除候補。

失う保証・残す検出手段：wait自体、実OS入力、編集後の原文copyは残す。clear検索は後続の不一致検索・trash移動で、変更なしeditorのdraft破棄はclosingAnUnchangedEditorDoesNotLeaveADraftで残る。画面配線を確認する主要なopen／closeはシナリオ中に残す。

費用との比較：長いUIシナリオの操作数・偶発的失敗点を減らす。waitの後の同一assertionは固有の不具合を検出しない。

### U05 MVPから説明画面への寄り道

対象：[check-mvp-ui.py:287](https://github.com/9uiLe/nibble/blob/bf8b29fada889c4d9110f39a62a59b303f84ea37/scripts/check-mvp-ui.py#L287)。

実施：MVPのAbout寄り道を削除。製品手順にAbout・interface driverの対象責務を記載した。

監査時の判断：settingsの操作位置変更はMVPに残し、Aboutへ入って撮影して戻る部分はcheck-about-ui／check-interface-uiの説明画面確認へ集約する。

失う保証・残す検出手段：説明画面への導線が壊れた場合を既存専用driverが検出する。これらは別コマンドなので、MVPだけ実行する変更の保証まで同じだとは扱わない。実行対象の規則に説明画面専用driverを残した場合に削除する。

費用との比較：同じ画面遷移と画像レビューの反復を削減。

## 検証記録

基点の製品テストはiOS 26.5・Releaseで118定義成功、Swift Testingが報告したテスト実行時間は10.896秒だった（ビルド時間を含まない）。単独の検索計測が3.432秒、実時間の通知期限が2.100秒を占めた。PythonはNixのlock環境で156メソッド成功・skipなし、2.865秒だった。いずれも1回の観測である。

変更後の製品テストは101定義成功、同じ端末・Releaseで5.614秒。通知期限の統合先は0.007秒、表示入力を追加したmounted rowは2.629秒だった（変更前1.833秒）。Pythonは146メソッド成功・skipなし、1.970秒。各1回の比較なので通常の揺らぎを含み、恒常的な高速化率や不安定さの改善率を保証する値ではない。検証hostは2定義から1定義へ統合し、原文反映まで成功した。

単独store benchmarkは10,000スニペット・200下書きで6回完了した。baseline/final各3回、順序はbaseline→final→final→baseline→baseline→final。同じseed・専用端末・`-Osize`を使い、11個の製品ソースhashが両variantで一致した。製品コードは変更していないので、これは計測入口の成立確認であり製品性能改善の根拠にはしない。

UI driverの実行・最終コミットとの照合結果は検証後に追記する。必要な入口は[製品手順](mvp.md)と[検証fixture手順](ios-verification.md)、PRの照合条件は[証跡とPRの検査](review-evidence.md)に従う。
