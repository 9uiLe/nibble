# 非同期処理とアニメーションの実装規約

状態：採用。決定日：2026-09-15。本体・共有拡張・テスト・研究用アプリ・検証用Swiftコードに適用する。

非同期操作は完了まで待てるAPIで提供し、UIがタスクの開始・所有・寿命を決める。非構造化タスクにはswift-tasking、アプリが指定するアニメーションにはswift-scoped-animationを使う。この文書は、コードで表す契約と機械検査の条件を定義する。操作別の仕様は[製品設計](decisions/0002-mvp-app.md)、実施済みの確認は[製品の検証結果](mvp-validation.md)を参照する。

## 操作APIと開始API

操作APIは`async`にし、受理した処理と結果反映を待ってから戻る。処理の完了、失敗、キャンセル、要求を受け付けない条件をAPIごとに定義する。同期メソッド・initializer・setter・observerから非同期処理を開始しない。`async`メソッドでも非構造化タスクを開始して即座に戻る実装は禁止する。

タスク開始はUI側の明示的な`startTask`または登録済みの同期UIイベントで行う。`startTask`は開始の受理を表し、業務処理の完了を表さない。開始したoperationはモデルの操作を直接awaitする。モデルはTaskingのstoreや開始用closureを受け取らず、入力・処理・結果だけを持つ。

| 呼出元の状況 | 選ぶ形 | 待機・終了の責務 |
| --- | --- | --- |
| 既存のasync処理で操作する | `await model.refresh()`などの操作API | 呼出元が完了・エラー・キャンセルを扱う |
| 子処理を並行して完了させる | `async let`・task group | 親子関係とscope内の完了を利用する |
| viewや状態IDに結び付いた処理 | SwiftUI `.task` / `.task(id:)`内で操作を直接await | SwiftUIによるview終了・ID変更時のキャンセルを扱う |
| 同期UIイベントから独立した操作を開始する | `startTask`から`ViewTaskStore.start` | UI所有者がActionID・寿命・重複方針・終了イベントを決める |
| 単一処理を置換・終了する専用所有者 | `@MainActor *TaskOwner`の`TaskSlot`と`startTask` | 開始の受理と処理完了を区別し、終了待ちを提供する。MVPでは未使用 |

actor、checked continuation、`CancellationError`は使用できる。既存タスクの協調には`Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority`を使える。TaskingのoperationやSwiftUI `.task`から別の非構造化タスクを開始しない。

### 実装例

モデルの`refresh()`は処理を完了までawaitする。同期イベントを持つviewは次の形で開始と終了を接続する。モデルの操作テストは`await model.refresh()`の直後に結果を検査できる。

```swift
@MainActor
struct ExampleView: View {
    @State private var tasks = ViewTaskStore()
    let model: ExampleModel

    var body: some View {
        Button("更新") { startTask() }
            .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask() {
        tasks.start(id: "example.refresh", lifetime: .screenBound, policy: .cancelExisting) { cancellation in
            try cancellation.check()
            await model.refresh()
        }
    }
}
```

この例はviewの終了で止める操作を表す。一覧のsceneBound操作など、シート表示やviewの一時的な非表示をまたぐ処理には、その操作に合う終了条件を設ける。

## 所有者と重複方針

`ViewTaskStore`は`View`・`UIViewController`または専用の`@MainActor *TaskOwner`に保持する。`*Model`や`@Observable`型はタスク所有者にしない。製品の一覧では`LibraryView`がモデルと`LibraryTaskOwner`を`@State`で保持し、編集では`SnippetEditor`がモデルとstoreを保持する。

| 項目 | 規則 |
| --- | --- |
| ActionID | 重複判定の単位。項目ごとに独立した操作は操作種別とUUIDを含める |
| cancelExisting | 同じIDの実行をキャンセルして新しい要求を受理する。古い結果の反映も防ぐ |
| ignoreNew | 同じIDが実行中なら新しい要求を受け付けない |
| allowConcurrent | 同時実行の整合性を定義して使用する |
| ActionLifetime | 所有者がキャンセル対象を分類する値。scene・viewのイベントは自動監視しない |
| 終了待ち | 所有者の`waitForIdle`等は所有・寿命のテストに使う。モデルの操作完了はAPI自体をawaitする |

