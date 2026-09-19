---
name: nibble-verification
description: nibbleのiOS検証を実行する、検証結果と証跡を照合する、PRを作成・更新するときに使う。静的検査だけの作業には不要。
---

# nibbleの検証とレビュー

対象ソースを実行し、結果・媒体・PRの対応を確認するための入口である。[開発ガイド](../../../CONTRIBUTING.md)が必要な検査、[証跡手順](../../../docs/review-evidence.md)が照合方法と合格条件を定める。

## 工程と適用範囲

| 依頼 | 手順 | 成果物 |
| --- | --- | --- |
| 変更に必要な検証の計画・実行 | [変更から検証](../../../docs/ios-verification.md#変更から検証を実行する) | 選択・除外理由、工程結果、ソース・媒体を照合したrun |
| 製品のビルド・操作 | [MVP手順](../../../docs/mvp.md) | Nibbleの対象導線を確認したrun |
| 実行基盤の確認 | [共通iOS手順](../../../docs/ios-verification.md) | VerificationAppのrun。smokeはこのfixture専用 |
| 保存・OS連携の比較実験 | [ResearchProbe](../../../validation/RESEARCH.md) | 比較条件と期待結果を持つ研究run |
| runの利用・再利用 | [ソース照合](../../../docs/review-evidence.md#runのソースと結果) | 対象revisionへのintegrity検査 |
| 画像・録画のレビュー | [レビュー記録](../../../docs/review-evidence.md#画像動画のレビュー記録) | 観測・未実施条件・閲覧条件を記したreview.json |
| PR作成・更新 | [PR照合](../../../docs/review-evidence.md#pr本文の作成と照合)、[テンプレート](../../../.github/pull_request_template.md) | 全コミットと最終headを照合した本文・CI結果 |

runは1回のiOS実行のソース・端末・コマンド・成否・媒体をまとめた記録であり、Git管理外のartifactsへ保存する。失敗runを成功で上書きしない。文書だけのPRにiOS実行・撮影は不要だが、既存runを使うならファイル照合が必要となる。

通常は`verify.py plan/run`を入口とし、個別コマンドを重複実行しない。成功後の追加変更は`--since`で再計画する。計画に記載した手動条件・媒体の目視・未解決の懸念は、自動工程の成功とは別に確認する。

## 完了条件

依頼された工程の成果物をそろえ、実施と未実施を区別する。動画の抽出確認、全編再生、公開、ブラウザー閲覧を相互に代用しない。自動検査は形式と整合性を確認し、観測の真実性やUXを証明しない。

PRはコミット済み差分へのlocal検査、公開後のremote検査と最終headのCIを確認する。本文はbody-fileで改行と添付URLを保持する。PR作成にマージを含めない。ローカル確認・媒体公開・PR・TestFlightは依頼された範囲で選び、承認済みの工程を再確認しない。
