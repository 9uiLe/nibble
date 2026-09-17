# 製品設計の研究資料

nibbleは、必要なテキストを素早く探してコピーし、作成・編集・削除を少ない操作で行うiPhone向けツールである。このディレクトリは、使いやすさ、原文保持、描画・応答性能、保守・復旧を判断するための一次資料、比較条件、研究用の実行結果を管理する。

製品の仕様は[製品設計（ADR 0002）](../docs/decisions/0002-mvp-app.md)、使い方と再現手順は[MVPの操作と検証](../docs/mvp.md)、製品で実施した確認は[MVPの検証結果](../docs/mvp-validation.md)を参照する。研究で取り上げるAPIや方式には、製品が採用しない候補も含む。

最低対応OSは**iOS 26.0**、実行検証は**iOS 26.5のみ**。26.0への適合はdeployment targetと個別APIのavailabilityで確認する。01〜05の一次資料と研究用実行結果の確認日は2026-09-13。06のUI設計資料は2026-09-17に確認した。MVPの実行評価はSimulatorに限定し、実機検証は受け入れ範囲に含めない。

## MVPの採用構成と研究の役割

| 領域 | MVPの採用構成 | 研究で比較・評価すること |
| --- | --- | --- |
| 利用と呼び出し | 一覧からコピーし、利用者が入力先へ戻ってペースト。標準ショートカットで一覧・作成URLを開く | hostごとの制約、App Intents・Controls・Keyboard・Widgetの便益と設定負担 |
| 取り込み | Share ExtensionでテキストまたはURLを1件保存 | hostが公開する形式、権限、共有元への復帰 |
| UI | SwiftUI + Observation、日本語UI、一覧検索、明示保存、下書き、削除・復元 | 探索・入力・誤操作・アクセシビリティと実機性能 |
| 非同期操作 | モデルのasync APIで処理と結果反映を待ち、UI所有者がTaskingで開始・寿命・重複を管理 | 完了契約、キャンセル・重複操作・応答 |
| 表示の更新 | AppMacrosで値だけを受け取る行を比較し、ScopedAnimationでアニメーション範囲を定義。構文は[実装規約](../docs/library-policy.md)に従う | 全表示入力と操作の整合性、外観・文字サイズへの追従、描画コスト、アニメーション伝播 |
| 保存 | Apple同梱SQLite、App Group、専用actor、WAL、revisionによる競合検出 | SwiftData・Core Dataとの比較、プロセス間の整合性、migrationと復旧 |
| 検索 | 原文と検索キーを分離し、日本語1文字から部分一致 | 正規化、FTS5、件数と検索の正確さ・遅延 |
| 保護 | completeのData Protection、端末内コピー、本文の自動収集なし | ロック・バックアップ・ログ・システム連携ごとの保護の実効性 |
| 同期・配布 | 同期なし。署名配布・審査はMVPの検証範囲外 | 同期の採用条件、配布・更新・プライバシー・運用要件 |

## 資料の読み方

| 資料 | 内容 |
| --- | --- |
| [01 呼び出し導線とiOSの境界](01-invocation-and-platform.md) | 本体、Shortcuts、Controls、Share / Action、Keyboard、Widget、リンクの能力と権限 |
| [02 データとアーキテクチャ](02-data-and-architecture.md) | 原文と更新の整合性、保存・共有、日本語検索、移行・復旧、任意同期 |
| [03 UI/UXと性能](03-ux-and-performance.md) | 探索・誤操作・作業復帰、入力とアクセシビリティ、応答・描画の測定 |
| [04 セキュリティ・配布・運用](04-security-distribution-and-operations.md) | 保存・コピー・公開範囲、プライバシー宣言、署名・配布、ライセンスと運用 |
| [05 製品の検証計画](05-decisions-and-validation.md) | MVPの評価と構成の見直しに使うV0〜V8の条件、証跡、採用判断 |
| [06 UI要素と画面構成の設計根拠](06-interface-design-evidence.md) | 2026-09-17確認のHIG・WWDC・W3Cと、部品・画面への適用限界。[UI設計](../docs/design/README.md)へ接続 |
| [iOS 26.5の研究用実行結果](experiments/ios-26-5-validation.md) | E01〜E25の観測、測定値、対象ソースと証跡、未実施条件 |
| [一次資料検証](experiments/primary-source-validation.md) | P01〜P13の文書上の契約、原著の閲読範囲、根拠の限界 |

Vは評価領域、Eは研究用アプリで実行した比較条件、Pは一次資料で確認する問いの識別子とする。[検証計画](05-decisions-and-validation.md)で対象の領域を選び、その仕様・研究・観測結果を照合する。

