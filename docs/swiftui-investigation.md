# SwiftUIの状態・応答・レイアウトの評価記録

## 目的と評価対象

本書は、nibbleの画面、画面間のデータ共有、非同期処理、共通UIを2026-09-18に評価した記録である。採用する構成と状態の契約は[製品設計](decisions/0002-mvp-app.md)、要素の目的と配置は[UI設計](design/README.md)、計測の成立条件は[性能検証の手順](performance-verification.md)に定義する。

本書では対象ソースを次の記号で識別する。テストや画面結果を、別の対象ソースへ無条件に引き継がない。

| 記号 | コミット | 評価上の役割 |
| --- | --- | --- |
| A | `80ceb6cecc5a9489d189fdba34b2c4cbfa9caf76` | 状態・応答の比較対象 |
| B | `4a1f0cb9ff2f9995709e6d74214a30c8aea1adfa` | 取得の完了結果と編集要求IDを持つ構成。モデル測定と共有取込の実行対象 |
| C | `f14c5008008b44ea6ca25c67ceeb685775ec0522` | 本体の編集シートをシーンのルートが提示する構成。製品テストと本体UIの受け入れ対象 |

対象CではRelease製品テスト72件、標準UI操作、一覧・検索の編集途中の背景復帰、小画面での固定表示と入力保持を確認した。共有取込とモデル測定は対象Bで実行した。描画時間・hitch・GPU・合成時間、横向き・RTL、VoiceOverの実操作は未評価である。

## 環境と記録の読み方

Xcode 26.5（17F42）、Swift 6.3.2、iOS 26.5（23F77）Simulatorを使用した。全アプリのdeployment targetは26.0、Swift language modeは6。本体・共有拡張・ResearchProbeはstrict concurrency complete、default isolation nonisolated。VerificationAppは明示的なMainActorクラスとSwift 6の設定を使う。RivePresentationはSwift tools 6.0、iOS 26.0、rive-ios 6.27.0。

| 専用端末 | UDID | 用途 |
| --- | --- | --- |
| iPhone 17 Pro | `D099A849-386F-4EAE-AE12-02D8DC623AF2` | Releaseテスト、標準操作、共有取込、モデル計測 |
| iPhone SE（第3世代） | `517ADFEE-F4CE-462A-987E-4040701A80C4` | 375×667 ptの小画面、固定表示、長文入力、背景復帰 |

1回の検証実行をrunと呼ぶ。`artifacts/ios/<run>/manifest.json`が入力ファイル・端末・コマンド・成否・媒体を記録し、開始・終了の入力をコミットと照合する。本体と共有拡張は同じApp Groupを使うad-hoc署名で実行した。生ログと媒体はGit管理対象外で、新しいcheckoutには含まれない。

「静的確認」はコードと依存関係の確認、「操作成功」はdriverによる操作と値の照合、「視覚確認」は実際に開いた画像・フレームの観察を指す。これらは独立した保証範囲を持つ。

## 調査範囲

製品本体、共有拡張、所有する共通UIとRive表示層、検証・研究用ターゲットのUI接続を確認した。表の静的確認は対象Cの構成に対するものである。実行対象にBを使った箇所は明記する。

