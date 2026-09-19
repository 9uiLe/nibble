# 製品の検証範囲

検証の担当範囲と未確認条件を示す。実行結果はrunの対象ソースとともに記録し、現在のcheckoutが合格済みかは[証跡手順](review-evidence.md)で照合する。テストやdriverが存在することは、この版で実行したことを意味しない。

## 確認する契約と入口

| 範囲 | 検査・手順 | 保証するもの / 保証しないもの |
| --- | --- | --- |
| 保存と操作 | 製品Swift Testing、[MVP手順](mvp.md#開発環境とビルド) | 永続化、競合、直接await後の状態。実画面やOS権限は別 |
| View | hostedテストと[比較規約](library-policy.md#viewの比較境界) | 入力変更・復元、Binding差し替え、環境更新。全画面の可読性は別 |
| 本体の基本操作 | `check-mvp-ui.py` | 作成、下書き、検索、コピー、ピン、復元、設定。説明イラストは専用driver |
| 表示方針 | `check-interface-ui.py` | 通常と最大文字・高コントラストで製品の配置を固定。最小文字はhostedテストで確認 |
| About・利用案内 | `check-about-ui.py`、`check-keyboard-guide-ui.py` | 導線・説明・Rive表示。GPUやフレーム時間の改善は別 |
| 結果通知 | `check-notice-ui.py` | 内容と期限、検索focus、通知前後の座標。音声・触覚は別 |
| 共有・呼び出し・IME | [MVP手順](mvp.md)の実操作 | 原文と対象UUID、入力先への受け渡し。貼付はIMEの代替にならない |
| Keyboard | [操作手順](mvp.md#キーボードの操作検証) | 行挿入、全文、コピー・ピンの権限、復帰、ページ。ホストごとの受理は別 |
| 基盤fixture | [共通手順](ios-verification.md) | 実行・入力・撮影の成立。製品の機能や品質は別 |
| 比較実験 | [ResearchProbe](../validation/RESEARCH.md) | 明示した条件の方式比較。製品targetの合格には使わない |

## 判断に使う測定

- [保存層と配布容量](product-architecture-validation.md)：索引・SQL再利用とサイズ最適化を含む構成の比較。
- [Keyboard](keyboard-readability-validation.md)：モデル・SQLiteの応答、全文や挿入を検査する際の限界。
- [性能手順](performance-verification.md)：測定の成立条件とSimulatorのInstruments障害。

いずれも対象版・条件を限定した値であり、新しいcheckoutの性能を保証しない。

## 検証範囲の制約

MVPの実行評価はiOS 26.5 Simulatorのみ。実機の触覚・熱・電力・ロック時保護・Handoff・ホストごとのKeyboard受理は未確認。署名・送信は[TestFlight](testflight.md)の工程で、Apple側の配信と端末での受け入れは配布担当者が確認する。

VoiceOver音声と通知順、Voice Control、Switch Control、全画面の横向き、複数scene、長時間利用、1 MB本文の入力追従は未確認。AXのラベルや座標は、これらの操作成立を証明しない。説明イラストは製品方針でReduce Motionへ追従しないため、OS設定との一致を受け入れ条件にしない。

画面の発見性・片手操作・誤操作・復旧の理解は[UI評価課題](design/audit.md)で評価する。自動driverの所要時間を利用者のタスク時間として扱わない。実施した観測、抽出フレーム、全編再生、添付先の閲覧は区別して申告する。
