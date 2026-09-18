# SwiftUIの状態・応答・レイアウトの調査

## 対象と進め方

比較元は`80ceb6cecc5a9489d189fdba34b2c4cbfa9caf76`。製品本体、共有拡張、所有する共通UIとRive表示層、および検証アプリのUI接続を調べる。外部依存と生成したRiveアセットは直接変更しない。固定文字・配色・演出、読み上げの意味、iOS 26.0以上の対応を維持する。

1. ターゲット、状態と操作の経路、更新依存、identityを棚卸しする。
2. 完了順・キャンセル・画面間の再取得を制御した回帰テストで、整合性の問題を確認する。
3. 確認した原因を修正し、共通UIの利用先を回帰検証する。
4. Releaseの操作、狭幅・横向き・キーボード・RTL、Time Profilerの取得可否と結果を記録する。

## 環境

Xcode 26.5（17F42）、Swift 6.3.2、iOS 26.5 Simulatorを使用する。全アプリのdeployment targetは26.0、Swift language modeは6。本体・共有拡張・ResearchProbeはstrict concurrency complete、default isolation nonisolated。VerificationAppは明示的なMainActorクラスとSwift 6の設定を使う。RivePresentationはSwift tools 6.0、iOS 26.0、rive-ios 6.27.0。

## 棚卸しと確認状況

「静的」は対象コードと依存先を読んだことを示す。実行・視覚・性能の確認とは区別する。

| ターゲット・範囲 | 状態・処理・接続 | 状況 |
| --- | --- | --- |
| Nibble: LibraryView | シーン内の一覧・検索モデル、タブ、検索フォーカス、削除一覧sheet、URL、privacy cover | 静的確認済み。表示時・復帰時・sheet終了時に再取得。複数シーンはInfo.plistで無効 |
| LibraryScreen | requestとsnapshot、フィルター、追加取得、編集sheet、削除確認、画面Task所有者 | 静的確認済み。キャンセル完了と読込状態を検証中 |
| SnippetRow / SnippetRowContent | UUIDのidentity、値入力、コピー・整理intent、比較ゲート | 静的確認済み。画面モデルは行の内部で参照しない |
| LibraryFilterBar / LibraryNotice | 選択Binding、通知ID・期限、読み上げ・触覚 | 静的確認済み。通知のObservation依存は独立View内 |
| SnippetEditor / EditorModel | sheetごとの入力snapshot、連番、保存・保持・破棄、フォーカス、FinishOperation | 静的確認済み。入場時のDraftは編集セッション初期値。通常の親更新へ同期しない |
| LibrarySettingsView / AboutView / AboutIllustration | AppStorageの左右、静的説明、画面ごとのRiveSession、配色・可視範囲 | 静的確認済み。Riveの画面外・背景停止と再入場を実行確認予定 |
| Shared: SnippetStore / SQLiteDatabase / Schema / Storage | actor接続、同期transaction、上限付きstatement再利用、要約・索引、App Group | 静的確認済み。保存処理とMainActorを分離。大きい本文は一覧へ保持しない |
| NibbleInterface / SceneInterfaceDefaults / LibraryEffects | traitの固定、UIViewのwindow接続、クリップボードとannouncement | 静的確認済み。updateUIViewは空。制約・subviewを再追加しない |
| NibbleShare: ShareViewController | NSItemProvider読込、draft生成、UIHostingController、完了callback | 静的確認済み。await後の離脱判定を検証中 |
| RivePresentation | Worker/Fileと独立Session、runtimeのRepresentable、可視・sceneの再生制御 | 静的確認済み。palette変更時のviewport identity更新はsessionを保持 |
| VerificationApp | UIKit入力・ラベル・反映。同期イベントと固定の縦stack | 静的確認済み。製品とは別fixture。長文・小高さで末尾へ到達できない構成は制約として確認 |
| ResearchProbe | UIKit一覧・検索・編集、SwiftData保存、URL、下書き、privacy cover | 静的確認済み。行ごとの全文filterと同期I/Oは研究用構成。製品の実行経路には入らない |
| ResearchProbe SDKCompileProbe / validation worker・benchmark | compile-only API、保存方式比較、製品保存層の測定 | UIの利用経路を確認。widget等は製品targetではない。測定用データ処理の実行は未確認 |

## 主要フローと所有権

