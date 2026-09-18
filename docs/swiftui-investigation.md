# SwiftUIの状態・応答・レイアウトの調査

## 対象と進め方

比較元は`80ceb6cecc5a9489d189fdba34b2c4cbfa9caf76`。キャンセル境界の修正は`4a1f0cb9ff2f9995709e6d74214a30c8aea1adfa`、編集提示の寿命も修正した最終製品ソースは`f14c5008008b44ea6ca25c67ceeb685775ec0522`。製品本体、共有拡張、所有する共通UIとRive表示層、および検証アプリのUI接続を調べた。外部依存と生成したRiveアセットは直接変更していない。固定文字・配色・演出、読み上げの意味、iOS 26.0以上の対応を維持する。

1. ターゲット、状態と操作の経路、更新依存、identityを棚卸しする。
2. 完了順・キャンセル・画面間の再取得を制御した回帰テストで、整合性の問題を確認する。
3. 確認した原因を修正し、共通UIの利用先を回帰検証する。
4. Releaseの操作・狭幅・キーボードを確認し、横向き・RTL・Time Profilerなど実行できなかった条件と再確認手順を記録する。

## 環境

Xcode 26.5（17F42）、Swift 6.3.2、iOS 26.5 Simulatorを使用する。全アプリのdeployment targetは26.0、Swift language modeは6。本体・共有拡張・ResearchProbeはstrict concurrency complete、default isolation nonisolated。VerificationAppは明示的なMainActorクラスとSwift 6の設定を使う。RivePresentationはSwift tools 6.0、iOS 26.0、rive-ios 6.27.0。

## 棚卸しと確認状況

「静的」は対象コードと依存先を読んだことを示す。実行・視覚・性能の確認とは区別する。

| ターゲット・範囲 | 状態・処理・接続 | 状況 |
| --- | --- | --- |
| Nibble: LibraryView | シーン内の一覧・検索モデル、タブ、検索フォーカス、編集・削除一覧sheet、URL、privacy cover | 静的・通常UI・一覧と検索の編集途中の背景復帰を確認。表示時・復帰時・sheet終了時に再取得。複数シーンはInfo.plistで無効 |
| LibraryScreen | requestとsnapshot、フィルター、追加取得、削除確認、画面Task所有者 | 静的・モデル回帰・通常UIを確認。編集の提示元はルート。中断後の再開ボタンはモデル状態と実装を照合し、実画面への中断注入は未実施 |
| SnippetRow / SnippetRowContent | UUIDのidentity、値入力、コピー・整理intent、比較ゲート | 静的確認済み。画面モデルは行の内部で参照しない |
| LibraryFilterBar / LibraryNotice | 選択Binding、通知ID・期限、読み上げ・触覚 | 静的確認済み。通知のObservation依存は独立View内 |
| SnippetEditor / EditorModel | sheetごとの入力snapshot、連番、保存・保持・破棄、フォーカス、FinishOperation | 静的確認済み。入場時のDraftは編集セッション初期値。通常の親更新へ同期しない |
| LibrarySettingsView / AboutView / AboutIllustration | AppStorageの左右、静的説明、画面ごとのRiveSession、配色・可視範囲 | 静的・通常幅と狭幅の表示・左右変更を確認。Riveの既存テストは実行。背景停止・複数周期の録画評価は今回未実施 |
| Shared: SnippetStore / SQLiteDatabase / Schema / Storage | actor接続、同期transaction、上限付きstatement再利用、要約・索引、App Group | 静的確認済み。保存処理とMainActorを分離。大きい本文は一覧へ保持しない |
| NibbleInterface / SceneInterfaceDefaults / LibraryEffects | traitの固定、UIViewのwindow接続、クリップボードとannouncement | 静的確認済み。updateUIViewは空。制約・subviewを再追加しない |
| NibbleShare: ShareViewController | NSItemProvider読込、draft生成、UIHostingController、完了callback | 静的確認と通常の共有取込を実行。await後の離脱判定を追加。遅延providerによる離脱競合は実行未確認 |
| RivePresentation | Worker/Fileと独立Session、runtimeのRepresentable、可視・sceneの再生制御 | 静的確認済み。palette変更時のviewport identity更新はsessionを保持 |
| VerificationApp | UIKit入力・ラベル・反映。同期イベントと固定の縦stack | 静的確認済み。製品とは別fixture。長文・小高さで末尾へ到達できない構成は制約として確認 |
| ResearchProbe | UIKit一覧・検索・編集、SwiftData保存、URL、下書き、privacy cover | 静的確認済み。行ごとの全文filterと同期I/Oは研究用構成。製品の実行経路には入らない |
| ResearchProbe SDKCompileProbe / validation worker・benchmark | compile-only API、保存方式比較、製品保存層の測定 | UIの利用経路を確認。widget等は製品targetではない。測定用データ処理の実行は未確認 |

