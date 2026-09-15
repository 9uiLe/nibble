# 非同期処理とアニメーションの実装規約

状態：採用。決定日：2026-09-15。

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

## 非同期APIの契約

非同期の操作は`async`メソッドとして公開し、その操作の完了まで呼出元が待機できるようにする。モデルの同期メソッド、initializer、入力プロパティのsetter・observerからタスクを開始しない。`async`を付けても、内部で非構造化タスクを開始して戻る形は操作APIとして認めない。

呼出元は既存タスクから`await model.copy(id)`を実行するか、同期UIイベントからTaskingで開始するかを選ぶ。モデルは入力・処理・結果を持ち、UI側の所有者がActionID・寿命・重複方針を決める。モデルはTaskingのstoreや開始用closureを受け取らない。

| 処理 | 戻った時点の契約 |
| --- | --- |
| 一覧読込 | 当該要求の検索・下書き取得が終了し、有効な世代なら表示状態を更新済み |
| 編集開始 | 再開する下書きの選択、またはDB上の下書き作成と編集状態への反映が終了 |
| コピー | 保存済み本文をpasteboardへ書き、通知状態を更新済み。通知の表示時間は待たない |
| ピン・削除・復元・完全削除 | DB更新と一覧の再取得が終了。エラーはmodelの表示状態へ反映 |
| 下書き保存 `persist(snapshot)` | 渡された不変snapshotのDB更新が終了。終了済みeditorや別IDのsnapshotは受け付けない |
| 保存・閉じる・破棄 | 最新入力を使った永続化が終了し、成功をBoolで返す。呼出側が画面を閉じる |
| 通知期限 `expireNotice(id:)` | 待機後、同じ通知IDであれば消去済み。古いID・キャンセルでは消さない |

入力setterは値とsequenceだけを同期的に更新する。`SnippetEditor`は描画時の不変snapshotを`.task(id: snapshot.sequence)`で`await model.persist(snapshot)`へ渡す。SwiftUIが複数の入力更新をまとめる場合があり、全キーストロークの独立した保存は契約に含めない。保存・閉じるはこの処理の開始を待たず、最新入力を直接永続化する。受理済みSQLite書込は完了させ、sequence比較と削除済み下書きを再生成しない更新で整合性を守る。

## 非同期処理の入口

| 処理の形 | 使用する入口 | 設計時に決めること |
| --- | --- | --- |
| 同期UIイベントから開始する操作 | `startTask`またはイベント内で`ViewTaskStore.start` | ActionID、lifetime、重複方針、終了イベント、キャンセル位置 |
| 単一処理を置換・終了する専用所有者 | `@MainActor`の`*TaskOwner`で`TaskSlot`を保持し、`startTask`から`replace` | 開始要求の受理と処理完了を区別し、終了を待つAPIを用意する。MVPでは未使用 |
| 既存のasync処理内で完結する操作 | `async/await`、`async let`、task group | 子処理の完了、エラー・キャンセル、actor隔離 |
| SwiftUIが寿命を管理する処理 | `.task` / `.task(id:)`で操作を直接await | viewの終了・ID変更でキャンセルしてよい処理か |
| 既存タスクの待機・協調的中断 | `Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority` | 結果反映前のキャンセル確認 |