製品のID・lifetime・policyは[操作の寿命と整合性](decisions/0002-mvp-app.md#操作の寿命と整合性)で定義する。一覧読込・コピー・項目更新はsceneBoundの有限処理とし、一覧viewの`onDisappear`ではキャンセルしない。background化では`LibraryTaskOwner.endScreen()`で編集開始を止め、モデルの同期API`clearNotice()`で通知状態を消す。

編集終了操作は`SnippetEditor.onDisappear`、共有provider読込は`ShareViewController.viewDidDisappear`でscreenBoundをキャンセルする。所有者とUIの寿命を一致させ、保持したモデル・画面・完了通知がいつ解放されるかを確認する。

## 完了・キャンセル・永続化

キャンセルは協調的な停止要求であり、確定したDB変更を巻き戻さない。結果の表示、pasteboardの変更、受理したDB書込にはそれぞれの完了条件を設ける。

| 操作 | 契約 |
| --- | --- |
| 検索 | 読込後にキャンセルと要求世代を確認し、有効な結果だけ反映 |
| コピー | DB読込の前後でキャンセルを確認。保存済み本文をコピーして通知状態を更新したら完了 |
| 編集開始・項目更新 | 開始時のキャンセルや重複条件を確認。受理済みDB処理は完了させる |
| 下書きのsnapshot保存 | 終了済みeditorと別の下書きIDを拒否。受理した書込はviewタスクのキャンセル後も完了 |
| 保存・閉じる・破棄 | 開始時にキャンセル・busy・終了済みを確認。永続化成功後はキャンセルが届いていてもUIへ成功を返す |
| 共有provider読込 | 読込の前後でキャンセルを確認。キャンセルは業務エラーとして表示しない |
| 通知期限 | 待機後にキャンセルと通知IDを確認し、対象の通知だけ消す |

入力setterは値とsequenceだけを更新する。viewは不変snapshotを`.task(id: snapshot.sequence)`から`persist(snapshot)`へ渡し、書込を直接awaitする。SwiftUIによる入力更新の集約を許容し、全キーストロークの独立した保存は約束しない。保存・閉じるは自動保存の開始に依存せず、最新入力を直接永続化する。

保存層はsequence比較で古いsnapshotを拒否し、保存・破棄後の下書きを遅れた書込で再生成しない。コピーの完了は通知の表示時間を含めず、期限は`.task(id: noticeID)`から`expireNotice(id:)`をawaitする。

業務エラーは表示状態へ変換し、入力を保持して再試行・競合回復を可能にする。storeへ流出した非キャンセルエラーはDebug assertionの対象になる。空のcatchで失敗を消さず、キャンセルだけを正常な終了として扱うcatchと区別する。

## アニメーションの境界

表示変化の範囲を名前付き`AnimationScope`で囲み、valueによる変更検知またはproxyの`scope.animate`を使う。複数triggerのfactoryは`AnimationTrigger.animation`と型名を明記する。入力など親のアニメーションを受けない領域には`animationBarrier()`を置く。

製品の通知scopeは`Library.Notice`とし、通知の有無をvalueで検知する。表示・消去は0.16秒のopacity遷移、Reduce Motion有効時はduration 0秒とする。通知本文の更新と表示の有無を区別し、scopeを必要な表示部分に限定する。

`LibraryView`と`SnippetEditor`の外側の`animationBarrier(warnsOnLeaks: false)`は、OSのシートtransactionが内容へ伝わるのを防ぐ。内側の`detectAnimationLeaks()`と編集入力領域の警告付きbarrierは、アプリ内部の伝播をDebug実行時に診断する。標準シート・メニュー・キーボード自体の遷移はOS部品が管理する。

診断の対象はmodifierの位置へ届くtransactionである。子孫の全表示変化やUIKitを自動検査する機能ではなく、scopeも同じ状態更新に伴う変化を自動分離しない。Reduce Motion、入力・スクロール・遷移を画像と録画で確認する。

## Lintと禁止する直接使用

`swift-library-policy`は字句解析とSwift構文木を使い、直接APIと開始境界を検査する。ローカルとUbuntu CIは同じNixのPython環境とtree-sitter-language-pack 1.4.1を使用する。違反はファイル・行・列を表示して終了コード1で失敗する。

```sh
# ソースの規約検査
nix develop --command python3 scripts/check_swift_policy.py

# Lintの回帰テストを含む共通検査
nix flake check --no-update-lock-file --print-build-logs
```

### 直接APIの制限

| 禁止するもの | 代表例 | 使用する入口 |
| --- | --- | --- |
| 生のTaskの生成・保持・別名・関数参照 | `Task {}`、`Task.detached`、`Task<…>.init`、Task型handle | Tasking、または構造化された処理 |
| 別scheduler | `DispatchQueue`、`DispatchWorkItem`、`DispatchSource`、`OperationQueue`、`BlockOperation`、`Thread`、`Timer` | Taskingによる所有、協調的なsleep |
| SwiftUIの直接アニメーション | `withAnimation`、`withTransaction`、`Transaction`、`.animation`、`.transaction`、`.phaseAnimator`、`.keyframeAnimator` | scope・proxy・barrier |
| UIKit / Core Animationの直接アニメーション | `UIView.animate`・`transition`等、`UIViewPropertyAnimator`、CAAnimation系、`CATransaction`等 | ScopedAnimationで製品の表示変化を設計 |

正確な名前の集合は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)を正とする。予約名は別用途にも使わない。SQLiteのprivate helperには`writeTransaction`を使う。

字句解析はコメント・通常/raw/複数行文字列・regexの本文を読み飛ばし、実行される補間を検査する。改行・コメントを挟む呼出し、修飾名、backtick、型aliasも対象とする。

### タスク開始境界の制限

