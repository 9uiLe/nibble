# UI/UX・操作効率・アクセシビリティ・応答性能

MVPの画面はSwiftUIの一覧・検索・スクロール可能な編集画面で構成する。[製品設計](../docs/decisions/0002-mvp-app.md)が採用仕様を定め、本書は比較・評価の根拠を扱う。Simulatorでの製品確認と、VoiceOver等の未検証項目は[MVPの検証結果](../docs/mvp-validation.md)を参照する。

対象は **iOS 26.0以上**。一次資料の確認日：2026-09-13。スニペットを利用して作業へ戻るまでの操作と応答を評価し、製品のUI、入力部品、性能予算を選ぶための根拠と検証条件を示す。

「事実」は原著・Apple公式資料の内容、「推奨」はnibbleへの適用案、「未確認」は実装・実機・利用者による検証条件を示す。原著とApple一次資料のURL・閲読範囲・制約は資料台帳と[補足の一次資料検証](experiments/primary-source-validation.md)に記載する。外部本文は転載しない。

## 1. 評価するタスクと指標

**推奨:** **呼び出す → 見つける → 内容を確認する → 利用する → 元の作業を続ける**を一つのタスクとして評価する。作成・編集・削除にも、一覧や元の作業へ戻る操作を含める。操作数、探索時間、誤り、総完了時間から導線を比較する。

各指標の根拠と適用案を示す。

