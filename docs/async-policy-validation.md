# 非同期API境界の検証

実施日：2026-09-15。[実装規約](library-policy.md)に定義した「操作を完了までawaitでき、UI側がタスク開始を選ぶ」契約を対象とする。本体・共有拡張・テストのソースは`16868e6`。`89cf8ff`はLintとその回帰テストだけを変更している。

## 環境と自動検査

Xcode 26.5 / Swift 6.3.2、iOS 26.5（23F77）Simulatorで実行した。最低対応OSは26.0。swift-tasking 0.3.0・swift-scoped-animation 0.2.1の固定版を使用する。

| 検査 | 結果と対象 |
| --- | --- |
| Nix共通検査 | `nix flake check --no-update-lock-file --print-build-logs`。workflow-policy・nix-format・ios-tooling・swift-library-policyの4 check |
| Python回帰テスト | 33件成功。うち20件がSwift規約、13件がiOS検証基盤 |
| Swift規約 | 本体・拡張・テスト・研究・基盤を含む17ソースに違反なし |
| 違反の検出 | 同期メソッドやsetter内でタスクを開始する違反例として、`058db92`のLibraryModel・EditorModel・SnippetEditorを構文Lintへ渡し、計11件の違反を検出。通常メソッド、setter、async内部の開始、storeの注入・別名化、開始メソッドの関数参照、任意closure・task内の再開始を回帰テストでも拒否 |
| 製品Releaseテスト | SE第3世代、UDID `A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`。26件成功、失敗・skipなし。run `20260915T113315Z-test-9cefc6` |
| 本体・拡張のDebugビルドと実行 | 17 Pro、UDID `114E57E6-E37D-4F50-907A-8B0B6B03C92E`。成功。run `20260915T113645Z-run-07f76a` |
| 本体・拡張のReleaseビルドと実行 | 17 Proの基本操作driverによるbuild・install・launchが成功 |

製品テストはコミット前の作業ツリーで実行した。manifestの全`app/`ファイルのSHA-256が`16868e6`と一致することを確認済み。画像・動画の対象も同じ製品ソースである。以下のrun IDは、Git管理対象外の`artifacts/ios/`内にあるmanifest・実行ログ・画像・動画を識別する。Ubuntu 24.04でも同じlockと共通コマンドを実行し、文書を含む`08ce0f7`で[4 checkの成功](https://github.com/9uiLe/nibble/actions/runs/34965595988)を確認した。

`AwaitableOperationTests`の7件は、モデルを直接awaitした時点の結果、入力setterがDBを変更しないこと、明示的なsnapshot保存と世代順序、即時保存・破棄と遅い自動保存、キャンセル済み呼出元、最新検索、独立した通知期限を検査する。`OwnedActionTests`は実際の`LibraryTaskOwner`を使って寿命と重複方針を検査する。操作のテストにmodel内部のタスク完了待ちやポーリングは使わない。

## 操作・画像・動画

17 Pro、標準文字サイズ・ライト外観、ダミーの日本語・空白・改行・結合文字・絵文字を使用した。画面の読取・入力・操作はNixのsim-use、撮影はAppleのsimctl。画像5点と動画6本の添付先は[PR #7](https://github.com/9uiLe/nibble/pull/7)。2026-09-14の証跡は[別のソースでの記録](library-policy-validation.md)として扱う。

| 導線 | 結果 | run ID |
| --- | --- | --- |
| 基本操作、Release | 作成・コピー・検索・編集・閉じる・ピン・削除・復元・下書き破棄を操作。コピーのUTF-8と復元UUIDが一致 | `20260915T114321Z-mvp-ui-dbb484` |
| 入力直後に閉じる、Release | 本文の貼付後、待機を追加せず閉じる。下書きを再開して保存し、コピーの空白・改行・Unicodeが完全一致 | `20260915T114734Z-async-draft-close-9bf0a6` |
| Safari共有、Debug | 本文をnibbleへ共有して保存、Safariへの復帰を確認。本体で一意のタイトルを検索し、コピーのUTF-8が一致 | `20260915T114242Z-async-share-c011bf` |
| 通常の通知、Debug | 5回のcold start、コピー2回の通知更新、最後の操作後の消去、編集開閉が成功 | `20260915T113754Z-scoped-notice-disabled-7d6961` |
| Reduce Motionの通知、Debug | 設定のselectedを確認し、5回のcold start、通知更新・消去・編集開閉が成功。終了後は無効へ復元して読取で確認 | `20260915T113935Z-scoped-notice-enabled-165d95` |
| 再起動、Release | 2回のcold startで保存済みUUIDを表示 | `20260915T114822Z-owned-cold-start-02c2e0` |

基本操作は`nix develop --command python3 scripts/check-mvp-ui.py --device <17 ProのUDID>`で再現できる。共有・表示設定の操作は[MVP手順](mvp.md)を参照する。下書きの追加確認は「新規作成 → 一意のタイトルと本文を入力 → 直後に閉じる → 同じ下書きを再開 → 保存 → タイトル検索 → コピー」を行う。

TextFieldのアクセシビリティ値は、この環境では本文の前後空白を省いて返した。初回run `20260915T114556Z-async-draft-close-0c7b22`は、この表示値へ原文の完全一致を要求して失敗した。保存済みDBの原文保持を確認した上で、表示は本文の読取、原文の完全一致は保存後のpasteboardで検査するdriverに修正し、成功runを取得した。失敗runを成功へ書き換えていない。

静止画と動画の時刻付き抽出フレームで、入力の保持、保存・閉じる、一覧への復帰、通知の表示・消去、共有元への復帰を確認した。全フレーム解析や人間による動画全編のリアルタイム再生は実施していない。録画にはdriverの待機・画面読取が含まれ、動画の長さを応答性能へ換算しない。

## 診断・測定と制約

Debug実行開始の2026-09-15 20:36:45 JST以降、対象導線で本体・拡張の`ScopedAnimation`カテゴリと`Unhandled ViewTaskStore`をAppleのlog showで検索した結果は0件。これは対象の診断位置と実行導線の結果であり、全タスク・全transactionの保証ではない。

SE / iOS 26.5 / Release、同じ本文・件数・SQL・先頭100件取得、各条件30回の検索テストで、10,000件の結果は次のとおり。測定区間はSQLite actorへの要求から返却まで。

| 検索語 | `8473b36`・2026-09-14 中央値 / 最大（ms） | `16868e6`・2026-09-15 中央値 / 最大（ms） |
| --- | --- | --- |
| 東 | 0.1254 / 0.2040 | 0.1193 / 0.1792 |
| 見つからない語句 | 4.7760 / 7.4709 | 4.2217 / 4.4165 |

検索SQLは同一で、ホスト負荷を含む異なる実行間の観測である。タスク開始・IME・View更新・描画を含まず、この差を非同期APIやTaskingによる性能改善とは判断しない。生データは`artifacts/async-search-timing.json`。

Lintは構文の制限であり、外部APIの副作用、型解決、macro展開を保証しない。実機検証・署名配布は受け入れ範囲外。実機hitch、UIフレーム時間の定量比較、VoiceOverの読み上げは未実施。製品全体の評価範囲は[MVPの制約](mvp-validation.md#検証範囲の制約)を参照する。