| ターゲット・範囲 | 状態・処理・接続 | 状況 |
| --- | --- | --- |
| Nibble: LibraryView | シーン内の一覧・検索モデル、タブ、検索フォーカス、編集・削除一覧sheet、URL、privacy cover | 静的・通常UI・一覧と検索の編集途中の背景復帰を確認。表示時・復帰時・sheet終了時に再取得。複数シーンはInfo.plistで無効 |
| LibraryScreen | requestとsnapshot、フィルター、追加取得、削除確認、画面Task所有者 | 静的・モデル回帰・通常UIを確認。編集の提示元はルート。中断後の再開ボタンはモデル状態と実装を照合し、実画面への中断注入は未実施 |
| SnippetRow / SnippetRowContent | UUIDのidentity、値入力、コピー・整理intent、比較ゲート | 静的確認済み。画面モデルは行の内部で参照しない |
| LibraryFilterBar / LibraryNotice | 選択Binding、通知ID・期限、読み上げ・触覚 | 静的確認済み。通知のObservation依存は独立View内 |
| SnippetEditor / EditorModel | sheetごとの入力snapshot、連番、保存・保持・破棄、フォーカス、FinishOperation | 静的確認済み。入場時のDraftは編集セッション初期値。通常の親更新へ同期しない |
| LibrarySettingsView / AboutView / AboutIllustration | AppStorageの左右、静的説明、画面ごとのRiveSession、配色・可視範囲 | 静的・通常幅と狭幅の表示・左右変更を確認。Riveの既存テストは実行。背景停止・複数周期の録画評価は対象Cでは未実施 |
| Shared: SnippetStore / SQLiteDatabase / Schema / Storage | actor接続、同期transaction、上限付きstatement再利用、要約・索引、App Group | 静的確認済み。保存処理とMainActorを分離。大きい本文は一覧へ保持しない |
| NibbleInterface / SceneInterfaceDefaults / LibraryEffects | traitの固定、UIViewのwindow接続、クリップボードとannouncement | 静的確認済み。updateUIViewは空。制約・subviewを再追加しない |
| NibbleShare: ShareViewController | NSItemProvider読込、draft生成、UIHostingController、完了callback | 静的確認と対象Bでの通常の共有取込を実行。await後の離脱判定をコードで確認。遅延providerによる離脱競合は実行未確認 |
| RivePresentation | Worker/Fileと独立Session、runtimeのRepresentable、可視・sceneの再生制御 | 静的確認済み。palette変更時のviewport identity更新はsessionを保持 |
| VerificationApp | UIKit入力・ラベル・反映。同期イベントと固定の縦stack | 静的確認済み。製品とは別fixture。長文・小高さで末尾へ到達できない構成は制約として確認 |
| ResearchProbe | UIKit一覧・検索・編集、SwiftData保存、URL、下書き、privacy cover | 静的確認済み。行ごとの全文filterと同期I/Oは研究用構成。製品の実行経路には入らない |
| ResearchProbe SDKCompileProbe / validation worker・benchmark | compile-only API、保存方式比較、製品保存層の測定 | UIの利用経路を確認。widget等は製品targetではない。測定用データ処理の実行は未確認 |

## 状態と更新依存の評価

| 評価対象 | コードで確認した構造 | 評価上の限界 |
| --- | --- | --- |
| 一覧・検索 | シーンが独立したモデルを保持し、同じ保存層から再取得する。要求と結果の組を照合して反映する | 複数ウィンドウは製品の提供範囲外 |
| 編集提示 | ルートがDraftのUUIDに対応するシートを提示し、シートが入力とフォーカスを保持する | SwiftUI内部の提示処理そのものは解析していない |
| 行 | モデルを渡さず、UUID、512 UTF-8 bytes以内のタイトル、180文字の要約、ピン状態を使う | 比較境界の存在からフレーム時間の改善は推定しない |
| 通知 | 通知・触覚のObservation依存を`LibraryNotice`内に置く。期限は通知IDを照合する | 遷移の滑らかさは連続再生で未評価 |
| 入力 | 入場時のDraftを初期値にし、入力番号付きsnapshotを保存層へ渡す | 1 MB本文のキーボード追従・IME変換確定は未評価 |
| レイアウト | Stack・List・ScrollViewで幅と自然高を解決する。計測値をStateへ戻す循環は製品内にない | 横向き・RTL・ウィンドウサイズ変更は未実施 |
| Rive | ホストがSessionを保持し、配色・可視性・scene状態を表示層へ渡す | 対象Cでの複数周期・背景停止の録画評価は未実施 |
| UIKit接続 | 共有拡張のUIHostingController、trait適用、OS作用、Rive runtimeの表示接続を確認した。trait用のupdateUIViewは空 | 製品のList・入力をUIKitへ置換する比較計測は未実施 |

LibraryPageの区分は取得結果の生成時に決まり、body内でDB検索や全文整形を行わない。Listのフィルターidentityは結果到着時のスクロール初期化に使い、編集シートのidentityとは分離されている。

確認できた整合性の問題は、結果反映の条件と提示の所有者にある。UIKit一覧への置換では同じモデルの競合は解決せず、セル・delegate・サイズ接続の管理が必要になる。UIKit置換による性能上の優位性を示す測定は得ていない。検索のdebounce、軽い派生値のState化、追加の描画キャッシュを正当化する実測も得ていない。

