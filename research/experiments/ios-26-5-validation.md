# iOS 26.5での研究項目の実行検証

状態は **一部実施済み**。公開APIのコンパイルと、保存・検索・復旧・画面操作の試作を実行した。実機・署名・利用者・配布構成が必要な項目は未実施として残す。V0〜V8全体の合格や製品構成の採用を意味しない。

- 実施日：2026-09-13
- 基点：`e7f39a4862413fded9928432a0a21407dbbaf6cd`、`research/validate-foundations`の作業ファイル。各`manifest.json`に対象ソースのSHA-256を記録。
- macOS 26.2 / Apple Silicon、Xcode 26.5 (17F42)、Apple Swift 6.3.2、Swift language mode 6、strict concurrency complete、default isolation nonisolated。
- iPhone 17 Pro Simulator `114E57E6-E37D-4F50-907A-8B0B6B03C92E`、iOS 26.5 (23F77)。実行OSは26.5のみ。deployment targetは26.0。
- 対象：`validation/ResearchProbe.xcodeproj` / `ResearchProbe`。製品の保存方式・UIを確定するアプリではない。
- 実機：`devicectl list devices`のiPhone 17は`unavailable`。有効なDeveloper Team、CloudKit試験用の2端末・アカウントは未提供。
- 小画面：iPhone SE (3rd generation) Simulator `A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`、同じ26.5 runtime。確認後にshutdown。
- 再現手順：[研究用の実行検証](../../validation/RESEARCH.md)。公開文書・論文で答えられる問いは [P01〜P13](primary-source-validation.md) を参照。

## 実行して確認した範囲