- 検索・フィルター: UIがrequestを更新し、画面のTask所有者が取得を置換する。SnippetStoreのactorで一貫した要約を作り、MainActorで要求・世代を照合してsnapshotへ反映する。フィルター変更中は古い一覧を操作不可で保持する。
- 行操作: UUIDとintentを画面が受け、有限の書込はシーン寿命で完了を待つ。同じ操作・対象の連打を抑止し、コピー・検索は最新を優先する。
- 編集: シートがモデルを所有する。入力はメモリと連番のみ更新し、`.task(id:)`が下書きの不変snapshotを渡す。受理した書込は完了し、連番とtransactionが古い書込・復活を防ぐ。保存・保持・破棄は入力を凍結し、成功したときだけ閉じる。
- 画面共有: 本体のstoreはアプリが所有する。一覧と検索は選択・snapshotを独立に持ち、再表示・復帰でDBを読む。共有拡張は別接続から同じApp Group DBへ書き、本体復帰で反映する。
- 説明演出: AboutIllustrationがSessionを所有し、RiveCanvasが可視・scene状態をruntimeへ渡す。演出から業務データを変更しない。

## 優先する確認

| 優先度 | 問題候補・根拠 | 影響・方針 |
| --- | --- | --- |
| 高 | LibraryModel.openはDB await後にキャンセルを確認せずeditorを設定する | 修正前のテストで再現。要求IDを導入し、離脱後の提示と旧要求の失敗を防ぐ。取消直後の再入場を受理する |
| 高 | refreshのcancel catchは完了状態を確定せず、通常エラーが後着すると中断を失敗表示にする | 修正前のテストで再現。成功・失敗・中断を区別し、同じ要求の再開とsnapshot保持を実装 |
| 中 | ShareViewControllerはdraft作成後に離脱を再確認しない | await後のキャンセル確認を追加。受理した共有本文を残し、離脱後のView・alert追加を防ぐ。拡張内の遅延競合の実行再現は未実施 |
| 調査中 | 検索の各入力で即時SQL取得、編集で各snapshotを永続化 | 頻度だけで遅いと断定しない。計測後に採否を決める |
| 調査中 | 通知の横並び・編集の自然高・ナビゲーション固定幅 | 文字・幅・キーボード条件で実際に確認する。根拠なしの固定高さ追加は行わない |

## 性能の評価単位

View値生成、body評価、レイアウト、描画・合成を区別する。関数・computed propertyへの移動は依存の分離にならない。現状は行表示値の比較ゲート、生成時に区分済みのLibraryPage、最大180文字の要約、通知だけを読むViewを使う。これらの構造だけからfpsや改善率を主張しない。

SwiftUIの状態・identityの修正が第一候補。UIKit一覧への置換では、同じモデルの競合は解消せず、セル状態・delegate・サイズ接続の管理が増える。標準SwiftUI入力・Listでの問題が計測できた範囲に限りUIKitを比較する。既存のUIKit接続は共有拡張とtrait適用に限定する。

### 更新依存と再計算

| 範囲 | 読み取る状態と計算 | 判断 |
| --- | --- | --- |
| ルート | タブ、検索focus、左右設定、scene。二つのモデルはStateでシーン中保持 | タブ変更でモデルを再作成しない。共有する永続データと独立した検索条件を区別する |
| 一覧 | request、snapshot、読込・失敗、editor。区分はLibraryPageの生成時に確定 | bodyでDB検索・全文整形をしない。filterのidentity変更は結果到着時のスクロール初期化という仕様 |
| 行 | UUID、最大512文字のタイトルと180文字の要約、ピン、操作位置 | 状態モデルを行へ渡さず、比較対象は表示値だけ。closureを比較ゲートへ含めない |
| 通知 | 通知ID・本文・Undo対象、触覚番号 | 一覧全体に通知の期限処理の依存を持たせない。新しい通知を古い期限で消さない |
| 編集 | Draftとsequence、phase、failure、focus | 入力ごとのsnapshotは保存順序のために必要。文字列比較はUTF-8一致、単なる切り出しやStateキャッシュを追加しない |
| 製品情報 | 静的説明、演出のSession・palette・可視性 | SwiftUIの更新でRiveファイルを再ロードしない。色変更はSessionを維持してviewportへ反映 |

ここで確認したのは依存と処理の配置であり、bodyの呼出回数や実フレーム時間ではない。幅の提案と自然高はStack・List・ScrollViewが解決し、GeometryReaderの計測値をStateへ戻す循環は製品内にない。入力中のfocusと編集データは同じsheetのidentity内に保持する。

### 検証・研究ターゲットの境界