## 主要フローと所有権

- 検索・フィルター: UIがrequestを更新し、画面のTask所有者が取得を置換する。SnippetStoreのactorで一貫した要約を作り、MainActorで要求・世代を照合してsnapshotへ反映する。フィルター変更中は古い一覧を操作不可で保持する。
- 行操作: UUIDとintentを画面が受け、有限の書込はシーン寿命で完了を待つ。同じ操作・対象の連打を抑止し、コピー・検索は最新を優先する。
- 編集: シーンのルートが提示を所有し、シート内で編集モデルを保持する。入力はメモリと連番のみ更新し、`.task(id:)`が下書きの不変snapshotを渡す。受理した書込は完了し、連番とtransactionが古い書込・復活を防ぐ。保存・保持・破棄は入力を凍結し、成功したときだけ閉じる。
- 画面共有: 本体のstoreはアプリが所有する。一覧と検索は選択・snapshotを独立に持ち、再表示・復帰でDBを読む。共有拡張は別接続から同じApp Group DBへ書き、本体復帰で反映する。
- 説明演出: AboutIllustrationがSessionを所有し、RiveCanvasが可視・scene状態をruntimeへ渡す。演出から業務データを変更しない。

## 問題と採否

| 優先度 | 問題候補・根拠 | 影響・方針 |
| --- | --- | --- |
| 高 | LibraryModel.openはDB await後にキャンセルを確認せずeditorを設定する | 修正前のテストで再現。要求IDを導入し、離脱後の提示と旧要求の失敗を防ぐ。取消直後の再入場を受理する |
| 高 | refreshのcancel catchは完了状態を確定せず、通常エラーが後着すると中断を失敗表示にする | 修正前のテストで再現。成功・失敗・中断を区別し、同じ要求の再開とsnapshot保持を実装 |
| 高 | タブ内のLibraryScreenが編集シートを提示し、背景移行でsheetのBindingがnilになる | SEで再現。同じモデルのまま提示が閉じることを専用ログで確認。提示元をLibraryViewへ移し、タブ内容と編集シートの寿命を分離 |
| 中 | ShareViewControllerはdraft作成後に離脱を再確認しない | await後のキャンセル確認を追加。受理した共有本文を残し、離脱後のView・alert追加を防ぐ。拡張内の遅延競合の実行再現は未実施 |
| 維持 | 検索の各入力で即時SQL取得、編集で各snapshotを永続化 | 同条件モデル計測で負荷増加は小さい。入力応答の実測は未取得のため、debounceや保存方式の変更は導入しない |
| 維持・一部未確認 | 通知の横並び・編集の自然高・ナビゲーション固定幅 | 通常幅と狭幅の静止状態を確認。固定高さの追加やUIKitへの置換を正当化する根拠は得ていない。横向き・RTL・遷移の滑らかさは未評価 |