| ID / 計画 | 期待・条件 | 観測結果 | 適用限界 |
| --- | --- | --- | --- |
| E01 / V3 | SwiftData・Core Data・SQLiteで同じ本文を作成、取得、更新、削除、再open | 3方式で一致。日本語・結合濁点・半角カナ・改行・タブ・絵文字・記号・前後空白を保持 | 本体内の独立接続。extensionのsandboxを試していない |
| E02 / V3 | 作成済みストアをread-onlyで読み、writeを拒否 | 3方式でread成功・write拒否、再open後の保存済み値を保持 | 親ディレクトリが書込可能な条件。Full AccessなしKeyboardの権限とは別 |
| E03 / V3 | 別プロセスのwriter競合、コミット前の強制終了 | 2番目のwriterは`database is locked`。未コミットwriterをSIGKILL後も`original`、integrity checkは`ok` | SQLiteの制御された1回の実験。SwiftData/Core Dataの終了・全障害パターンを網羅しない |
| E04 / V3 | readerのtransaction中に別プロセスで更新 | transaction中は`original`、終了後のreadは`committed` | 明示再読込が必要。通知配送やframeworkの画面更新時間は未測定 |
| E05 / V3 | checkpoint後のSQLiteを書込不可のディレクトリから開く | read-only open・取得成功 | POSIX権限の試験。live WALの全sidecar条件やApp Group権限を保証しない |
| E06 / V3,V5 | 稼働中DBをOnline Backup APIで複製、DB本体だけのcopyとも比較 | Backup APIは本文一致・`integrity_check=ok`。WALを欠く本体だけのcopyはread失敗 | 直接SQLiteのみ。SwiftData/Core Data内部DBへこのbackup方法を適用していない |
| E07 / V3,V5 | SwiftData VersionedSchemaとCore Dataに属性を追加して軽量移行 | ID・本文保持。SwiftDataの新optional titleはnil、Core Dataのtitleは指定defaultの空文字 | 各1→2の単純なschema変更。製品の全既存版、rename、破壊的変更は未定義 |
| E08 / V3 | SwiftData/Core Dataの保存履歴を取得。SwiftData履歴削除後に古いtokenを使用 | 履歴取得成功。古いtokenは`historyTokenExpired`、全件再読込は可能 | token失効時の製品UIや全プロセスへの再構築通知は未実装 |
| E09 / V3,V5 | JSON snapshotをatomic置換し、置換前に開いたreaderと新readerで取得 | 旧readerは旧版全体、新readerは新版全体 | 同一プロセスのファイルハンドル比較。採用extensionでの切替は別条件 |
| E10 / V4 | FTS5 unicode61/trigram、1・2・3文字の日本語 | 作成成功。trigram `MATCH`は「東」「東京」0件、「東京都」1件。`LIKE '%東京%'`は1件 | LIKEの成功は短文index効率を保証しない。unicode61は単語単位で任意部分一致ではない |
| E11 / V4 | 検索用NFC+case/width foldingと期待集合 | 結合濁点／合成済、半角／全角カナ、全角／半角英字大小は一致。かな／カナ、清音／濁音は区別 | 試験で選んだ比較仕様。製品の検索仕様は利用シーンと合わせて決める |
| E12 / V4 | 古い検索を遅延させ新しい検索の後に完了、FTSの更新・削除・rebuild | 世代番号で古い結果を適用しない。更新・削除後のFTS検索が期待集合に一致 | 世代管理は試作のロジック。external-content FTSや製品import索引の試験ではない |
| E13 / V5 | versioned JSONの往復と不正import | UTF-8一致。不正JSON、未知の版、重複ID、4 MB超を拒否。不正import後も既存値を保持 | サイズは試作用制限。異なる既存データへのmerge方針は未決定 |
| E14 / V1,V5 | 保存失敗後の本文保持・下書き再open | 保存失敗を表示し、別editorが同じ下書きを取得 | save直前に容量不足エラーを注入。実際の容量枯渇や保存中のOS終了を代替しない |
| E15 / V5 | 期限付きAの消失、期限前にBまたは同文Aで上書き | Aは期限後にnil。上書きB・同文Aは旧期限後も保持 | 同一アプリのgeneral pasteboard、1秒期限・2秒後読取。別アプリ書込・Handoff・ロック・再起動は未実施 |
| E16 / V1,V4 | UIの作成→日本語検索→再open→copy→削除→復元 | sim-useで操作成立、削除したIDが消え、復元後に同じIDが再表示。copyの全UTF-8 bytesが一致 | `sim-use paste`はIMEを通らない。復元は起動中の1件のみ |
| E17 / V2,V5 | URL入力をallowlistで判定 | list/createを許可。delete、不正ID、query、fragment、別schemeを拒否 | custom schemeの競合、Universal Linksのドメイン関連付けは別の試験 |
| E18 / V2,V6,V7 | SDKの型・memberを26.0 targetでコンパイル | Simulator/iphoneos × app/`-application-extension`の4条件成功 | API一覧は下記。機能の登録・権限・実行結果を保証しない |
| E19 / V8 | generic iOS向けarchiveとmanifest配置 | unsigned archive生成成功、bundle rootに`PrivacyInfo.xcprivacy`、plist構文検査成功 | `codesign --verify`は未署名を報告。配布・Validate App・審査は未実施 |
| E20 / V5 | `.completeFileProtection`を指定したsnapshotの保護属性 | 書込・置換は成立したが、Simulatorの取得属性はnil | 実機の暗号化・ロック時読取を検証済みとしない |
| E21 / V1,V2 | SafariのtextareaへOSの編集メニューからペーストし、リンクから本体へ復帰 | フォームが表示したUTF-8配列が原文と一致。custom schemeの確認ダイアログを経て本体の一覧へ復帰 | ローカルのダミーフォーム1件。シミュレータのclipboardへ再書込するsim-use pasteをhost側では使わない |
| E22 / V4 | 日本語かなキーボードの実キーで「かな」を入力、候補「カナ」を選択、コピー | 候補選択が本文へ反映され、原文+「カナ」の全bytesが一致 | 本文編集の1条件。変換中の検索結果更新・全IME・全hostの試験は残る |
| E23 / V6 | iPhone 17 Proでdark/最大Dynamic Type/ソフトキーボードを表示 | キーと保存・コピー・削除が表示され操作可能。最大文字サイズとキーボード併用時は本文viewportが狭く、全文はスクロールを要する | 可読性・支援技術での操作性の合格判定ではない |
| E24 / V6 | iPhone SE第3世代・375×667 pt、最大Dynamic Typeとキーボード併用 | **不合格**。本文viewportが36 ptまで縮み、文字の上下が切れる。タイトルも省略される。copyの本文は保持 | 縦stackに全操作を置くこの試作を製品へ採用しない。入力と操作の配置、ページ全体のスクロールを比較する必要がある |
| E25 / V2 | Shortcuts一覧への登録とアクション実行 | 一覧への表示は成功。実行は失敗し、OSログは`LNActionForAutoShortcutPhraseFetchError Code=1 / Couldn’t find AppShortcutsProvider` | 明示的な`updateAppShortcutParameters()`、アプリ/Shortcutsの再起動、ad hoc署名でも同じ画面エラー。metadataにはproviderとactionが存在する。原因は未特定で、26.5実機・署名構成での比較が必要 |