VerificationAppは操作基盤用fixture、ResearchProbeは保存方式・OS連携の比較試作である。ResearchProbeの同期ストア、行ごとのfilter、SQLiteWorkerの意図的なロック待ちは製品へリンクされない。Stores・SDKCompileProbe・SQLiteWorker・StoreBenchmarkの呼出経路は静的確認に限る。

## 整合性の評価ケース

| 優先度 | 条件と問題の根拠 | 対象Cの契約と確認範囲 |
| --- | --- | --- |
| 高 | Aを基礎にした制御付きテストで、読込取消後に進行状態が残り、通常エラーの後着を失敗表示へ反映した | 要求ごとに成功・失敗・中断を持つ。古い取得IDの結果・後始末を採用しない。モデルテストで確認 |
| 高 | Aを基礎にした制御付きテストで、離脱後の編集対象設定・失敗表示を再現した | 提示要求IDを失効させ、取消直後の再入場を受理する。旧成功・旧失敗の後着をモデルと所有者のテストで確認 |
| 高 | タブ内がシートを提示するSEの構成で、ホーム移動時に同じモデルのeditor Bindingがnilになった | ルートがシートを提示する。一覧・検索それぞれの背景復帰と入力・保存・コピーを対象Cの操作で確認 |
| 中 | 共有の下書き作成後に離脱を確認しない場合、awaitから戻ったホストへUIを追加できる | 読込後・作成後・失敗時にキャンセルを確認する。コードと対象Bの通常取込を確認。遅延providerを使う離脱競合は実行未確認 |

問題の優先度は、入力文脈や操作結果への影響と利用先の数に基づく。実利用での発生率は測定していない。保存層に受理された書込の確定と、離脱後のUI反映を別の契約として評価する。

### 編集シートの提示条件

SEの長文編集で、タブ内提示の構成ではホーム移動後にシートが閉じる現象を2回観察した。下書きから入力を復元できたが、同じ編集画面は維持されなかった。

| 診断run | 構成と観測 |
| --- | --- |
| `20260918T044735Z-swiftui-layout-d45f5f` | モデル生成とeditor Bindingを記録する診断用ソース。同一PID・同一モデルで背景移行時にeditorがnilになる |
| `20260918T045156Z-swiftui-layout-27a16d` | ルートがシートを提示する試作。復帰後も同じ入力を保持し、コピーのUTF-8が一致する |

ログは`artifacts/presentation-trace.log`と`artifacts/root-presentation-trace.log`。診断用ソースは各runのmanifestで識別し、対象Cに一時ログは含めない。観測から特定した条件は提示元と背景移行の組み合わせであり、SwiftUI内部の原因を断定するものではない。

## 製品テストと共通検査

iPhone 17 ProのRelease構成で実行した。取消後の成功・通常エラー、取消直後の再入場、新しい提示後の旧結果、既存下書きの再開取消、フィルター変更後の中断・再開は、checked continuationで完了順を制御して検査した。

| run | 対象 | 結果 |
| --- | --- | --- |
| `20260918T035618Z-test-f27d0c` | Aの動作を基礎に、読込制御点と不具合を検出するテストを加えた診断用ソース | 67件成功、2件失敗。読込中の残留、離脱後の提示・エラーを検出 |
| `20260918T040508Z-test-a3c95d` | B | 72件成功、失敗・skipなし。パラメータ展開後78実行 |
| `20260918T050040Z-test-090ce8` | C | 72件成功、失敗・skipなし。パラメータ展開後78実行 |

保存・同時操作・原文保持・通知期限・マウント済みViewの比較と表示設定・Rive接続のテストを含む。遅延providerや画面上の読込中断を注入するUIテストの成功を示すものではない。

対象Cの評価に対応する`nix flake check --no-update-lock-file --print-build-logs`は7検査が成功した。製品補助ツールのPythonテスト101件、共通UI設計ツール35件、Swift規約、Rive生成契約、文書・設計照合を含む。ログは`artifacts/nix-check-audit-final.log`。この結果はiOS操作や描画性能の保証とは分けて扱う。

## UI操作と画面間のデータ共有

全runはRelease、iOS 26.5（23F77）。表の対象は開始・終了の製品入力との照合先である。