編集提示の問題は通常のホーム移動で再現し、一覧・検索の両方へ影響するため優先した。読込・編集開始の競合は遅い旧要求と離脱が重なる条件に限られるが、表示と操作の整合性を失う。要求IDと終了状態に変更を限定し、完了順を制御するテストでリスクを抑えた。共有拡張の修正はawait直後の表示判定だけに限定し、保存済み下書きを破棄しない。実利用での各問題の発生率は計測していない。

## 性能の評価単位

View値生成、body評価、レイアウト、描画・合成を区別する。関数・computed propertyへの移動は依存の分離にならない。現状は行表示値の比較ゲート、生成時に区分済みのLibraryPage、最大180文字の要約、通知だけを読むViewを使う。これらの構造だけからfpsや改善率を主張しない。

SwiftUIの状態・identityの修正が第一候補。UIKit一覧への置換では、同じモデルの競合は解消せず、セル状態・delegate・サイズ接続の管理が増える。標準SwiftUI入力・Listでの問題が計測できた範囲に限りUIKitを比較する。既存のUIKit接続は共有拡張とtrait適用に限定する。

### 更新依存と再計算

| 範囲 | 読み取る状態と計算 | 判断 |
| --- | --- | --- |
| ルート | タブ、検索focus、左右設定、scene、一覧と検索のeditor。二つのモデルはStateでシーン中保持 | タブ変更でモデルを再作成しない。共有する永続データと独立した検索条件を区別し、編集提示をタブ内容から独立させる |
| 一覧 | request、snapshot、読込・失敗。区分はLibraryPageの生成時に確定 | bodyでDB検索・全文整形をしない。filterのidentity変更は結果到着時のスクロール初期化という仕様 |
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
| `20260918T040508Z-test-a3c95d` | キャンセル境界の修正後72テスト成功、失敗・skipなし。パラメータ展開は78実行 |
| `20260918T050040Z-test-090ce8` | 最終製品コミットで72テスト成功、失敗・skipなし。パラメータ展開は78実行 |

追加した検査は、取消後に成功・通常エラーが届く場合、取消直後に別所有者から再入場する場合、新しい提示後に旧結果が届く場合、既存下書きの再開取消、フィルター変更後の中断と再開を扱う。checked continuationで完了順を決め、待ち時間に依存せず再現する。通常の保存、同時操作、原文保持、通知期限、mounted Viewの比較・表示設定、Riveの既存テストも実行した。

共通の`nix flake check --no-update-lock-file --print-build-logs`は7検査が成功した。Pythonの製品補助ツール101件と共通UI設計ツール35件、Swift規約、Rive生成契約、文書・設計照合を含む。`artifacts/nix-check-audit-final.log`に記録する。iOSの成功とクラウドで実行可能な検査の成功は別々に評価する。

## UIと画面間の連携

すべてRelease、iOS 26.5（23F77）。最初の3runは`4a1f0cb9ff2f9995709e6d74214a30c8aea1adfa`、以降は`f14c5008008b44ea6ca25c67ceeb685775ec0522`と照合する。本体と共有拡張は同じApp Groupでad hoc署名した。各runは`artifacts/ios/`に保存し、開始・終了の入力を製品ソースと照合する。

| run | 端末・確認した操作 | 結果 |
| --- | --- | --- |
| `20260918T040828Z-mvp-ui-f2d9ea` | iPhone 17 Pro。作成、下書き再開、保存、検索、編集、原文コピー、ピン、削除・Undo、破棄、左右設定と再起動、About、削除一覧の検索・復元 | 標準driver成功。日本語・結合文字・絵文字・空白・改行を含むUTF-8と、復元したUUIDを照合 |
| `20260918T042013Z-fixed-interface-61e631` | iPhone SE（第3世代）、375×667 pt。通常・AXXXL/高コントラスト・XS/標準設定で一覧、編集、設定、About | 固定表示ポリシーのAX frame比較が成功。終了時に設定を復元 |
| `20260918T042743Z-swiftui-share-480e9b` | iPhone 17 Pro。Safariから共有拡張を開き、編集・保存して共有元へ戻り、本体へ復帰してコピー | 取込、App Group、共有元復帰、本体反映、原文UTF-8一致を確認 |
| `20260918T045528Z-mvp-ui-51531a` | iPhone 17 Pro。標準操作に、一覧・検索それぞれの編集途中の背景復帰を追加 | 成功。復帰後の入力、保存後の原文コピー、削除・復元、設定・Aboutも確認 |
| `20260918T050932Z-fixed-interface-1420c0` | iPhone SE第3世代。固定表示設定3条件と、長いタイトル・120行本文のキーボード表示、背景復帰、コピー | 成功。4画面の対象AX frameが設定間で一致し、復帰後の入力と本文8,889 bytesを照合。OS設定を復元 |