SDK probeは`AppIntent.supportedModes`、`AppShortcutsProvider`、`ControlWidgetButton`、`StaticControlConfiguration`、`Widget`、`TimelineProvider`、`Button(intent:)`、`widgetURL`、`containerBackground`、`systemSmall/accessoryRectangular`、`ControlCenter`/`WidgetCenter`のreload、`UIInputViewController`の挿入・削除・切替・Full Access照会、App Group URL、`NSExtensionContext`の完了・cancel、pasteboard options、Observation、`ModelActor`、`MXMetricManager`/subscriber、`CKSyncEngine`のfetch/sendとstate updateのserializationを含む。これ以外の全API・全Widget familyの確認結果ではない。

## 計測値の使い方

同じ短いダミー本文で0・20・1,000・10,000件を試した。各ストアの新規作成後の保存・全件取得は各1回、全件正規化を含む検索は30回。SimulatorのRelease（`-O`、テスト可能設定）であり、cold launch、実機のCPU・メモリ・電源条件をそろえた性能比較ではない。保存には各frameworkの管理処理と履歴の差も含まれる。

| 件数 | SwiftData 保存/取得 ms | Core Data 保存/取得 ms | SQLite 保存/取得 ms | 全件検索 中央値/最大 ms（30回） |
| --- | --- | --- | --- | --- |
| 0 | 0.124 / 0.099 | 0.780 / 0.083 | 0.048 / 0.017 | 0.000 / 0.002 |
| 20 | 4.945 / 0.449 | 3.348 / 0.302 | 0.066 / 0.037 | 0.088 / 0.163 |
| 1000 | 72.733 / 15.840 | 12.552 / 3.764 | 1.228 / 0.912 | 4.432 / 4.563 |
| 10000 | 700.163 / 173.106 | 88.247 / 31.531 | 11.662 / 8.260 | 43.920 / 47.120 |

個々のraw値はテストアプリの`Documents/results/simulator-timing.json`。この試作はMainActor上で全件を処理するため、観測値を製品の性能予算として採用しない。index・取得範囲・背景処理の必要性を判断するための実機測定へ進む材料とする。

## 未実施条件の全体対応

下表は01〜04の未確認事項とV0〜V8のうち、上の実行やP01〜P13では完了しない条件をまとめる。「未決定」は製品の選択であり、テストの成功で自動的に決定されるものではない。

