# 非同期処理とアニメーションの実装規約

nibbleは、非構造化タスクをswift-tasking、アプリが指定するアニメーションをswift-scoped-animationで管理する。本体、共有拡張、テスト、研究用アプリ、検証用Swiftコードに同じ規約を適用する。処理の所有者・終了条件・重複実行方針と、表示変化の適用範囲をコードから判断できることを目的とする。

製品の画面・データ・操作ごとの契約は[製品設計](decisions/0002-mvp-app.md)、実施した確認は[Tasking・ScopedAnimationの検証結果](library-policy-validation.md)に記載する。この文書は実装に使う入口、禁止API、依存管理、規約の検査方法を定義する。

## 依存とビルド

| パッケージ | 固定版 | 使用するproduct | 対応条件 |
| --- | --- | --- | --- |
| [swift-tasking](https://github.com/9uiLe/swift-tasking/tree/0.3.0) | 0.3.0 | `Tasking`の`ViewTaskStore`、`TaskingCore`の`TaskSlot` | Swift tools 6.0、iOS 13以上 |
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.1) | 0.2.1 | `ScopedAnimation` | Swift tools 6.2、iOS 17以上 |

製品のdeployment targetは26.0、検証ツールチェーンはXcode 26.5 / Swift 6.3.2とする。本体と共有拡張には両パッケージの同じ版をリンクする。構造化された処理だけを持つ研究・基盤targetには不要なproductをリンクしない。

Xcode projectはexact versionを指定し、`app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`にrevisionを固定する。初回の依存解決はネットワーク接続のあるMacで次を実行する。通常のビルドでもXcodeが解決する。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

両パッケージはMITライセンスで、追加の外部パッケージを持たない。本体と共有拡張のbundleに`ThirdPartyNotices.txt`を含める。補助ツールはNix、アプリのSwift PackageはXcode / SwiftPMで管理する。

## 非同期処理の入口

| 処理の形 | 使用する入口 | 設計時に決めること |
| --- | --- | --- |
| Button・UIKit callbackから開始するUI操作 | 所有者に保持した`ViewTaskStore.start` | ActionID、lifetime、重複方針、終了イベント、キャンセル位置 |
| 非UIの単一処理を置換・終了する所有者 | `TaskingCore`の`TaskSlot` | slotの保持期間、開始・置換・キャンセルの条件。MVPのUI操作にはViewTaskStoreを使う |
| 呼出元のasync処理内で完結する処理 | `async/await`、`async let`、task group | actor隔離、子処理の完了とエラー伝播 |
| SwiftUIが寿命を管理するview処理 | `.task` / `.task(id:)` | viewの終了・ID変更でキャンセルしてよい処理か |
| 既存タスクの待機・協調的な中断確認 | `Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority` | キャンセルを観測する中断点と結果反映の条件 |

