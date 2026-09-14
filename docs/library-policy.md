# 非同期処理とアニメーションの実装規約

nibbleの非構造化タスクはswift-tasking、アプリが指定するアニメーションはswift-scoped-animationで管理する。本体、共有拡張、テスト、研究用アプリ、検証用Swiftコードに同じ規約を適用する。目的は、処理の所有者・終了条件・重複実行方針と、アニメーションの適用範囲をコードから判断できる状態にすること。採用状態は「採用」、決定日は2026-09-14。

## 依存とビルド

| パッケージ | 固定版 | 使用するproduct | 対応条件 |
| --- | --- | --- | --- |
| [swift-tasking](https://github.com/9uiLe/swift-tasking/tree/0.3.0) | 0.3.0 | UIは`Tasking`。非UIの所有者には`TaskingCore`の`TaskSlot` | Swift tools 6.0、iOS 13以上 |
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.1) | 0.2.1 | `ScopedAnimation` | Swift tools 6.2、iOS 17以上 |

製品のdeployment targetは26.0、確認するツールチェーンはXcode 26.5 / Swift 6.3.2とする。両パッケージの最低OSは製品の条件を満たす。本体と共有拡張で同じ版をリンクし、テストから製品の所有者を直接検査する。構造化された処理だけを持つ研究・基盤targetに不要なproductをリンクしない。

Xcode projectではexact versionを指定し、`app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`にrevisionを固定する。初回の依存解決は次のApple CLIで行う。通常のビルドでもXcodeが解決する。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

両ライブラリはMITライセンスで、追加の外部パッケージを持たない。本体と共有拡張のbundleに`ThirdPartyNotices.txt`を含める。補助ツールはNix、アプリのSwift PackageはXcode / SwiftPMで管理する。

## 非同期処理の境界

同期的なButtonやUIKit callbackから非同期処理を開始するときは、所有者に保持した`ViewTaskStore.start`を使う。呼び出しごとに`ActionID`、`ActionLifetime`、`TaskStartPolicy`を指定する。非UIの単一処理を置換・終了する場合は`TaskSlot`を使う。storeやslotを開始箇所だけの一時変数にせず、機能の所有者とともに保持する。

```swift
private let tasks = ViewTaskStore()
private static let refresh: ActionID = "library.refresh"

func reload() {
    tasks.start(id: Self.refresh, lifetime: .screenBound, policy: .cancelExisting) { [weak self] cancellation in
        try cancellation.check()
        await self?.refresh()
    }
}
```

`ActionLifetime`は分類用の値であり、自動で画面・sceneのイベントを監視しない。画面終了時の`cancel(lifetime:)`を明示的に接続する。キャンセルは協調的であり、DBの確定済み変更を取り消さない。画面を閉じる際に保存を捨てたり、古い結果で新しい画面を更新したりしないよう、中断点と結果反映の条件を決める。

| 所有者・処理 | lifetime / 重複方針 | 終了と整合性 |
| --- | --- | --- |
| `LibraryModel`の再取得 | screenBound / cancelExisting | 一覧終了時にキャンセル。検索結果は世代とキャンセル状態を確認して反映 |
| `LibraryModel`の編集開始 | screenBound / ignoreNew | 二重に下書きを作らない。開始前のキャンセルで開かず、受理済みDB処理は完了させる |
| `LibraryModel`のコピー | sceneBound / cancelExisting | 最新のコピーを優先。DB読込後にもキャンセルを確認してからpasteboardへ反映 |
| `LibraryModel`のピン・削除・復元・完全削除 | sceneBound / ignoreNew | 操作種別と項目UUIDでIDを分ける。同じ項目の同じ処理だけ重複を抑制し、受理済みの書込は完了させる |
| `LibraryModel`の通知消去 | screenBound / cancelExisting | 新しい通知で期限を更新。一覧終了時にキャンセルし、通知と取り消し操作を消去 |
| `EditorModel`の下書き書込 | screenBound / allowConcurrent | 入力snapshotをすべて受理。SQLiteのsequence比較で最新を保持し、保存・破棄後の下書きを再生成しない |
| `SnippetEditor`の保存・閉じる・破棄 | screenBound / ignoreNew | 共通IDで終了処理の二重実行を防止。画面終了時にキャンセルし、成功した永続化に対応する終了通知を返す |
| `ShareViewController`のprovider読込 | screenBound / ignoreNew | viewDidDisappearでキャンセル。provider読込の前後で確認し、キャンセルを業務エラー表示にしない |

一覧のsceneBound処理は、シート表示や一時的な非active化で中断しない有限の操作とする。所有者の解放時はstoreが残る処理をキャンセルする。下書き書込も入力snapshotを保持し、受理済みのSQLite処理を完了させる。業務エラーはmodelの表示状態へ変換する。storeへ流出した非キャンセルエラーはDebug assertionの対象なので、空のcatchで消さない。