| 計画 / 関連章 | 未実施・未確定の内容 | 完了に必要な条件と確認手順 |
| --- | --- | --- |
| V0 / 01,03,05 | 実利用のhost、頻度、既存手順、完了地点、初回設定・日常利用の比較、片手の迷い・失敗 | 利用者の代表的な2〜3タスクを確定し、現在の方法と候補導線を同じ実機で観察。自動化所要時間を人のタスク時間にしない |
| V1 / 01,03 | メール・メッセージ等の対象host全体、cold/warm・オフライン、長文・連打・0件時の使い勝手 | 実際の優先hostと実機で本文一致・復帰・区間別時間を計測。Safari1条件の成功を全hostへ広げない |
| V2 / 01 | Controls・Widget・Share/Action・Keyboardの登録、初期データなし、入力形式別の可否、Full Access拒否・取消、非対応host、ロック・機内モード・Action Button | 入口の採用候補を確定し、同じTeamの本体・extensionのtargetとentitlementを登録。iOS 26.5実機で成功・拒否・fallbackを録画する。SDKCompileProbeだけで完了しない |
| V2 / 01 | Universal Linksの関連ドメイン、custom schemeの競合・削除済みIDの実導線 | 管理するドメインとAASA、採用するID遷移仕様が必要。未インストール・同一ドメインSafari・不正入力を確認 |
| V3 / 02 | SwiftData/Core Dataの別プロセス同時利用、更新通知・stale context、保存中終了、移行担当とextension起動の競合 | 選択した実extensionと共有ストアで書込成功→他入口の再取得を記録。SDK/本体内接続だけでは判定できない |
| V3 / 01,02 | Keyboardからのread-only DB初期化、live WAL sidecar不足、snapshotの初回生成前・移行中・版切替 | 実際のFull AccessなしKeyboard、App Group、3方式のread-only設定で試す。POSIX read-onlyディレクトリの成功と権限を区別 |
| V3 / 02 | Apple同梱SQLiteのWAL-reset修正、長期履歴・WAL・index増加とcleanup | Apple派生版の修正情報・該当ソースの確認と再現条件の長期試験。版番号や単発の競合成功から修正済みと断定しない |
| V4 / 02,03 | 変換中の検索・候補・カーソル、長文、全角記号等の最終期待集合、import後の派生index整合性 | 入力部品・検索仕様を確定し、実IMEで変換中に検索・保存・画面更新を重ねる。programmatic markedTextの確認とは区別 |
| V5 / 01,02,04 | 端末の再ロック・初回アンロック前・バックアップ復元、Keychain移行、全入口の認証と本文露出 | 署名した実機で本体・App Group・sidecar・Keychainの保護クラス別に読書き。読めない状態で初期化しないことを確認 |
| V5 / 04 | アプリ切替画面の本文隠蔽、ログと検索への本文露出 | 試作のscene非アクティブ時のcoverは実装のみ。アプリ切替画面の実際のsnapshot、エラー経路のログ、採用する検索公開設定を個別に確認する |
| V5 / 01,04 | 別アプリの後続コピー、Handoff、端末再起動後の期限・転送・changeCount競合 | 2台の実機、同一Apple Account/Handoff条件と接続状態が必要。A→B→旧期限を別アプリで繰り返す。ペースト済み本文の回収は保証対象にしない |
| V5 / 02,04 | 製品全旧版からの移行、失敗・ディスク枯渇・途中終了、merge import、削除後の履歴・snapshot・backup・同期先 | 製品schema/保持方針と出荷版fixtureが必要。移行失敗時に元ストアを保持し、再試行・exportで復旧できるか比較 |
| V6 / 03 | VoiceOver読順・通知、Voice Control、Switch Control、外付けキーボード、片手・左右、コントラスト・Reduce Motion | 実機と実際の支援技術で主要タスクを完了。AXツリー・スクリーンショットだけを読み上げ動作の証拠にしない |
| V6 / 03 | 実機Releaseの起動・再呼出・検索・保存・hitch・メモリ・電力・長期利用、性能予算 | 同一のiOS 26.5実機・電源/熱条件・データで反復、Instruments traceを収集。Simulatorの値や原著係数を予算へ転用しない |
| V6 / 03 | MetricKit metric/diagnosticの自然受信、payload保存・外部転送・運用 | 実機で受信期間を設ける。転送先と保持方針を決定。コンパイルや合成payloadは実配送の確認ではない |
| V7 / 02,04 | 同期の必要性、CloudKit schema、編集/削除競合、オフライン・長期不在、アカウント変更、無効化/再開、両端末収束 | Developer Team/CloudKit container、2台の26.5端末と試験アカウント、同期採否が必要。両本文保持・アカウント分離・復旧を確認 |
| V8 / 04 | 署名/export、TestFlight更新、最終manifest/API用途・App Privacy・privacy policy、ライセンス・サポート先、審査 | 製品target、Team・証明書・profile、配布方法・データフローを確定。最終archiveを点検し配布更新を実行。審査承認は提出結果で判断 |
| 文献 / 03 | KLM/Jotaの原著本文 | 出版社が本文取得を許すアクセスか合法公開全文が必要。P01/P02の取得不能記録を参照。Altmann原著はP03で照合済み |