| run | 対象・端末 | 確認した操作と結果 |
| --- | --- | --- |
| `20260918T040828Z-mvp-ui-f2d9ea` | B・iPhone 17 Pro | 作成、下書き再開、保存、検索、編集、コピー、ピン、削除・Undo、破棄、左右設定と再起動、About、削除一覧の検索・復元が成功。原文UTF-8と復元UUIDを照合 |
| `20260918T042013Z-fixed-interface-61e631` | B・iPhone SE | 通常・AXXXL/高コントラスト・XS/標準設定で一覧、編集、設定、Aboutの対象要素の位置比較が成功。設定を復元 |
| `20260918T042743Z-swiftui-share-480e9b` | B・iPhone 17 Pro | Safariから共有し、編集・保存して共有元へ戻り、本体でコピー。App Group、本体反映、UTF-8一致を確認 |
| `20260918T045528Z-mvp-ui-51531a` | C・iPhone 17 Pro | 標準操作と、一覧・検索の編集途中の背景復帰が成功。入力、保存後の原文コピー、削除・復元、設定・Aboutを確認 |
| `20260918T050932Z-fixed-interface-1420c0` | C・iPhone SE | 固定表示3条件と長いタイトル・120行本文のキーボード表示・背景復帰が成功。4画面の対象要素の位置と本文8,889 bytesを照合。設定を復元 |

AXはアクセシビリティ要素から取得した値・位置を指す。AXXXLとXSはOSの文字サイズ設定であり、製品の固定表示方針が保たれる条件として使った。VoiceOverの実操作とは区別する。

### 画像と録画の観察範囲

次の画像と抽出フレームを実際に開いた。確認方法、原本のhash、観察範囲は各runの`review.json`へ記録した。

| run | 開いた画像 / 動画の長さと抽出時刻（秒） | 観察 |
| --- | --- | --- |
| `20260918T040828Z-mvp-ui-f2d9ea` | 17枚中7枚 / 179.177、8.238・89.678・160.617 | 一覧、入力、検索、0件、設定、About、削除一覧。余白と操作領域、キーボード上の0件案内 |
| `20260918T042013Z-fixed-interface-61e631` | 12枚中4枚 / 52.530、2.948・26.605・47.277 | 狭幅の一覧・編集・About。本文・演出・説明の順序 |
| `20260918T042743Z-swiftui-share-480e9b` | 編集と本体の2枚 / 344.245、2.220・95.650・330.563 | 共有編集と本体。コピー通知の途中フレームに文字の重なりがあり、停止画像では残らない |
| `20260918T045528Z-mvp-ui-51531a` | 背景復帰後の編集2枚と完了一覧 / 193.767、9.240・96.930・174.525 | シートと入力の保持、保存・閉じる、検索とキーボード、削除一覧の0件案内 |
| `20260918T050932Z-fixed-interface-1420c0` | 14枚中6枚 / 53.105、1.872・26.627・47.040 | 通常/AXXXL一覧、XS設定、AXXXL About、長文編集の背景移行前後。タイトルの折り返しと操作領域 |