VerificationAppは文字列反映と自動操作のfixture、ResearchProbeは保存方式とOS連携の比較試作である。ResearchProbeの同期ストア・行ごとのfilterと、SQLiteWorkerの意図的なロック待ちは製品へリンクされない。比較実験の条件を変える改造は行わず、製品の性能評価にも流用しない。ResearchProbeのStores、SDKCompileProbe、SQLiteWorker、StoreBenchmarkの呼出経路を静的に確認した。各試作の実行結果を今回確認済みとはしない。

## 回帰テスト

専用iPhone 17 Pro Simulator（`D099A849-386F-4EAE-AE12-02D8DC623AF2`、iOS 26.5 / 23F77）でReleaseテストを実行した。各runのmanifestが開始・終了時のソースhashを記録する。

| run | 条件・結果 |
| --- | --- |
| `20260918T035618Z-test-f27d0c` | 修正前の動作に読込完了の制御点と回帰テストを追加。既存67テスト成功、追加2テスト失敗。読込中の残留、離脱後のeditor設定・エラーを再現 |
| `20260918T040508Z-test-a3c95d` | 修正後72テスト成功、失敗・skipなし。パラメータ展開は78実行 |

追加した検査は、取消後に成功・通常エラーが届く場合、取消直後に別所有者から再入場する場合、新しい提示後に旧結果が届く場合、既存下書きの再開取消、フィルター変更後の中断と再開を扱う。checked continuationで完了順を決め、待ち時間に依存せず再現する。通常の保存、同時操作、原文保持、通知期限、mounted Viewの比較・表示設定、Riveの既存テストも実行した。

## モデル処理の同条件比較

`artifacts/measure-library.py`が比較元と作業中ソースから独立したSimulator実行ファイルを生成する。Swift 6・strict concurrency complete・`-Osize`・whole module optimizationを両方へ適用した。1万件の保存済み項目（ピン50件）と下書き200件の同一DBを各プロセスへ複製し、baseline / final / final / baseline / baseline / finalの順で測定した。各操作はウォームアップ後100回、各版3プロセス、表は合計300回の中央値とp95。

| `LibraryModel.refresh`の要求 | 比較元 中央値 / p95（ms） | 修正後 中央値 / p95（ms） |
| --- | --- | --- |
| すべて（100件・下書き3件） | 0.167 / 0.199 | 0.163 / 0.192 |
| 検索一致（100件） | 0.174 / 0.190 | 0.168 / 0.196 |
| 検索0件（1万件走査） | 3.973 / 4.858 | 3.838 / 4.181 |
| ピン（50件） | 0.082 / 0.099 | 0.085 / 0.104 |
| 下書き（100件） | 0.407 / 0.484 | 0.405 / 0.527 |

終了時のphysical footprintは比較元11,113,728〜11,146,496 bytes、修正後11,130,112〜11,146,496 bytes。これはモデル・SQLite・ライブラリを含む計測プロセスの値で、Nibbleの描画メモリではない。処理時間の差を高速化率と解釈しない。今回の状態遷移修正による大きな負荷増加はこの条件では観測していない。

`artifacts/performance/library-comparison/results.json`にソースとharnessのhash、compileコマンド、端末、全サンプルを保存した。DB取得・MainActorへの反映は含み、View生成・body・レイアウト・描画・スクロールは含まない。実機の60 fps、入力遅延、hitch改善を主張しない。

Time Profilerは専用SimulatorのNibbleに30秒の記録を要求したが、開始待ちのまま制限時間を超え、SIGINTにも応答しなかったため約4分で当該プロセスを終了した。`artifacts/performance/baseline-trace.log`を残し、traceの数値は採用しない。Instrumentsの有効なtrace、body時間、GPU・合成時間は未取得。

## 一次資料

確認日: 2026-09-18。実装判断はローカルXcode 26.5のAPIと照合する。

- [SwiftUIの性能分析](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): 評価時間・更新頻度・レイアウトと描画の区別。
- [InstrumentsによるSwiftUI最適化](https://developer.apple.com/videos/play/wwdc2025/306/): 更新依存とrender loopの分析。
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html): 協調的キャンセルとactorの中断点。
- [Data race safety](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/): await後に状態が変わることと再検証。
- [Observationとモデル](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app): View内で読む観測対象と依存を対応させる。
- [Layout](https://developer.apple.com/documentation/swiftui/layout): サイズ提案への応答と配置、標準コンテナを優先する判断。
