# 収益と機能アクセス

nibbleは保存件数で利用を制限しない。利用者は本文を端末内に保存し、検索、コピー、キーボード挿入、変数の差し替えを使える。課金は継続的な価値がある機能に設定し、保存済みの原文や下書きの所有権を変更しない。利用者から見た契約は[製品仕様](../product-specification.md#無料機能とnibble-pro)、表示は[画面構成](../design/screens.md#s04-設定)で定める。

## 機能と提供状態

| 機能 | 無料 | Pro | 実装上の判定 |
| --- | --- | --- | --- |
| 保存・検索・通常のコピー・キーボード挿入 | 利用できる。保存件数に上限はない | 同じ | 保存層にプラン判定を置かない |
| 変数の作成・再利用・差し替え | 利用できる | 利用できる | `FeatureAccess.availability(.variableReplacement, pro:)` |
| 広告なし | 広告配信開始時は対象外 | 対象 | `FeatureAccess`の`.adFree`。広告SDKと広告枠は未接続 |
| サブスクリプション購入 | 販売を開始するまで表示しない | 検証済みの権利を表示・管理できる | `FeatureAccess.subscriptionsOffered`とStoreKitの商品取得 |

[FeatureAccess.swift](../../app/Shared/Domain/FeatureAccess.swift)は機能ごとの対象と販売状態を一つの`FeaturePolicy`にまとめる。`included`は利用可能、`requiresPro`は販売中のPro権利が必要、`unavailable`は購入によっても利用できない状態を表す。本体、共有拡張、キーボードは同じ判定を使う。利用条件を変える場合は、追加入口、利用直前の判定、設定の説明、該当テストを同じ変更で更新する。利用不可になった変数を含む本文も原文のまま編集・保持でき、コピーや挿入では印を送らず理由を示す。

変数は無料で利用できるため、保存・編集・利用の入口で同じ利用資格を示す。印の作成と利用、原文と完成文の境界は[変数の編集と利用](variables.md)が定める。

## 権利と商品

本体の[ProSubscription.swift](../../app/Nibble/Monetization/ProSubscription.swift)はStoreKitが検証した現在の権利と取引更新を読み、期限付きのPro状態をApp Groupへ反映する。`ProAccess`はその共有スナップショットを本体と拡張へ渡す。拡張は購入や復元を開始しない。設定の[ProView.swift](../../app/Nibble/Settings/ProView.swift)は権利の確認、登録管理、販売中の商品取得と復元入口を担当する。表示価格と期間はStoreKitの商品情報を使う。

scene復帰と取引更新からの権利再取得が重なった場合、最後に開始した有効な要求だけが共有スナップショットへ反映する。取消済みの要求は反映しない。商品取得は設定画面の表示期間に属し、画面を離れた要求や旧再読込の結果で新しい商品表示を上書きしない。

App Store Connectの商品IDは月額`nibble.pro.subscription.monthly`、年額`nibble.pro.subscription.yearly`である。日本の設定価格は月額300円、年額2,400円。販売には継続的な提供内容、商品説明、公開用の規約とプライバシーポリシーを用意する。保存データは端末内にあり、Apple Accountによる権利の復元は本文の同期を意味しない。

## 広告と計測

無料版へ広告を配信する場合は作業画面の閲覧中に限る。編集、変数入力、検索、キーボード、コピー完了には広告を置かない。[AdvertisingContent.swift](../../app/Nibble/Monetization/AdvertisingContent.swift)が作業画面用の表示を供給し、[AppRootView.swift](../../app/Nibble/Navigation/AppRootView.swift)が画面状態とPro権利で表示資格を決める。`UnconfiguredAdvertising`は何も返さず、空の広告枠も作らない。広告事業者と広告枠ID、公開用プライバシーポリシー、必要な同意表示が揃うまで広告SDKをリンクしない。

本文、検索語、画面操作の履歴を外部analyticsへ送らない。購入・継続の集計はApp Store Connect Analyticsを使う。広告導入時は広告事業者の収益レポートとApp Store Connectの購入集計を分けて読む。アプリ内イベントを計測する場合は、収集項目、保存期間、同意、公開文書を製品仕様に定義してから実装する。

## 開発と検証

機能の対象を変更する作業では、`FeaturePolicy`の両方の権利状態、未販売状態、変数を含む保存済み本文の扱いを[NibbleTests](../../app/NibbleTests/SnippetStoreTests.swift)で確認する。保存件数の無制限性は31件を超える保存と編集・復元で確認する。StoreKitの購入、取消、復元、期限切れはSandbox/TestFlightで商品とApple側の状態を使って別に確認し、単体テストの成功を購入の成立とみなさない。実行手順は[検証](../ios-verification.md)、配布手順は[TestFlight](../testflight.md)に従う。