全編再生とfps評価は未実施。対象Cの本体・小画面と対象Bの共有の画像11枚・録画3本は[PR #22](https://github.com/9uiLe/nibble/pull/22)へ添付し、2026-09-18にログイン済みリポジトリ所有者のChromeで読み込みを確認した。通知遷移の滑らかさは合格と判定していない。長文編集の画像で見える本文は数行であり、末尾へのスクロールやIME変換確定を確認した結果にはしない。

### 公開媒体と原本の対応

画像はiPhone 17 Proが1206×2622、小画面が750×1334で読み込まれた。動画3本は`readyState=4`、`error=null`を確認した。これは読込確認であり、全編再生や未認証ユーザーのアクセスを確認した結果ではない。

| 対象 | 画像 | 画面録画・ブラウザーの表示時間 |
| --- | --- | --- |
| C・本体 | [変更後の基本操作後の一覧](https://github.com/user-attachments/assets/a66dd16e-a085-49a9-9caf-303de741dfb5)、[一覧からの編集で背景復帰した画面](https://github.com/user-attachments/assets/ff6962a0-a802-4ba3-bd57-5b3f3462ef05)、[検索からの編集で背景復帰した画面](https://github.com/user-attachments/assets/332de574-6212-4441-8cfb-0b6395a0d449) | [録画](https://github.com/user-attachments/assets/2be7f3db-106f-4cf5-8885-3e5249df0fca)・193.767秒 |
| C・小画面 | [SEの標準表示](https://github.com/user-attachments/assets/f85ac449-7baa-4136-86dd-b9c70c394160)、[SEのAXXXL高コントラスト表示](https://github.com/user-attachments/assets/b6848007-ba5f-48b9-9c00-f39c14337d53)、[SEの設定](https://github.com/user-attachments/assets/8b32e116-7cb8-48fb-828f-5fab3c84b64e)、[SEのnibbleについて](https://github.com/user-attachments/assets/329d9888-775c-465b-abd4-a42360185309)、[SEの長文編集とキーボード](https://github.com/user-attachments/assets/eb3b32bd-2b4a-417f-b6f2-f7449dd4f6e4)、[SEの長文編集で背景復帰した画面](https://github.com/user-attachments/assets/1abf44b7-df80-4ec5-a37f-543c7b6ded8d) | [録画](https://github.com/user-attachments/assets/5bd6d7df-7609-4781-a8d5-a84f4b4e2312)・53.105秒 |
| B・共有 | [共有拡張の編集画面（対象B）](https://github.com/user-attachments/assets/12664cbd-36b0-44c3-b6c0-2d0e6cbaac4e)、[共有保存後の本体一覧（対象B）](https://github.com/user-attachments/assets/f8b29e55-3a14-4c75-aa63-0afb1195de19) | [録画](https://github.com/user-attachments/assets/3f2a968b-7525-4b51-bdc5-a22ac772c200)・344.245秒 |

本体録画の原本は119,255,819 bytesで、GitHubの動画上限100 MBを超える。Apple標準の`avconvert --preset Preset1280x720`で全区間を再圧縮した閲覧用動画（588×1280、60,475,326 bytes）を公開した。原本と閲覧用はともに193.767秒で、区間の切除は行っていない。他の録画とPNGは原本を添付した。

| 本体録画 | SHA-256 |
| --- | --- |
| 原本 | `ca6668bd8752ae337f35be3eb672f1b95e89f0a926a3dc3c922cf13258b90428` |
| 閲覧用 | `d9abfbbe6ba972a13a996e80534c2d82272decdaa96f2c500e7156e806b5cf80` |

閲覧用の9.207・96.857・174.588秒も画像で開き、ホーム、検索、0件案内の表示を確認した。再圧縮によりフレームの抽出時刻と画質は原本と異なる。原本の実行入力・媒体hashの照合と、公開媒体の変換・閲覧確認は独立した記録であり、公開先とのバイト一致を自動検査したものではない。対応は`artifacts/pr-media/publication.json`と各runの`review.json`に記録した。

### 完了しなかった操作・診断run

失敗runは保存し、成功件数へ含めない。

| run | 失敗した段階と確認できたこと |
| --- | --- |
| `20260918T042330Z-swiftui-share-70b8a8` | 保存直後の画面遷移中にAXを取得し、共有元の要素を取得できなかった。独立した再取得ではSafari復帰を確認。成功した共有runは画面到達を待つdriverで実行 |
| `20260918T044121Z-swiftui-layout-479d72` | 保存直後にAX要素が一時的に空となり、全導線の検証を完了できなかった |
| `20260918T043427Z-swiftui-layout-e6290f` / `20260918T043712Z-swiftui-layout-c3cf9b` | キーボードによる位置変化と編集メニューの取得でペースト操作が失敗。成功runは標準の「本文の末尾にペースト」を使用 |
| `20260918T044654Z-swiftui-layout-0135d1` / `20260918T045100Z-swiftui-layout-363819` | 診断用ビルドのコンパイル失敗。製品の実行結果として扱わない |

## モデル処理の同条件比較

比較対象はAとB。`artifacts/measure-library.py`で独立したSimulator実行ファイルを生成し、両方にSwift 6、strict concurrency complete、`-Osize`、whole module optimizationを適用した。対象Cの測定対象モデル・保存層はBと同一である。

1万件の保存済み項目（ピン50件）と下書き200件の同じDBを各プロセスへ複製し、A / B / B / A / A / Bの順で実行した。各操作はウォームアップ後100回、各版3プロセス。表は合計300回の中央値とp95である。

| `LibraryModel.refresh`の要求 | A 中央値 / p95（ms） | B 中央値 / p95（ms） |
| --- | --- | --- |
| すべて（100件・下書き3件） | 0.167 / 0.199 | 0.163 / 0.192 |
| 検索一致（100件） | 0.174 / 0.190 | 0.168 / 0.196 |
| 検索0件（1万件走査） | 3.973 / 4.858 | 3.838 / 4.181 |
| ピン（50件） | 0.082 / 0.099 | 0.085 / 0.104 |
| 下書き（100件） | 0.407 / 0.484 | 0.405 / 0.527 |

終了時のphysical footprintはAが11,113,728〜11,146,496 bytes、Bが11,130,112〜11,146,496 bytes。これはモデル・SQLite・ライブラリを含む計測プロセスの値で、Nibbleの描画メモリではない。この条件では状態管理に伴う大きな負荷増加を観測していないが、処理時間の差を高速化率と解釈しない。

`artifacts/performance/library-comparison/results.json`にソース・harnessのhash、compileコマンド、端末、全サンプルを保存した。測定にはDB取得とMainActorへの反映を含み、View生成・body・レイアウト・描画・スクロールを含まない。

## Instrumentsと未取得の指標

[Instrumentsの診断記録](instruments-diagnosis.md)で、SimulatorのCPU計測サービス生成失敗を確認した。最小Cプログラムでも同じ開始待ちを再現している。Mac上の対照試験では有効なtraceを取得できたが、Simulatorの製品計測は成立していない。

body時間、hitch、GPU・合成時間、入力から表示までの遅延は未取得である。[性能検証の手順](performance-verification.md)で対象サンプルの存在を確認してから、同じDBと操作の製品比較を行う。

## 未確認条件と再評価方法

| 対象 | 未確認の理由・範囲 | 再評価する条件 |
| --- | --- | --- |
| 横向き・RTL・ウィンドウサイズ変更 | SimulatorアプリのUI接続がタイムアウトし、回転を操作できなかった。製品はiPhone向けで複数ウィンドウを提供しない | 編集のキーボード、検索、削除確認、About末尾を確認。RTLは言語・方向設定と左右操作設定を組み合わせる |
| CPU・描画・hitch | Instrumentsの記録が成立しない | 接続・保存・export確認後、起動・検索・入力・スクロール・背景復帰を同条件で測定 |
| 中断と離脱競合の実画面 | モデルテストとコード照合まで。`library.resumeLoading`の画面、遅延providerのUI競合は未実行 | 読込を制御する検証構成で、中断・再入場・旧結果の後着を発生させる |
| VoiceOver・日本語IME・長文入力 | 読み上げ順、変換確定、1 MB本文のキーボード追従は未実施 | 実操作で順序、確定前後の本文、フォーカスと応答を確認 |
| 配色と通知遷移 | 全配色条件・通知の連続再生は未評価 | ライト・ダークと代表状態を操作・録画で確認 |
| Rive | 通常表示とテストまで。対象Cの複数周期、Reduce Motion変更、画面外・背景停止の録画は未実施 | 同じSessionの停止・復帰と表示を複数周期で確認 |
| 検証・研究アプリ | 呼出経路とUIKit構成の静的確認まで | 各専用手順で実行する。製品テストの成功を流用しない |
| 外部依存・実機条件 | 外部ライブラリ内部の網羅調査、実機fps・電力・署名配布は評価範囲外 | 必要な依存と実機条件を個別の検証対象として定義する |

## 一次資料

確認日: 2026-09-18。実装判断はローカルXcode 26.5のAPIと照合する。

- [SwiftUIの性能分析](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): 評価時間・更新頻度・レイアウトと描画の区別。
- [InstrumentsによるSwiftUI最適化](https://developer.apple.com/videos/play/wwdc2025/306/): 更新依存とrender loopの分析。
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html): 協調的キャンセルとactorの中断点。
- [Data race safety](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/): await後に状態が変わることと再検証。
- [Observationとモデル](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app): View内で読む観測対象と依存を対応させる。
- [Layout](https://developer.apple.com/documentation/swiftui/layout): サイズ提案への応答と配置、標準コンテナを優先する判断。