Taskingの[設計方針](https://github.com/9uiLe/swift-tasking/blob/0.3.0/README.md)に従い、構造化できる処理は親子関係を利用する。actor、continuation、`CancellationError`も使用できる。`startTask`は処理の開始を表す明示的な境界であり、完了を表す操作APIではない。そこから呼ぶ処理は直接awaitし、タスク内で別の非構造化タスクを開始しない。

```swift
struct ExampleView: View {
    @State private var tasks = ViewTaskStore()
    let model: ExampleModel

    var body: some View {
        Button("更新") { startTask() }
    }

    private func startTask() {
        tasks.start(id: "example.refresh", lifetime: .screenBound, policy: .cancelExisting) { cancellation in
            try cancellation.check()
            await model.refresh()
        }
    }
}
```

## 所有・寿命・重複実行

`ViewTaskStore`はview・UIViewController、または専用の`@MainActor *TaskOwner`に保持する。`LibraryView`はmodelと`LibraryTaskOwner`を`@State`で保持し、後者が開始・キャンセル・重複判定を担当する。所有者の終了待ちはタスク管理のテストで使い、モデルの操作テストは操作自体をawaitする。

`ActionID`は重複判定の単位とし、項目ごとに独立した操作はUUIDを含める。`cancelExisting`は同じIDをキャンセルして新しい要求を受理し、`ignoreNew`は同じIDの実行中の要求を抑止する。`allowConcurrent`を使う場合は同時実行の整合性を定義する。

`ActionLifetime`は分類であり、画面・sceneのイベントを自動監視しない。所有者が`cancel(lifetime:)`をイベントへ接続する。操作ごとのID・重複方針は[製品設計](decisions/0002-mvp-app.md#操作の寿命と整合性)を正とする。

- 一覧の読込・コピー・項目更新はsceneBoundの有限処理で、シート表示や一時的な非active化をまたぐ。viewの表示・非表示をキャンセル条件にしない。
- background化では所有者の`endScreen()`で編集開始をキャンセルし、modelの`clearNotice()`で通知ID・本文・取り消し操作を消す。通知の消去待ちはSwiftUI `.task(id:)`が管理する。
- 編集の保存・閉じる・破棄は同じ終了操作IDで扱い、`SnippetEditor.onDisappear`でキャンセルする。共有provider読込は`ShareViewController.viewDidDisappear`でキャンセルする。
- 下書きの自動保存はviewが直接awaitする。入力変更・画面終了によるSwiftUIのキャンセルは、DBへ受理済みの書込を巻き戻さない。

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

`swift-library-policy`はNixのPythonとtree-sitter-language-pack（lockされたnixpkgsの1.4.1）で動き、ローカルとUbuntu CIで同じ規則を使う。違反にはファイル・行・列を表示し、終了コード1で失敗させる。抑制コメントやファイル単位の例外は設けない。

| 禁止対象 | 代表例と代替 |
| --- | --- |
| 生のTask生成・保持・別名・関数参照 | `Task {}`、`Task.detached`、`Task<…>.init`、Task型handle。`ViewTaskStore` / `TaskSlot`を使う |
| 別の直接scheduler | `DispatchQueue`、`DispatchWorkItem`、`DispatchSource`、`OperationQueue`、`BlockOperation`、`Thread`、`Timer`。Taskingに所有させ、待機には協調的なsleepを使う |
| SwiftUIの直接指定 | `withAnimation`、`withTransaction`、`Transaction`、`.animation`、`.transaction`、`.phaseAnimator`、`.keyframeAnimator`。scope / proxy / barrierを使う |
| UIKit / Core Animationの直接指定 | `UIView.animate`・`transition`等、`UIViewPropertyAnimator`、CAAnimation系、`CATransaction`等。製品のアニメーションをscopeで設計する |

正確な名前の集合は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)を正とする。予約した名前は別用途にも使わない。SQLiteのprivate helperには`writeTransaction`という名前を使う。

検査対象はリポジトリのSwiftファイル全体で、新しいsourceディレクトリも再帰的に探索する。`artifacts`、`.build`、`DerivedData`等の生成物は除外する。依存コードは`artifacts`以下に取得し、ライブラリ内部の標準API実装を製品コードの違反にしない。Swift sourceとsource directoryのsymlink、読めない入力、対象0件はエラーとする。

字句解析はコメント・通常/raw/複数行文字列・regexの本文を読み飛ばし、実行される補間は検査する。改行・コメントを挟む呼出し、修飾名、backtick、型aliasも対象とする。

[scripts/swift_task_boundary.py](../scripts/swift_task_boundary.py)はSwiftの構文木から、次の制限を検査する。

- `ViewTaskStore()`は`tasks`、`TaskSlot()`は`taskSlot`というprivateプロパティで直接構築する。所有者は`View`・`UIViewController`・`@MainActor *TaskOwner`に限る。`*Model`と`@Observable`型では保持しない。型alias・生成関数・引数注入は禁止する。
- `tasks`・`taskSlot`は予約名とし、直接のTaskingメソッド呼出し以外へ渡さない。storeや開始メソッドを別名化・返却・captureしない。
- タスク開始は`startTask`、登録した同期UIイベント、UIKit lifecycle、`@Test`の本体で行う。SwiftUIの`.task`、Taskingのoperation、任意のclosure、通常の同期/asyncメソッド、initializer、setter・observerでは開始しない。
- `startTask`自体の呼出しと関数参照も検査する。通常メソッドから包み直すことや、開始処理を別名化して渡すことは禁止する。`ViewTaskStore`の開始メソッドは同期とし、TaskSlotのactor呼出しが必要な専用所有者だけ`async startTask`を許可する。
- 登録済みUI境界はButtonのaction、`onAppear`・`onDisappear`・`onChange`・`onOpenURL`、sheet/fullScreenCoverの`onDismiss`、UIViewControllerのoverride `viewDidLoad`・`viewDidAppear`・`viewWillAppear`。表示内容を構築するclosureは開始境界にしない。
- `@Test`では所有権・キャンセルの試験用にローカルstoreと直接の開始を認める。テスト内でもoperation closureからの再開始やaliasは禁止する。

未対応・壊れた構文は成功扱いにしない。使用するSwift grammarが未対応の`isolated deinit`は`isolated`だけを同じ長さの空白に置換して解析し、本体の検査と元ソースの診断位置を維持する。この互換処理も回帰テストで確認する。

この検査は保守可能な構文を制限するもので、Swiftの型解決・macro展開・全プログラムの副作用解析は行わない。外部APIや独自macroが内部で開始する処理、独自のcallback登録、受理済み操作の完了契約までは保証しない。新しい入口や構文の追加は、規則・回帰テスト・完了を直接待つ製品テストとともにレビューする。ファイル別除外や抑制コメントは使わない。

## 採用理由と保守

画面ごとに生のTask handleとanimation transactionを管理する構成では、寿命・重複・適用範囲の実装が分散する。TaskingとScopedAnimationはこれらを共通APIで宣言できる。一方で外部APIへの追従、Swift tools要件、操作ごとの管理コストを負う。開始境界を明示し、モデルとデータ層のasync APIを独立させ、置換が必要な範囲をUI所有者とscopeに絞る。

依存更新ではexact version・共有lock・ライセンスを同時に確認し、重複操作、キャンセル、入力直後の保存、共有元への復帰、通知と入力へのアニメーション伝播をiOS 26.5で検証する。保守停止、対応OS・ツールチェーンの不適合、測定した応答・描画の悪化、scopeで必要な表現を扱えない場合を採用の見直し条件とする。測定結果は記録したライブラリ版と条件に限って解釈する。