| 観点 | 一次資料から確認できたこと | nibble への推奨 |
| --- | --- | --- |
| 操作数 | KSPC は入力方式と言語モデルから打鍵量を比較できるが、候補の視認・判断、誤入力修正などを単独では説明しない。[U01](#u01) | タップ数と入力文字数に加え、探索時間、誤選択、やり直し、総完了時間を記録する。 |
| 押しやすさ | 2D 選択では幅だけでなく高さ・接近方向がモデルに影響し、片手親指の研究では対象サイズと速度・誤りに関係があった。[U02](#u02) [U03](#u03) | 行全体の操作領域、上下の間隔、画面端、片手保持を確認する。小さなアイコンを増やして密度だけを優先しない。 |
| フィードバック | マウスによる選択研究では遅延が操作時間だけでなく誤りにも影響した。iPhone の閾値を決めた研究ではない。[U04](#u04) | 遅延を単なる待ち時間として扱わず、連打・二重実行・誤選択の原因になっていないか調べる。 |
| 発見しやすさ | Apple は context menu 内の操作をメイン UI からも使えるよう求めている。[U06](#u06) | 編集・削除を長押しやスワイプだけに閉じ込めない。 |
| 単純さとアクセシビリティ | Apple は標準的で単純な操作、ジェスチャーの代替、Dynamic Type、VoiceOver、Full Keyboard Access などを推奨する。[U05](#u05) | 通常のタッチ操作と支援技術で、同じ主要タスクを最後まで完了できることを受け入れ条件にする。 |
| 性能 | 長い処理だけでなく、短い SwiftUI 更新が過剰に起こることも hitch の原因になる。[U13](#u13) | 画面録画による体験確認と Instruments による原因・時間の確認を組み合わせる。 |

## 2. 原著研究から使える知識と適用限界

### 操作数・探索・総完了時間

**事実:** MacKenzie (2002) は KSPC（生成する文字 1 文字当たりの打鍵数）を、操作手順と言語コーパスから事前計算する方法として整理した。主に British National Corpus の約 9,000 万語を使い、文字・二文字連鎖・単語の頻度表で複数の入力方式を分析している。被験者を使った nibble 型ツールの比較実験ではない。[U01](#u01)

語予測では候補選択の方式が打鍵量に影響し、著者自身が注意配分、誤り、修正などの限界を述べている。[U01](#u01)

**推奨:** 検索、最近使った項目、固定した項目などの候補を比較する際は、利用頻度を仮定した操作シーケンスを描く。本文を手入力する場合に比べて何操作を節約できるかと、候補を探す負担を分けて評価する。候補数を増やすことや自動並べ替えが速さにつながるかは、実際のタスクで確かめる。

**適用限界:** 英語の小文字・空白を中心とする分析で、日本語変換、コード記号、複数行スニペット、絵文字の入力負担を直接表さない。論文中の Hick-Hyman 由来の時間推定も nibble の SLA に転用しない。nibble では文字数の定義を決め、入力文字数、変換・候補選択、タップ数を別々に記録する。

### 操作領域の幅・高さ・位置を同時に見る

**事実:** MacKenzie & Buxton (1992) は大学のコンピュータ利用経験者 12 人（男性 9 人、女性 3 人）を対象に、Macintosh II、マウス、640×480 の CRT で長方形を選択する実験を行った。接近方向は 0・45・90 度で、距離・幅・高さを変えた 78 条件、各人 1,170 試行を使用した。水平幅だけを使うモデルに比べ、幅と高さの小さい方、または接近方向上の幅を用いるモデルの適合が改善した。[U02](#u02)

**推奨:** 横に長いスニペット行でも、行高が不足すれば選択しやすいとは限らないという設計上の注意として使う。コピー・編集・削除の領域が隣り合う場合は、高さと間隔、手の届き方も見る。

**適用限界:** マウスカーソルと親指タッチでは入力特性が違う。論文の回帰係数を iPhone の選択時間予測に使わない。左手、片手保持、指による遮蔽、支援技術を検証した研究でもない。

**事実:** Parhi, Karlson & Bederson (2006) は右利き 20 人（19〜42 歳、男性 17 人、女性 3 人）に HP iPAQ h4155 を片手で持ち、立った状態で右親指を使わせた。単発選択は 3.8〜11.5 mm の対象を 9 領域で、連続入力は 5.8〜13.4 mm のキーを 4 領域で比較した。[U03](#u03)

大きい対象ほど速度が改善する傾向があり、誤り率の差と主観評価を踏まえて単発 9.2 mm、連続 9.6 mm を提案している。著者は歩行中や異なる筐体への一般化を未検証としている。[U03](#u03)

**推奨:** この研究は「物理寸法・保持方法・入力種類をそろえて比較すべき」という根拠にする。確認日のApple HIG は iOS の既定 control size を 44×44 pt、minimum を 28×28 pt と掲載している。[U05](#u05)

nibble の主操作は **44×44 pt 以上を初期の設計目安**とし、小さい領域を採用する場合は誤操作・間隔・支援技術を実機評価する。44 pt が確認日のHIG における全場面の絶対最小値であるとは記載しない。[U05](#u05)

**適用限界:** 2006 年の PDA の mm 値を現行 iPhone の pt に一律変換しない。研究の右利き中心の標本から、左利き、高齢者、運動機能に制約がある人の使いやすさを断定しない。

### 待ち時間と誤りを一緒に評価する

**事実:** MacKenzie & Ware (1993) はマウス経験のある大学の参加者 8 人を対象に、Silicon Graphics IRIS、光学マウス、60 Hz CRT を用いた横方向の対象選択実験を行った。遅延は 8.3・25・75・225 ms、距離は 3 水準、幅は 4 水準。[U04](#u04)

225 ms 条件では 8.3 ms 条件と比べて平均移動時間が 911→1,493 ms、誤り率が 3.6→11.3% に増加した。遅延と課題難度の交互作用も報告している。[U04](#u04)

**推奨:** コピーや保存の応答が遅いとき、待ち時間の短縮だけでなく「利用者が処理済みと理解できるか」「もう一度タップして二重操作しないか」も評価する。フィードバック表示を足す場合も、実処理完了と一致させる。

**適用限界:** これは直接タッチ、検索、アプリ起動、iOS 26 の評価ではない。75 ms・225 ms を知覚の普遍的境界や nibble の合格値にしない。論文の「zero lag」に相当する比較条件にも平均 8.3 ms の遅延があり、本当に 0 ms ではない。

## 3. Apple の設計指針を製品の確認項目にする

### スニペットの利用・編集・削除

**事実:** Apple は標準 edit menu の利用、標準の選択ジェスチャー、適切な Cut / Copy / Paste、可能な場合の undo / redo を勧めている。context menu は関連する少数の操作に絞り、その操作をメイン UI にも用意する。iOS では同じ対象に context menu と edit menu の両方を提供しないよう案内している。[U06](#u06) [U07](#u07)

**推奨:** スニペットという項目への操作と、編集している本文の選択範囲への操作を区別する。項目のコピーと本文の Copy が競合しないかを確かめる。「削除」はコピーの近くで誤って実行されない配置にし、取り消し・復元の方法を検討する。確認ダイアログの回数を増やすことだけを安全性としない。作成・編集中の中断では下書きや選択位置をどう扱うかを仕様にする。

**MVPの採用仕様:** コピー後は一覧を維持し、利用者が入力先へ戻る。保存は明示操作とし、編集中の入力は下書きとして保持する。削除は直後の取り消しと削除一覧からの復元を用意する。[製品設計](../docs/decisions/0002-mvp-app.md)が契約を定める。これらの選択の使いやすさを比較する利用者試験は未実施。他アプリへの挿入やクリップボード権限の可否は、このUI資料だけでは判定できない。

### 検索と大量件数

**事実:** Apple は可能なら入力とともに検索を開始し、関連性の高い結果を先に出し、検索対象が分かる placeholder を使うよう案内している。iOS の検索配置には tab、toolbar、inline の選択肢がある。現行 HIG は 2026 年の更新を含む。[U08](#u08)

**推奨:** スニペットのタイトルだけでなく本文を検索するか、ひらがな／カタカナ・全角／半角・英字大小・記号をどう扱うかを仕様にし、検索の正しさと速度を別々に測る。入力が続く間の古い結果の上書き、削除済み項目の表示、結果の並べ替えでタップ対象が移動することを防ぐ設計を検証する。検索や並べ替えを毎回全件へ適用する必要があるかは、計測して判断する。

**推奨:** 検証用データは空、20、1,000、10,000 件を初期案とし、長い本文、同名、同じ先頭文、絵文字、コード、複数行、検索結果 0 件を含める。件数は負荷試験の仮定であり、対応保証や「通常の利用量」ではない。索引・ページング・キャッシュの採否はこの負荷と実際の利用想定から決める。

**未確認:** 利用者が覚えているのはタイトル、本文、利用時期のどれか、最近使った項目や固定項目がどの程度必要か。検索配置や初期フォーカスの最適解も、導線別の試作で比較する。最新 HIG の見た目を採用する際は API availability を iOS 26.0 で別途確認する。

### 日本語入力とキーボード

**事実:** `UITextInput.markedTextRange` は、利用者の確定を必要とする多段階入力の暫定テキスト範囲を表す。確定前の文字列を通常の確定済み入力と同一視できない。[U11](#u11)

**推奨:** 日本語の変換中に再描画や検索結果反映が起きても、未確定文字、候補、カーソル、選択範囲を壊さないことを確認する。Return による変換確定と「検索」「保存」「送信」を混同しない。本文の空白・改行・記号を勝手に整形しない。検索・保存の処理で未確定入力をどう扱うかは仕様とテストを一緒に定める。

**事実:** Apple は入力の種類に応じた keyboard / Return key、キーボードで隠れないレイアウト、標準 shortcut の尊重、Full Keyboard Access を勧める。custom keyboard extension には他のキーボードへ分かりやすく切り替える導線が必要である。[U09](#u09) [U10](#u10)

**推奨:** iPhone のかなフリック・日本語ローマ字・英語・絵文字、利用可能なら外付けキーボードを確認する。検索の呼び出し、結果選択、キャンセル、作成・編集・コピーがタッチなしでも完了するかを調べる。標準 Copy / Paste / Undo や入力ソース切り替えを別用途へ上書きしない。custom keyboard を検討する場合は、nibble 内部の検索だけでなく標準キーボードへ戻るまでを録画する。

**未確認:** システム IME と実際に採用する SwiftUI / UIKit の編集部品の相互作用、ホストアプリごとの extension 挙動。標準部品を使うことは検証免除の理由にならない。

### アクセシビリティ

**事実:** Apple は、色だけに依存しない情報、文字サイズ拡大、VoiceOver、十分な操作領域と間隔、複雑なジェスチャーの回避、代替操作、Reduce Motion を含むシステム設定への対応を求めている。自動で消える UI は認知・支援技術の操作時間に影響するため最小限にするよう勧めている。[U05](#u05)

**推奨:** 次の確認を通常のタスク検証と同時に行う。

| 条件 | 確認すること |
| --- | --- |
| VoiceOver | 呼び出し直後のフォーカス、検索欄→結果→操作の順序、同名項目の識別、コピー・保存・削除の結果通知、元画面への復帰。長文全文の読み上げが必須にならないラベルと操作。 |
| Dynamic Type | 最大のアクセシビリティ文字サイズでも検索、本文確認、作成・編集・削除、閉じる操作が可能。省略された本文を確認する手段がある。 |
| 色・外観 | ライト／ダーク、Increase Contrast、背景素材が変わる場所で文字・アイコンが識別可能。成功・エラー・選択状態を色だけで伝えない。 |
| 動き | Reduce Motion 時の過剰な拡大・跳ね・移動を抑え、状態変化そのものは理解できる。 |
| 運動・入力支援 | 片手、左右の手、Voice Control、Full Keyboard Access、必要に応じて Switch Control で主要操作を実行。長押しやスワイプに代わる操作がある。 |
| 一時的な通知 | 「コピーしました」などの表示を見逃しても処理結果が理解できる。自動で消える通知だけに Undo の唯一の入口を置く案は慎重に評価する。 |

表は製品の受け入れ条件の候補を示す。各条件での製品検証は未実施。

## 4. 応答性能を計測できる形にする

### 応答時間と描画の指標

**事実:** Apple の responsiveness 資料は、離散的操作に対する同期的なメインスレッド処理を 100 ms 未満、連続操作を 1 refresh interval（おおむね 8 または 17 ms）未満とする粗い目安を掲載している。同時に、システム側のイベント・描画処理にも時間が必要で、アプリに全時間を使えるわけではなく、連続 UI 更新で約 5 ms 未満を目指す説明もある。資料自体がこれらを大まかな目安としている。[U12](#u12)

**推奨:** 「処理が 100 ms 未満だから速い」とは判定しない。入力受信、検索処理、結果の適用、描画、利用者の完了判断までを区別する。60 Hz と 120 Hz では予算が異なり、可変 refresh rate、端末状態、レンダリングコストも関わる。nibbleの合格値はiOS 26.5の実機と想定データで基準値を採った後、導線ごとに決める。

**事実:** Instruments 26 の SwiftUI instrument は、長い body 更新、representable 更新、不要な更新の原因を追う機能を提供する。WWDC25 の例では formatter 作成・計算を body 内で繰り返す負担と、配列全体への依存によって多数の行が更新される問題を診断している。[U13](#u13)

**推奨:** 検索正規化、表示用文字列生成、本文プレビュー加工、ソート、I/O が body や入力処理を占有していないかを調べる。更新範囲を狭める、表示用データを準備する、キャッシュする、といった候補は実測後に比較する。

キャッシュを導入する場合は更新・削除・locale 変更で古い内容を出さないことも検証する。`Task {}` と書くだけで重い仕事が MainActor 外へ移ると考えず、選定する Swift の設定と実際の実行位置を確認する。[U12](#u12) [U13](#u13)

### 初回実装時の計測計画案

| タスク | 区間・指標 | 確認手段 |
| --- | --- | --- |
| 初回起動・再呼び出し | 呼び出し操作から操作可能になるまで。cold / warm、入口ごとに分ける。 | ローカル実機の UI 操作、画面録画、Instruments、採用 Xcode の launch metric。 |
| 検索 | 入力受信→検索終了、検索終了→結果反映。利用者が結果を操作できるまでの体験も別に確認。 | 対象区間の signpost、Instruments、XCTest performance、録画。 |
| 一覧スクロール | hitch 数・時間、更新が集中する箇所、CPU・メモリ、長文表示や大量件数の影響。 | Animation Hitches、SwiftUI instrument、Time Profiler。 |
| 作成・編集・保存・削除 | 入力の追従、操作→完了反映、永続化の完了と表示上の成功の対応、繰り返し操作。 | 対象区間の計測、UI 検証、録画。 |
| コピー・挿入 | 選択→コピー／挿入→元の作業継続。二重実行、誤った項目の利用、失敗時の回復。 | 連携先を含む実機タスク、録画。アプリ内計測だけで他アプリへの挿入成功を推定しない。 |
| 継続使用 | メモリ増加、キャッシュ量、エネルギー、リリース後の hang 診断。 | Instruments と、採用する場合は MetricKit / Xcode Organizer。[U12](#u12) [U15](#u15) |

**推奨する実施条件:** iOS 26.5のみを対象に、同じ実機、Xcode / Swift、Release構成、データと操作手順で変更前後を比較する。端末モデル、バッテリー・低電力モード・熱状態、cold / warm の定義、ウォームアップ、測定回数と外れ値の扱いを記録する。

初期の反復数は各条件 30 回程度を仮案とし、生データ・中央値・最大値を残す。p95 等を使う場合は十分な試行数と算出方法を別途決め、少数試行の裾の値を保証値にしない。実機の測定値と製品の性能予算は未確定。

**事実:** Apple は性能テストを Release 構成で実行し、Debug executable、coverage、runtime sanitizer を無効にして実運用に近い条件を作るよう案内する。XCTest の計測値・baseline・許容幅を使って回帰を検出できる。[U14](#u14)

**推奨:** sanitizerで正しさを調べる実行と、速度を比較する実行を分けて記録する。性能回帰を隠すためにbaselineを更新しない。Apple SDKの計測・テストはローカルMacと実機で行う。試作の実行・画面記録には [検証基盤](../docs/ios-verification.md) を使い、性能測定用targetと計測条件は試作ごとに定義する。

### リリース後の計測と OS 世代

**事実:** `MXMetricManager` は iOS 13 以降で利用でき、過去 24 時間の metric と未配達分を配信する。現行の class 資料は「metric source ごとに 1 日最大 1 回」とし、異なる source 由来で一日に複数 payload が届く可能性も説明する。診断は iOS 15 以降、利用可能になった時点で配信する。実機での受信確認が必要である。[U15](#u15)

**事実:** 現行 MetricKit トップページが紹介する新しい `MetricManager` の非同期 sequence は **iOS 27 以降**であり、26.0 の API と同一ではない。[U15](#u15)

**推奨:** iOS 26.0 では `MXMetricManager` / `MXMetricManagerSubscriber` を含む互換性を評価し、27 以降の API は availability と移行方針を別に決める。MetricKit は各操作の全件・即時の測定を保証する仕組みとして使わない。保存・送信する診断情報、保持期間、利用者への説明、運用先は技術採用前に設計し、スニペット本文や検索語を性能ログへ入れない。外部へ診断情報を送る構成は未決定。

## 5. 製品の操作・性能を評価する試作

1. **利用までの往復:** 既存の文字入力中に呼び出し、1 件を選び、利用して戻るまでを入口ごとに記録する。成功率、操作数、所要時間、誤り、再試行を比較する。
2. **入力と検索:** 日本語変換中の編集、10,000 件の検索、連続入力、0 件結果を同じ試作で扱い、入力を壊さず結果を更新できるかを確認する。
3. **作成・編集・削除の回復:** 中断、保存失敗、誤削除を再現し、データと画面状態を失わず理解できる導線を比較する。
4. **標準部品での到達性:** Dynamic Type、VoiceOver、片手、Full Keyboard Access の主要タスクを実行し、スクリーンショット・録画と性能 trace を取得する。

ResearchProbeのUIKit画面は、一覧・編集・コピー・削除復元を通して原文と状態の保持を比較する。自動操作では[E14〜E16](experiments/ios-26-5-validation.md)、システムの日本語かなキーボードではE22の条件を評価する。小画面・最大文字サイズ・キーボード併用時に本文が切れる縦配置は、製品の表示要件を満たさない（E24）。

製品の画面構成、入力部品、データ更新、性能予算は、利用者の主要タスクと実機で評価して選ぶ。支援技術の操作性と実機性能は未実施である。検証コマンド・撮影の成立、比較試作の結果、製品の受け入れ条件をそれぞれ記録する。

## 6. 資料台帳

根拠とする一次資料は、原著4本を含む **16ページ／論文**。出典IDは15項目で、U15は2ページを参照する。Apple DocCは公式JSONの本文・metadataも確認対象とする。資料には26.0より新しいOSの情報が含まれるため、個別APIのavailabilityを照合する。

### U01

- 著者・題名・年: I. Scott MacKenzie, *KSPC (Keystrokes per Character) as a Characteristic of Text Entry Techniques*, 2002. Mobile HCI 2002, LNCS 2411, 195–210.
- URL: <http://www.yorku.ca/mack/hcimobile02.html>（著者の York University 公開版）。
- 閲読範囲: HTML 版の abstract、KSPC 定義、corpus、入力方式の分析、word prediction、performance issues、conclusion。本文の比較表を含む。
- 制約: 新規の被験者実験ではなく、英語コーパスと仮定した操作手順による分析。画像化された数式の再計算や付属ソフトの実行はしていない。HTTPS が証明書エラーとなるため、大学が提供する HTTP 版を取得した。

### U02

- 著者・題名・年: I. Scott MacKenzie & William Buxton, *Extending Fitts' Law to Two-Dimensional Tasks*, 1992. CHI ’92, 219–226.
- DOI: <https://doi.org/10.1145/142750.142794>。閲読 URL: <http://www.yorku.ca/mack/CHI92.html>（著者の大学公開版）。
- 閲読範囲: abstract、モデル定義、method、results、model comparisons、discussion のモデル一般化に関する部分。図の caption と数値表も確認。
- 制約: マウスと CRT を用いた 12 人の実験。引用文献の研究を別途読んだとは扱わない。HTTPS の証明書エラーにより HTTP 版を利用。

### U03

- 著者・題名・年: Pekka Parhi, Amy K. Karlson & Benjamin B. Bederson, *Target Size Study for One-Handed Thumb Use on Small Touchscreen Devices*, 2006. University of Maryland HCIL technical report 2006-11.
- URL: <https://www.cs.umd.edu/hcil/trs/2006-11/2006-11.pdf>（著者所属研究所の公開 PDF）。
- 閲読範囲: 8 ページの PDF の abstract、study design、participants / equipment、discrete / serial tasks、results、discussion、conclusions をテキスト抽出で確認。3 ページの参加者・機器・試行条件、7 ページの連続入力の結果・discussion を画像でも確認。
- 制約: 抽出では一部二段組みの行順が乱れる。本文で確認できた条件・結論を使用し、グラフから追加の数値を推定していない。右利き・立位・特定 PDA の結果である。

### U04

- 著者・題名・年: I. Scott MacKenzie & Colin Ware, *Lag as a Determinant of Human Performance in Interactive Systems*, 1993. INTERCHI ’93, 488–493.
- DOI: <https://doi.org/10.1145/169059.169431>。閲読 URL: <http://www.yorku.ca/mack/CHI93b.html>（著者の大学公開版）。
- 閲読範囲: abstract、lag の説明、method、results and discussion、prediction model、conclusions、表 1 の各遅延条件。
- 制約: 8 人のマウス選択実験。新しい iPhone、直接タッチ、検索処理の評価ではない。HTTP の著者公開版を利用。

### U05

- 著者・題名・年: Apple, *Human Interface Guidelines — Accessibility*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- 閲読範囲: Vision、Mobility、Speech、Cognitive、control size と contrast の表、関連設定の指針。
- 制約: HIG の設計指針。nibble の適合試験を行った結果ではない。既定サイズと最小サイズを区別した。

### U06

- 著者・題名・年: Apple, *Human Interface Guidelines — Context menus*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/design/human-interface-guidelines/context-menus>
- 閲読範囲: best practices、content、iOS / iPadOS の項目。
- 制約: 実際の表示位置・他操作との競合は採用 UI で検証が必要。

### U07

- 著者・題名・年: Apple, *Human Interface Guidelines — Edit menus*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/design/human-interface-guidelines/edit-menus>
- 閲読範囲: 標準操作、undo / redo、選択可能なテキスト、iOS / iPadOS の表示。
- 制約: クリップボード権限や任意の他アプリへの書き込みを許可する仕様ではない。

### U08

- 著者・題名・年: Apple, *Human Interface Guidelines — Search fields*, 継続更新、2026-06-08 の変更履歴を含む。
- URL: <https://developer.apple.com/design/human-interface-guidelines/search-fields>
- 閲読範囲: best practices、scope / tokens、iOS の tab / toolbar / inline の配置とフォーカス。
- 制約: 掲載する最新の外観・動作について 26.0 の API availability を一括保証する資料ではない。検索アルゴリズムの採用根拠とも分ける。

### U09

- 著者・題名・年: Apple, *Human Interface Guidelines — Keyboards*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/design/human-interface-guidelines/keyboards>
- 閲読範囲: Full Keyboard Access、standard / custom shortcuts、入力ソース切り替え、修飾キー・locale の注意。
- 制約: 他 OS のショートカットも掲載するため、表全体を iOS の動作保証として使わない。

### U10

- 著者・題名・年: Apple, *Human Interface Guidelines — Virtual keyboards*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards>
- 閲読範囲: keyboard type / Return、custom input views と custom keyboards の区別、切り替え、iOS レイアウト。
- 制約: extension の全制約を列挙する API リファレンスではない。ホストアプリごとの対応は未検証。

### U11

- 著者・題名・年: Apple, *UITextInput.markedTextRange*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/documentation/uikit/uitextinput/markedtextrange>
- 閲読範囲: declaration、discussion、availability（iOS 3.2 以降）。
- 制約: 暫定テキストの意味を定義する API 資料。SwiftUI の特定入力部品の変換保持を実証したものではない。

### U12

- 著者・題名・年: Apple, *Improving app responsiveness*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/documentation/xcode/improving-app-responsiveness>
- 閲読範囲: overview の粗い時間目安、main thread、hang / hitch、variable refresh rate、Instruments、性能テスト、shipping app の診断。
- 制約: 時間の目安を SLA として使用しない。Swift concurrency のサンプルは選択するコンパイラ・言語モード・isolation 設定で再評価する。

### U13

- 著者・題名・年: Apple（Jed / Steven）, *Optimize SwiftUI performance with Instruments*, WWDC25, session 306, 2025.
- URL: <https://developer.apple.com/videos/play/wwdc2025/306/>
- 閲読範囲: 公式 transcript の全章（SwiftUI instrument、long body updates、cause & effect、next steps）と掲載コードの関連箇所。
- 制約: 動画そのものの視聴・サンプルの実行は未実施。Instruments 26 と対応する OS の準備が必要。説明例を nibble の採用アーキテクチャとはしない。

### U14

- 著者・題名・年: Apple, *Writing and running performance tests*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests>
- 閲読範囲: XCTest 計測、metrics、Release / test plan 設定、baseline / tolerance、失敗時の診断。
- 制約: XCTest の平均・baseline の判定を、全利用者・全端末の操作時間保証とはしない。製品の性能テストtargetとbaselineは未定義。検証用アプリにはSwift Testingのホストテストがある。

### U15

- 著者・題名・年: Apple, *MetricKit* / *MXMetricManager*, 継続更新（調査日版）。
- URL: <https://developer.apple.com/documentation/metrickit>、<https://developer.apple.com/documentation/metrickit/mxmetricmanager>
- 閲読範囲: framework overview の iOS 27+ API 紹介、従来 class の declaration / availability / overview / 受信例 / 実機注意。
- 制約: トップページの簡略な「一日最大一回」と、class の source ごとの配信説明を区別した。診断の受信・外部転送・実運用は未実施。新 API への移行や telemetry 基盤は未決定。

## 7. 根拠の適用範囲と追加調査

- KLM（Keystroke-Level Model）原著は本文未確認のため、係数や精度を設計根拠に含めない。操作の時間予測へ適用する場合は原著の条件を確認する。
- Jotaらの直接タッチ遅延研究は本文未確認。直接タッチによる遅延の知覚・操作への影響は追加調査対象とし、マウス研究の結果で代用しない。
- Altmann / Trafton (2007) は出版社の原著全文を [P03](experiments/primary-source-validation.md) で照合済み。戦術ゲームと30〜45秒の中断という実験条件をnibbleへ一般化せず、元の作業の再開も測る根拠として用いる。
- nibble と同じ利用場面でのスニペット再利用、日本語入力、片手操作、アクセシビリティの利用者調査は未実施。特定の論文だけから「あらゆるシーンでシームレス」を達成したと判断しない。