`async/await`、`async let`、task group、SwiftUIの`.task(id:)`は構造化された処理・OSによる寿命管理として使う。Taskingの[設計方針](https://github.com/9uiLe/swift-tasking/blob/0.3.0/README.md)に従い、これらを非構造化タスクに置き換えない。actor、continuation、`CancellationError`も利用できる。`Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority`は既存タスクの協調用に限って許可する。

## アニメーションの境界

変化させる最小の表示部分を名前付き`AnimationScope`で囲み、valueによる変更検知、またはproxyの`scope.animate`を使う。複数のtriggerを指定する場合は`AnimationTrigger.animation`を明記する。入力領域など親のアニメーションを受けない部分は`.animationBarrier()`を使う。

一覧の通知は`Library.Notice` scopeで表示・消去を0.16秒のopacity遷移として扱う。Reduce Motion有効時はdurationを0にする。編集の入力領域にはbarrierを置く。標準のシート・メニュー・キーボード等、OS部品自身の遷移はその部品の動作に従う。

画面の根には`.detectAnimationLeaks()`を置き、Debug実行時に診断を確認する。検知できるのはmodifierの位置に届いたtransactionであり、子孫のすべての変化やUIKitを自動検査する機能ではない。scopeも同じ状態更新に付随する変更を自動で分離しないため、小さく配置し、スクリーンショットと録画を確認する。

## Lintと禁止する直接使用

```sh
# 単独実行
nix develop --command python3 scripts/check_swift_policy.py

# Lint自身の回帰テストを含む共通検査
nix flake check --no-update-lock-file --print-build-logs
```

`swift-library-policy`はNixのPythonで実行し、ローカルとUbuntu CIで同じ禁止規則を適用する。違反にはファイル・行・列を表示し、終了コード1で検査を失敗させる。抑制コメントやファイル単位の例外は用意しない。

| 禁止対象 | 代表例・代替 |
| --- | --- |
| 生のTask生成・保持・別名・関数参照 | `Task {}`、`Task.detached`、`Task<…>.init`、`Task`型のhandle。`ViewTaskStore` / `TaskSlot`を使用 |
| 別の直接scheduler | `DispatchQueue`、`DispatchWorkItem`、`DispatchSource`、`OperationQueue`、`BlockOperation`、`Thread`、`Timer`。Taskingに所有させ、待機には協調的なsleepを使用 |
| SwiftUIの直接指定 | `withAnimation`、`withTransaction`、`Transaction`、`.animation`、`.transaction`、`.phaseAnimator`、`.keyframeAnimator`。scope / proxy / barrierを使用 |
| UIKit / Core Animationの直接指定 | `UIView.animate`・`transition`等、`UIViewPropertyAnimator`、`CAAnimation`系、`CATransaction`等。製品のアニメーションをscopeで設計 |

正確な名前の集合は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)を正とする。これらの名前は別用途にも使わない。例えばSQLiteのprivate helperは`writeTransaction`とし、SwiftUIの`.transaction`と区別する。

検査はリポジトリ内のSwiftファイルを再帰的に読む。新しいsourceディレクトリも対象とし、`artifacts`、`.build`、`DerivedData`等の生成物は除外する。依存コードは`artifacts`以下に取得し、ライブラリ内部の標準API実装を製品コードの違反にしない。Swift sourceとsource directoryのsymlink、読めない入力、対象0件はエラーにする。

コメント・通常/raw/複数行文字列・regexの本文を読み飛ばし、実行される文字列補間は検査する。改行・コメントを挟んだ呼出し、修飾名、backtick、型の別名宣言も規則の対象になる。型解決やmacro展開を行うSwiftコンパイラではなく、予約した名前を検査する字句Lintである。独自macro、型aliasを通じた動的な呼出し、未知のAPIまで網羅する保証はない。Lint自体の変更と新しい非同期・アニメーション入口はレビューし、規則と回帰テストを一緒に更新する。

## 選定と保守

生のTask handleとanimation transactionを各画面で管理する案は、寿命・重複・適用範囲の実装が分散する。TaskingとScopedAnimationを共通の入口にすると、その方針を宣言でき、同じ契約で検査できる。一方で外部APIへの追従、Swift tools要件、操作ごとの管理コストを負う。独自wrapperを重ねず、データ層のasync APIを独立させて移行範囲をUIの所有者とscopeに絞る。

依存更新はexact version・共有lock・ライセンスを一緒に確認し、重複操作、キャンセル、最新入力の保存、共有元への復帰、通知と入力へのアニメーション伝播をiOS 26.5で再検証する。保守停止、対応OS・ツールチェーンの不適合、測定した応答・描画の悪化、必要な表現をscopeで扱えない場合は採用を見直す。既存の測定結果を別版の性能保証に使わない。
