# 保存と日本語検索の選択根拠

nibbleはApple同梱SQLiteをApp Groupで共有する。採用した状態・transaction・復旧の契約は[製品設計](../docs/decisions/0002-mvp-app.md)、実測は[方式比較](experiments/ios-26-5-validation.md)に定める。一次資料の確認日は2026-09-13。

## SQLiteを選ぶ理由

本体・共有拡張・Keyboardの別プロセスで、原文、下書き、版の競合を明示的に扱う。SQLiteはtransactionと取得範囲を直接制御でき、既存DBの読取と限定的なピン更新を分離できる。SwiftData/Core Dataはモデル管理・移行・履歴を提供するが、共有containerだけでは別プロセスの表示更新や競合UIまで自動解決しない。[D01][D06][D07][D09]

ResearchProbeでは3方式の保存・原文保持が成立したが、単発の全件取得速度だけを採否の根拠にはしない。現在の索引とSQL再利用の判断には[製品保存層の比較](../docs/product-architecture-validation.md)を使う。同期・export/importはMVPの機能に含めない。

## App GroupとWAL

Full Accessなしの共有領域読取はUIKitの契約である。[D20] DBライブラリがsidecar・lock・migrationをどう扱うかは別の条件になる。本体がDBとWAL/SHMを用意し、Keyboardは初期化・移行をせず、未知schemaや不足データを空ストアへ置き換えない。

WALは永続状態の一部であり、稼働中のDB本体だけをコピーするとコミット済み値を失う可能性がある。調査用の整合した複製にはSQLite Online Backup APIを使う。[D14][D16] この方法をSwiftData/Core Data管理下の内部DBへ直接適用する保証はない。

SQLite upstreamのWAL-reset修正がApple同梱版へ含まれるかは未確認。`sqlite_version()`だけから修正済みとは判断しない。OS更新時や長期競合の調査ではsource ID・compile options・再現条件を記録する。[D14]

## 原文と検索値

Swiftの文字列等価とUTF-8の完全一致は異なる。保存・コピーする原文を正規化せず、検索値だけへNFCと日本語localeのcase/width foldingを使う。ひらがな/カタカナと清音/濁音を区別するのは製品判断で、Unicode正規化が決める検索仕様ではない。[D17][D18]

FTS5のunicode61は単語単位で、trigramのMATCHは1〜2文字の部分一致を満たさない。日本語1文字からの検索を優先し、製品は正規化した値への部分一致を採用する。[D15] ResearchProbeの「東」「東京」「東京都」の比較でもこの差を確認した。大きなデータでの走査時間は別途測定し、LIKEで結果が返ることを索引が効くことと混同しない。

## 出典

[D01]: https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches
[D06]: https://developer.apple.com/documentation/xcode/configuring-app-groups
[D07]: https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes
[D09]: https://developer.apple.com/documentation/swiftdata/fetching-and-filtering-time-based-model-changes
[D14]: https://www.sqlite.org/wal.html
[D15]: https://www.sqlite.org/fts5.html
[D16]: https://www.sqlite.org/backup.html
[D17]: https://www.unicode.org/reports/tr15/tr15-57.html
[D18]: https://developer.apple.com/documentation/foundation/nsstring/folding(options:locale:)
[D20]: https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