初回の標準UI runは17画像中7画像と179.177秒の動画の3フレーム（8.238 / 89.678 / 160.617秒）、固定表示runは12画像中4画像と52.530秒の動画の3フレーム（2.948 / 26.605 / 47.277秒）を実際に開いた。前者では一覧・入力・検索・0件・設定・About・削除一覧、後者では狭幅の一覧・編集・Aboutを観察した。余白と操作領域の分離、0件案内がキーボードより上にあること、本文・演出・説明の順序を確認した。

共有runでは編集と本体の2画像、344.245秒の動画の3フレーム（2.220 / 95.650 / 330.563秒）を開いた。コピー通知の途中フレームは文字の移動が重なって見えるため、遷移の滑らかさを合格と判定していない。停止後の画像では重なりは残っていない。全編再生、fps評価、媒体の公開・ブラウザー閲覧確認は未実施。原本のhashと具体的な観察範囲を各runの`review.json`に記録した。

最終コードの標準UI runは背景復帰後の編集2画像と完了一覧の画像、193.767秒の動画の3フレーム（9.240 / 96.930 / 174.525秒）を開いた。編集シートと入力の保持、保存・閉じる操作、検索とキーボード、削除一覧の0件案内を確認した。開始・終了の入力と媒体hashは最終製品コミットへの整合性検査が成功した。

共有の最初のrun `20260918T042330Z-swiftui-share-70b8a8`は保存直後のAX取得が画面遷移中に重なり、共有元の要素が見つからず失敗した。その後の再取得ではSafariへの復帰を確認した。補助driverを画面到達までの短いポーリングへ変更し、上記の別runで取込から再検証した。製品コードはこの切り分けでは変更していない。

最終コードの小画面runは14画像中6画像（一覧の通常・AXXXL、XSの設定、AXXXLのAbout、長文編集の背景移行前後）、53.105秒の動画の3フレーム（1.872 / 26.627 / 47.040秒）を開いた。長いタイトルの折り返し、行の省略と操作領域、キーボード表示中の保存・閉じると入力の保持を確認した。表示できる本文は数行であり、長文末尾へのスクロールやIME変換確定の検証とはしない。開始・終了の入力と媒体hashは最終製品コミットと一致した。

### 編集シートの背景移行

SEの補助runで120行の本文と長いタイトルを扱った際、ホームへ移動して戻ると編集シートが閉じる現象を2回観察した。入力は下書きから復元できたが、編集中の文脈は維持されなかった。`20260918T044121Z-swiftui-layout-479d72`は最後の保存直後にAX要素が一時的に空となって失敗しており、全導線成功とはしない。

診断用ビルド`20260918T044735Z-swiftui-layout-d45f5f`では、モデルの生成とeditor Bindingの更新だけを記録した。同一PID・同一モデルで、背景移行時にeditorがnilになった。提示元をタブ内からルートへ移した試作`20260918T045156Z-swiftui-layout-27a16d`では、ホームから戻っても同じ編集シートを維持し、元の本文のコピーもUTF-8で一致した。変更前後のログは`artifacts/presentation-trace.log`と`artifacts/root-presentation-trace.log`。一時的な診断ログは製品コードから削除した。