Taskingの[設計方針](https://github.com/9uiLe/swift-tasking/blob/0.3.0/README.md)に従い、構造化された処理はその親子関係を利用する。actor、continuation、`CancellationError`も使用できる。データ層のasync APIはUIのタスク所有から独立させる。

## 所有・寿命・重複実行

`ViewTaskStore`はmodelまたはviewの状態として保持する。開始箇所だけの一時変数にはしない。`ActionID`は同じ操作を識別する値とし、項目ごとに独立した操作はUUIDを含める。`cancelExisting`は同じIDの処理をキャンセルして新しい要求を受理し、`ignoreNew`は実行中の同じIDへの要求を抑止し、`allowConcurrent`は複数の要求を受理する。

一覧読込の実装例では、LibraryModelが所有するstoreを使う。

```swift
private let tasks = ViewTaskStore()
private static let refresh: ActionID = "library.refresh"

func reload() {
    tasks.start(id: Self.refresh, lifetime: .sceneBound, policy: .cancelExisting) { [weak self] cancellation in
        try cancellation.check()
        await self?.refresh()
    }
}
```

`ActionLifetime`は分類用の値であり、画面・sceneのイベントを自動監視しない。所有者が`cancel(lifetime:)`をイベントへ接続する。製品では次の境界を使い、操作ごとのID・重複方針は[製品設計の一覧](decisions/0002-mvp-app.md#操作の寿命と整合性)を正とする。

- 一覧modelはscene内のルートviewの`@State`が保持する。読込・コピー・項目更新はsceneBoundの有限処理で、シート表示や一時的な非active化をまたぐ。
- 一覧のbackground化では`endScreen()`を呼び、その時点のscreenBound操作である編集開始と通知消去をキャンセルする。通知と取り消し操作も消去する。viewの表示・非表示を一覧modelの終了条件にはしない。
- 編集の保存・閉じる・破棄は同じ終了操作IDで扱い、`SnippetEditor.onDisappear`でキャンセルする。共有provider読込は`ShareViewController.viewDidDisappear`でキャンセルする。
- 下書き書込は入力snapshotを受理し、SQLiteのsequence比較で最新値を保持する。入力更新を取り消す目的で書込をキャンセルしない。

## キャンセル・結果・エラー

キャンセルは協調的な停止要求であり、DBの確定済み変更を取り消さない。画面表示、pasteboardへの書込、永続化の完了を同じ停止条件で扱わず、各操作の契約を守る。

| 対象 | 結果を扱う規則 |
| --- | --- |
| 検索 | 返却時に要求世代とキャンセル状態を確認し、古い検索で最新状態を上書きしない |
| コピー | DB読込の前後でキャンセルを確認し、保存済み本文だけをpasteboardへ反映 |
| 下書きの開始・更新 | 受理済みDB処理を完了させる。入力sequenceで順序を判定し、除去済み下書きを遅れた更新で再生成しない |
| 保存・閉じる・破棄 | 永続化が成功したら、途中でキャンセルを受けても対応する終了通知を返す |
| provider読込 | 読込の前後でキャンセルを確認し、キャンセルを業務エラーとして表示しない |
| 業務エラー | modelの表示状態へ変換し、入力を保持して再試行・競合からの回復を可能にする |

storeへ流出した非キャンセルエラーはDebug assertionの対象になる。空のcatchで業務エラーを消さない。キャンセルだけを正常な終了として扱うcatchと、利用者へ通知すべき失敗を区別する。

## アニメーションの境界

表示変化の適用範囲を名前付き`AnimationScope`で囲み、valueによる変更検知またはproxyの`scope.animate`を使う。複数triggerのfactoryは`AnimationTrigger.animation`と型名を明記する。入力領域など親のアニメーションを受けない部分には`.animationBarrier()`を使う。

製品の通知scopeは`Library.Notice`とし、通知の有無をvalueで検知する。表示・消去は0.16秒のopacity遷移、Reduce Motion有効時はduration 0秒とする。通知本文の更新と表示の有無を区別し、scopeは必要な表示部分に限って配置する。

LibraryViewとSnippetEditorの外側に`.animationBarrier(warnsOnLeaks: false)`を置き、OSのシートtransactionをアプリ内容へ伝えない。その内側の`.detectAnimationLeaks()`と、編集入力領域の警告付きbarrierでアプリ内部の漏れをDebug実行時に診断する。ローカルscopeは自身のアニメーションを適用する。標準シート・メニュー・キーボード自体の遷移はOS部品が管理する。

診断対象はmodifierの位置へ届くtransactionであり、子孫すべての表示変化やUIKitを自動検査する機能ではない。scopeも同じ状態更新に付随する変化を自動分離しない。適用範囲、Reduce Motion、入力・スクロール・遷移はスクリーンショットと録画で確認する。

## Lintと禁止する直接使用

```sh
# 規約の単独検査
nix develop --command python3 scripts/check_swift_policy.py

# Lintの回帰テストを含む共通検査
nix flake check --no-update-lock-file --print-build-logs
```

`swift-library-policy`はNixのPythonで動き、ローカルとUbuntu CIで同じ規則を使う。違反にはファイル・行・列を表示し、終了コード1で失敗させる。抑制コメントやファイル単位の例外は設けない。

| 禁止対象 | 代表例と代替 |
| --- | --- |
| 生のTask生成・保持・別名・関数参照 | `Task {}`、`Task.detached`、`Task<…>.init`、Task型handle。`ViewTaskStore` / `TaskSlot`を使う |
| 別の直接scheduler | `DispatchQueue`、`DispatchWorkItem`、`DispatchSource`、`OperationQueue`、`BlockOperation`、`Thread`、`Timer`。Taskingに所有させ、待機には協調的なsleepを使う |
| SwiftUIの直接指定 | `withAnimation`、`withTransaction`、`Transaction`、`.animation`、`.transaction`、`.phaseAnimator`、`.keyframeAnimator`。scope / proxy / barrierを使う |
| UIKit / Core Animationの直接指定 | `UIView.animate`・`transition`等、`UIViewPropertyAnimator`、CAAnimation系、`CATransaction`等。製品のアニメーションをscopeで設計する |

正確な名前の集合は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)を正とする。予約した名前は別用途にも使わない。SQLiteのprivate helperには`writeTransaction`という名前を使う。

検査対象はリポジトリのSwiftファイル全体で、新しいsourceディレクトリも再帰的に探索する。`artifacts`、`.build`、`DerivedData`等の生成物は除外する。依存コードは`artifacts`以下に取得し、ライブラリ内部の標準API実装を製品コードの違反にしない。Swift sourceとsource directoryのsymlink、読めない入力、対象0件はエラーとする。

字句解析はコメント・通常/raw/複数行文字列・regexの本文を読み飛ばし、実行される補間は検査する。改行・コメントを挟む呼出し、修飾名、backtick、型aliasの宣言も規則の対象とする。Swiftの型解決やmacro展開を行う検査ではないため、独自macro、別名を通じた動的な呼出し、未知のAPIまで網羅する保証はない。Lint自体の変更と新しい入口の導入では、規則と回帰テストを併せてレビューする。

## 採用理由と保守

画面ごとに生のTask handleとanimation transactionを管理する構成では、寿命・重複・適用範囲の実装が分散する。TaskingとScopedAnimationはこれらを共通APIで宣言できる。一方で外部APIへの追従、Swift tools要件、操作ごとの管理コストを負う。独自wrapperを重ねず、データ層のasync APIを独立させ、置換が必要な範囲をUI所有者とscopeに絞る。

依存更新ではexact version・共有lock・ライセンスを同時に確認し、重複操作、キャンセル、入力直後の保存、共有元への復帰、通知と入力へのアニメーション伝播をiOS 26.5で検証する。保守停止、対応OS・ツールチェーンの不適合、測定した応答・描画の悪化、scopeで必要な表現を扱えない場合を採用の見直し条件とする。測定結果は記録したライブラリ版と条件に限って解釈する。