保存・呼び出し方式、検索規則、機密項目、同期、rich text/画像/変数、アカウント/AI/課金、配布・運用担当は引き続き製品の判断項目。試作の便宜上の選択を採用ADRへ昇格しない。

## 証跡と検証コマンドの結果

生成物はGit管理対象外。下のパスは当日のローカル証跡の識別子であり、PRへの添付を代替しない。新規の比較試作なので製品画面の変更前画像はない。確認に使ったダミーデータと再現コマンドはソースに含める。

最終テストとCRUD録画は同じアプリ・テストソースで取得した。Safari・日本語IME・最大文字・小画面・最初のShortcuts録画は`20260913T052747Z-research-ui`で使った版に対応し、その後にeditorのclosureをweak参照へ変更し、Shortcutsの明示的な登録更新を追加した。補足録画を最終ソースの再実行と扱わない。操作の追試結果、画像・抽出フレームの確認範囲、ファイルhashは`artifacts/research/REVIEW.md`と`evidence-index.json`に記録する。

| 検証 | 結果・証跡 |
| --- | --- |
| Release Swift Testing | `artifacts/ios/20260913T054738Z-test-5dc7a9/`。14テスト、パラメータ違いを含む16ケース成功、失敗0・skip0 |
| 最終CRUD操作 | `artifacts/ios/20260913T054807Z-research-ui-35b334/`。manifest、UI JSON、clipboard、assertions、PNG、MP4と抽出フレーム |
| SDK | `artifacts/research/sdk/`、4構成exit 0 |
| 別プロセスSQLite | `artifacts/research/processes/3d2b3f84-e9f2-4892-9922-8f0cbb6e66ee/results.json` |
| 詳細JSON | `artifacts/research/final-results/`。runtime・SQLite source ID/compile options・履歴・移行・snapshot・文字列・timing |
| Safari | `artifacts/research/safari-pasted-final.png`、`safari-paste-final.mp4`、`safari-pasted.json`、`safari-assertion.json`、`safari-return.json` |
| 日本語IME | `artifacts/research/japanese-ime.mp4`、`japanese-composing.json`、`japanese-confirmed.json`/PNG、`japanese-copy.txt` |
| 表示条件 | `artifacts/research/dark-large-editor.png`、`dark-large-keyboard.png`、`compact-large.png`/JSON。compactは不合格の証拠 |
| Shortcuts | `artifacts/research/shortcuts-open.png`/MP4、`shortcuts-os.log`、`shortcuts-retry.json`、`shortcuts-adhoc-result.json`。実行失敗の証拠 |
| unsigned archive | `artifacts/research/ResearchProbe-final.xcarchive`、`archive-final.log`。配布未検証 |
| 共通検査 | `nix flake check --no-update-lock-file --print-build-logs`の3検査成功。Python基盤テスト12件成功。今回の実行hostはaarch64-darwinであり、Linuxでの実行結果ではない |

UIのAX値は外側の空白を省く場合があったため、本文の完全一致はcopyしたbytesで確認した。画面操作では検索中のnavigation barが隠れて復元へ到達できない問題を確認し、試作は検索中もnavigation barを表示する。UIKitの通常表示、操作録画の抽出フレーム、Safariペースト、日本語候補確定、最大文字、小画面での文字切れ、Shortcutsのエラー画面を確認した。録画の取得・復号確認と視覚確認を区別し、各REVIEWに確認範囲を残す。

研究の主要な結論は、短い日本語検索をtrigram MATCHだけでは実現できないこと、保存方式3案の基本機能は成立する一方で共有権限・性能・移行の採用判断には追加条件があること、単純な縦配置が小画面の最大文字で破綻すること、Shortcutsの登録成功が実行成功を意味しないことである。未実施条件を満たすまでは、製品の全導線や性能・保護・同期を検証済みにしない。