ここで確かめた原因は、iOS 26.5での提示元の寿命と背景移行の組み合わせである。SwiftUI内部の実装を断定しない。取得や保存のモデルを変更せず、ルートが一覧・検索それぞれのeditor Bindingを提示し、閉じたら元のモデルを再取得する。標準UI driverに一覧・検索の編集途中でホームへ移動し、復帰後のシート・入力値と、その後の保存・原文コピーを照合する工程を加えた。

長文入力の最初の2run（`20260918T043427Z-swiftui-layout-e6290f`、`20260918T043712Z-swiftui-layout-c3cf9b`）は、キーボードによる位置変化とネイティブ編集メニューの取得によりペースト操作が失敗した。後続は標準の「本文の末尾にペースト」を操作し、入力と保存した本文の一致を検査した。診断用ビルドのコンパイル失敗2run（`20260918T044654Z-swiftui-layout-0135d1`、`20260918T045100Z-swiftui-layout-363819`）も成功結果に含めない。

## モデル処理の同条件比較

`artifacts/measure-library.py`が比較元と`4a1f0cb9ff2f9995709e6d74214a30c8aea1adfa`から独立したSimulator実行ファイルを生成する。最終製品コミットでも、測定対象のモデル・保存層は変更していない。Swift 6・strict concurrency complete・`-Osize`・whole module optimizationを両方へ適用した。1万件の保存済み項目（ピン50件）と下書き200件の同一DBを各プロセスへ複製し、baseline / final / final / baseline / baseline / finalの順で測定した。各操作はウォームアップ後100回、各版3プロセス、表は合計300回の中央値とp95。

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

## 残る検証と再確認方法

- 横向き・RTL・ウィンドウサイズ変更: SimulatorアプリのUI接続がタイムアウトし、回転を操作できなかった。復旧後、編集のキーボード表示、検索、削除確認、About末尾を横向きで確認する。RTLはschemeの言語・方向設定で同じ導線と左右操作設定を比較する。製品はiPhone向けで複数ウィンドウを提供しない。
- Instruments: Xcodeで専用Simulatorへ接続してTime Profilerの記録開始を確認し、同じDBと操作で起動・検索・入力・スクロール・復帰を比較する。有効なtraceを取得するまで、body回数、hitch、描画速度の改善は未評価とする。
- キャンセルのUI: 中断・旧要求の後着はモデルテストで再現した。`library.resumeLoading`の実画面と共有拡張の遅延providerは、読込を制御する検証用構成で確認が必要。NSItemProviderのcallback自体は即時停止せず、復帰時のUI反映を抑止する設計である。
- VoiceOverの順序と実操作、日本語IMEの変換確定、1 MB本文のキーボード追従、全配色条件、通知遷移の連続再生は未実施。固定表示の検査をこれらの代替としない。
- Rive: 通常表示と既存テストを確認した。複数周期、Reduce Motion変更、画面外・背景停止の録画再評価は今回の対象ソースでは未実施。既存の記録を今回の実行結果に合算しない。
- VerificationApp / ResearchProbe: 呼出経路とUIKit構成を静的確認したが、今回実行していない。外部ライブラリ内部の網羅調査・直接修正も対象外。実機のfps・電力・署名配布はSimulator評価に含まない。

## 一次資料

確認日: 2026-09-18。実装判断はローカルXcode 26.5のAPIと照合する。

- [SwiftUIの性能分析](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): 評価時間・更新頻度・レイアウトと描画の区別。
- [InstrumentsによるSwiftUI最適化](https://developer.apple.com/videos/play/wwdc2025/306/): 更新依存とrender loopの分析。
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html): 協調的キャンセルとactorの中断点。
- [Data race safety](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/): await後に状態が変わることと再検証。
- [Observationとモデル](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app): View内で読む観測対象と依存を対応させる。
- [Layout](https://developer.apple.com/documentation/swiftui/layout): サイズ提案への応答と配置、標準コンテナを優先する判断。