[scripts/swift_task_boundary.py](../scripts/swift_task_boundary.py)は次の構文上の制約を適用する。

| 検査対象 | 許可する形 |
| --- | --- |
| storeの構築 | 所有者のprivateプロパティへ`ViewTaskStore()`を`tasks`、`TaskSlot()`を`taskSlot`として直接代入 |
| 所有する型 | `View`・`UIViewController`・`@MainActor *TaskOwner`。`*Model`・`@Observable`は不可 |
| storeの参照 | 予約したプロパティへの対応メソッドの直接呼出し。型alias・生成関数・引数注入・返却・再代入・capture・メソッド参照は不可 |
| 開始メソッド | 所有者の`startTask`。ViewTaskStoreの開始は同期。TaskSlotのactor呼出しが必要な専用所有者には`async startTask`を許可するが、ViewTaskStore.startをasyncで包む形は不可 |
| 開始メソッドの使用 | 許可された開始境界から直接呼び出す。通常メソッドからのラップ、関数参照、別名化は不可 |
| 所有者のテスト | `@Test`の本体でローカルstoreの直接構築と開始を許可。operation内の再開始やaliasは不可 |

登録済みの開始境界は`startTask`、Buttonのaction、`onAppear`・`onDisappear`・`onChange`・`onOpenURL`、sheet/fullScreenCoverの`onDismiss`、UIViewControllerのoverride `viewDidLoad`・`viewDidAppear`・`viewWillAppear`、`@Test`の本体とする。Buttonのlabelやsheetのcontentなど、表示を構築するclosureは含めない。

通常の同期/asyncメソッド、initializer、getter・setter・observer、任意のclosure、SwiftUI `.task`、Taskingのoperationからの開始を拒否する。予約名以外の任意の`.replace`を一律に禁止する規則ではない。

### 検査対象と保証範囲

リポジトリ内のSwiftソースを再帰的に探索し、新しいsourceディレクトリも検査する。`artifacts`・`.build`・`DerivedData`等の生成物は除外する。依存コードは`artifacts`以下に取得し、ライブラリ内部実装は所有するソースの検査対象に含めない。Swift sourceとsource directoryのsymlink、読めない入力、対象0件はエラーとする。

抑制コメント・ファイル単位の例外は設けない。未対応・壊れた構文も失敗させる。grammarが未対応の`isolated deinit`は`isolated`だけを同じbyte長の空白へ置換して解析し、本体の検査と元ソースの診断位置を保つ。この互換処理は回帰テストで確認する。

Lintは構文の制限であり、Swiftの型解決・macro展開・全プログラムの副作用解析は行わない。外部APIや独自macroの内部動作、独自callback登録、受理済み操作の完了までは保証しない。完了契約はモデルのAPIを直接awaitする製品テストで検査し、UIの開始・重複・寿命は所有者のテストで検査する。新しい開始境界や構文を認める際は、規則・回帰テスト・製品テストを合わせてレビューする。

## 依存とビルド

| パッケージ | 固定版 | product | 対応条件 |
| --- | --- | --- | --- |
| [swift-tasking](https://github.com/9uiLe/swift-tasking/tree/0.3.0) | 0.3.0 | `Tasking`の`ViewTaskStore`、`TaskingCore`の`TaskSlot` | Swift tools 6.0、iOS 13以上 |
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.1) | 0.2.1 | `ScopedAnimation` | Swift tools 6.2、iOS 17以上 |

製品のdeployment targetは26.0、検証ツールチェーンはXcode 26.5 / Swift 6.3.2とする。本体と共有拡張は同じ固定版をリンクする。構造化された処理だけを持つ研究・基盤targetには不要なproductをリンクしない。

Xcode projectのexact versionと共有の`app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`でrevisionを固定する。初回はネットワーク接続のあるMacで解決する。通常のビルドでもXcodeが解決する。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

両パッケージはMITライセンスで追加の外部パッケージを持たない。本体と共有拡張のbundleに`ThirdPartyNotices.txt`を含める。補助ツールはNix、アプリのSwift PackageはXcode / SwiftPMで管理する。

## 採用理由と更新条件

Taskingは処理の所有・寿命・重複方針、ScopedAnimationは表示変化の適用範囲を共通APIで表す。外部APIへの追従、Swift tools要件、操作ごとの管理コストを伴うため、モデルと保存層の操作を独立したasync APIにし、依存をUI所有者とscopeへ集中させる。

依存更新ではexact version・共有lock・ライセンスを照合し、重複操作、キャンセル、入力直後の保存・閉じる、共有元への復帰、通知と入力への伝播をiOS 26.5で確認する。保守停止、対応OS・ツールチェーンの不適合、測定した応答・描画の悪化、必要な表現への不適合を見直し条件とする。

[2026-09-15の非同期API境界の検証](async-policy-validation.md)と[2026-09-14のTasking・ScopedAnimationの検証](library-policy-validation.md)は、それぞれ記載したソースと条件の観測記録である。採用の根拠と適用限界を確認し、依存の更新時には対象ソースに対応する結果を記録する。
