# 設計判断の根拠

製品仕様は[製品仕様・要件](../docs/product-specification.md)と[UI設計](../docs/design/README.md)を正本とする。このディレクトリは、その判断に使う外部の制約・方式比較・適用限界を保持する。研究用コードの存在は製品の採用を意味しない。

| 判断すること | 根拠 |
| --- | --- |
| 呼び出し・共有・挿入の能力と権限 | [OSの境界](01-invocation-and-platform.md) |
| SQLite、原文、日本語検索の選択 | [保存と検索](02-data-and-architecture.md) |
| 操作効率の評価方法 | [利用者評価の根拠](03-ux-and-performance.md) |
| データの露出、配布申告、ライセンス | [保護と公開の条件](04-security-distribution-and-operations.md) |
| UIの指針と製品判断の区別 | [R番号の一次資料台帳](06-interface-design-evidence.md) |
| 保存方式・検索・OS機能の比較値 | [ResearchProbeの知見](experiments/ios-26-5-validation.md) |

資料には確認日と適用限界を付ける。外部規約は提出時、APIは採用時に確認し、未確認を仕様へ変えない。比較実験の再実行は[研究手順](probe/README.md)、製品の確認は[製品の検証手順](../docs/ios-verification.md)と[検証範囲](../docs/testing.md#検証範囲と制約)に従う。