## 検証対象と責務

| 対象 | 役割 | 定義・手順 |
| --- | --- | --- |
| Nibble / NibbleShare | 製品の保存・画面・呼び出し・共有の確認 | [MVP手順](../docs/mvp.md)、[製品の結果](../docs/mvp-validation.md) |
| VerificationApp | 検証コマンド・文字列照合・撮影の成立を試験するfixture | [共通コマンド](../docs/ios-verification.md) |
| ResearchProbe | 同じダミーデータで保存3方式、検索、復旧、入力、コピー、OS連携を比較する | [研究用の構成と実行手順](../validation/RESEARCH.md) |
| 共通基盤とCI | Apple CLIでビルド・実行管理・撮影、sim-useで画面操作、Ubuntuで静的検査 | [基盤の設計](../docs/decisions/0001-local-ios-verification.md)、[開発ガイド](../CONTRIBUTING.md) |

ResearchProbeはUIKitの比較用画面とSwiftData・Core Data・SQLiteの保存実装を持つ。MainActorでの全件処理や比較用の画面配置は、その実験の条件である。製品のSwiftUI画面・SQLite actor・共有拡張とは対象を区別して結果を読む。

## 設計判断に使う知見

| 領域 | 根拠と適用範囲 |
| --- | --- |
| 呼び出し | 呼び出し・取り込み・他アプリへの挿入は異なる能力である。任意画面への重ね合わせや全入力欄への直接挿入を前提にせず、hostと入口の組み合わせを評価する。[01](01-invocation-and-platform.md) |
| Keyboardの共有領域 | AppleはFull AccessなしKeyboardのread-only利用を説明する。DB初期化・sidecar・移行・更新反映は実際のextensionで確認する。MVPはKeyboardを採用しない。[02](02-data-and-architecture.md)、P04 |
| 保存 | 3方式の基本CRUD・再読込は成立する。移行・プロセス間共有・実機性能は各条件で評価する。live WALを欠くDB本体だけのコピーをバックアップにしない。E01〜E09 |
| 日本語検索 | trigram MATCHでは1〜2文字の日本語検索が一致しない。MVPは原文と検索キーを分け、`instr`による部分一致を採用する。E10〜E12 |
| 操作と表示 | コピーから元の作業の再開までを評価する。ResearchProbeの縦配置は小画面・最大文字サイズ・キーボード併用で本文が切れる。製品のスクロール可能な編集画面は製品側の証跡で評価する。E24、[03](03-ux-and-performance.md) |
| システム連携 | Shortcutsへの登録と実行成功は別の条件である。ResearchProbeの前景アクションは実行失敗・原因未特定。MVPの標準URLアクションによる作成は製品側で確認する。E25 |
| 保護と運用 | Data Protection、ロック、コピー、同期で保護範囲が異なる。コピー期限は他アプリに保存した内容を回収しない。配布物のAPI・SDK・データフローと宣言を照合する。[04](04-security-distribution-and-operations.md) |
| 性能 | Simulatorの値は記録した構成・データに対する観測値である。実機の起動・入力・描画・メモリの性能保証には使わない。[03](03-ux-and-performance.md) |

## 評価の限界と更新

研究用の未実施条件は[研究用実行結果](experiments/ios-26-5-validation.md)、製品の未検証項目は[MVPの検証結果](../docs/mvp-validation.md)で管理する。実機性能・ロック時の保護、利用者試験、支援技術、同期、署名配布にはそれぞれ固有の条件がある。KLMとJotaの原著本文は未取得であり、係数や効果量を設計根拠に使わない。

- **事実**は公式API文書、WWDC transcript、言語・SQLite等の一次資料、原著論文で確認した内容を指す。
- **設計への示唆・推奨**は事実をnibbleへ適用する候補を指す。採用構成はADRを正とする。
- **観測結果**は記録した端末・OS・ソース・データ・権限の条件に限って解釈する。
- **未確認・未決定**は実験または製品判断が必要な条件を指す。MVPの対象外機能と、採用済み機能の未検証項目を区別する。

資料台帳にはURL、著者・発行主体、日付、閲読範囲、適用限界を記す。DocCの公式JSON本文とmetadata、動画のtranscriptと視聴、書誌と原著本文を区別する。外部の文書全文を転載せず、要約・分析・出典をGitで管理する。

生成ログ・画像・動画はGit管理対象外の`artifacts/`に保存し、レビュー可能な証跡をPRへ添付する。OS・SDK・schema・呼び出し・プライバシー方針を変更するときは、関連する根拠・検証条件・ADRを合わせて更新する。
