# 非同期処理・アニメーション・View比較の実装規約

本体・共有拡張・テスト・研究用アプリ・検証用Swiftに適用する。モデルは処理と状態、UIは操作の開始とタスクの所有、表示用Viewは受け取った値の描画を担う。製品固有の操作は[製品設計](decisions/0002-mvp-app.md)、実行手順は[MVP手順](mvp.md)、確認済みの条件は[検証結果](mvp-validation.md)を参照する。

## 責務と使用するAPI

| 責務 | 使用するAPI | 守る契約 |
| --- | --- | --- |
| 操作を完了させる | モデルの`async` API、Swift Concurrency | 受理した処理と結果反映を待ってから戻る |
| 非構造化タスクを所有する | swift-taskingの`ViewTaskStore` / `TaskSlot` | UI所有者が開始・ID・寿命・重複方針・終了を定義する |
| 表示値の比較で更新を制御する | swift-app-macrosの`@Equatable` / `EquatableBodyView` | 比較対象は表示に必要な値だけとし、全入力を比較する |
| アニメーションを適用する | swift-scoped-animationの`AnimationScope` / `animationBarrier` | 表示変化を必要な範囲に限定し、入力への伝播を防ぐ |

モデルの操作APIを呼ぶ側が、既存タスクからawaitするか、同期UIイベントからタスクとして開始するかを選ぶ。比較による更新制御を「比較境界」、アニメーションの適用範囲を「scope」と呼ぶ。両者は別の責務であり、状態・操作を比較から除外して表示更新を調整しない。

## 操作APIと開始API

操作APIは`async`にし、完了・失敗・キャンセル・受理しない条件を定義する。同期メソッド・initializer・setter・observerから非同期処理を開始しない。`async`メソッドでも、非構造化タスクを開始して処理の完了前に戻る実装は禁止する。

開始APIの`startTask`は、UI所有者が開始を受理するための名前である。開始の受理は業務処理の完了を意味しない。開始したoperationはモデルの操作を直接awaitし、別の非構造化タスクを開始しない。モデルはTaskingのstoreや開始用closureを保持・受領しない。

| 呼出元の状況 | 選ぶ形 | 待機・終了の責務 |
| --- | --- | --- |
| 既存のasync処理で操作する | `await model.refresh()`などの操作API | 呼出元が完了・エラー・キャンセルを扱う |
| 子処理を並行して完了させる | `async let`・task group | 親子関係とscope内の完了を利用する |
| viewや状態IDに結び付いた処理 | SwiftUI `.task` / `.task(id:)`で操作を直接await | SwiftUIによるview終了・ID変更時のキャンセルを扱う |
| 同期UIイベントから操作を開始する | `startTask`と`ViewTaskStore.start` | UI所有者がID・寿命・重複方針・終了イベントを決める |
| 単一処理を置換・終了する専用所有者 | `@MainActor *TaskOwner`の`TaskSlot`と`startTask` | 開始の受理と処理完了を区別し、終了待ちを提供する。MVPでは未使用 |

actor、checked continuation、`CancellationError`は使用できる。既存タスクの協調には`Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority`を使える。SwiftUI `.task`やTaskingのoperation内では構造化された処理を使う。

### 実装例

この例では`ExampleModel.refresh()`が読込と結果反映を完了まで待つ。`ExampleView`はボタン操作から開始し、画面の終了をキャンセルへ接続する。モデルの操作テストは`await model.refresh()`の直後に結果を検査する。

```swift
import SwiftUI
import Tasking

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

この終了条件は画面の消失で止める操作に使う。一覧のsceneBound操作など、シート表示や一時的な非表示をまたぐ処理には、その操作に合う終了条件を設ける。

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

編集終了操作は`SnippetEditor.onDisappear`、共有provider読込は`ShareViewController.viewDidDisappear`でscreenBoundをキャンセルする。保持したモデル・画面・完了通知の解放条件を所有者の寿命と合わせる。

## 完了・キャンセル・永続化

キャンセルは協調的な停止要求であり、確定したDB変更を巻き戻さない。結果の表示、pasteboardの変更、DB書込にはそれぞれの完了条件を設ける。

| 操作 | 契約 |
| --- | --- |
| 検索 | 読込後にキャンセルと要求世代を確認し、有効な結果だけ反映 |
| コピー | DB読込の前後でキャンセルを確認。保存済み本文をコピーして通知状態を更新したら完了 |
| 編集開始・項目更新 | 開始時のキャンセルや重複条件を確認。受理済みDB処理は完了させる |
| 下書きの保存 | 終了済みeditorと別の下書きIDを拒否。受理した書込はviewタスクのキャンセル後も完了 |
| 保存・閉じる・破棄 | 開始時にキャンセル・busy・終了済みを確認。永続化成功後はキャンセルが届いていてもUIへ成功を返す |
| 共有provider読込 | 読込の前後でキャンセルを確認。キャンセルは業務エラーとして表示しない |
| 通知期限 | 待機後にキャンセルと通知IDを確認し、対象の通知だけ消す |

下書きの入力順序を`sequence`、ある時点の下書きを固定した値を`snapshot`と呼ぶ。入力setterは値とsequenceだけを更新する。viewは`.task(id: snapshot.sequence)`から`persist(snapshot)`を直接awaitする。SwiftUIによる入力更新の集約を許容し、全キーストロークの独立した保存は約束しない。

保存・閉じるは自動保存の開始に依存せず、最新入力を直接永続化する。保存層はsequence比較で古いsnapshotを拒否し、保存・破棄後の下書きを遅れた書込で再生成しない。コピーの完了に通知の表示時間を含めず、期限は`.task(id: noticeID)`から`expireNotice(id:)`をawaitする。

業務エラーは表示状態へ変換し、入力を保持して再試行・競合回復を可能にする。storeへ流出した非キャンセルエラーはDebug assertionの対象になる。空のcatchで失敗を消さず、キャンセルだけを正常な終了として扱うcatchと区別する。

## Viewの比較境界

比較Viewは`@Equatable`を付けた`EquatableBodyView`とし、同じstructの`equatableBody`に内容を書く。ライブラリの既定の`body`が等価比較を適用するため、呼出側は通常のViewとして配置する。

```swift
import AppMacros
import SwiftUI

@Equatable
struct CaptionContent: EquatableBodyView {
    let text: String

    var equatableBody: some View {
        Text(text)
    }
}
```

製品の`SnippetRowContent`はタイトル・本文プレビュー・ピン状態だけを`let`で受け取り、すべてを比較する。Button、アクセシビリティの操作ラベル、コピー・編集・削除等のクロージャは`LibraryView`に保持する。表示値が等しい場合も、操作は現在のモデル・項目を参照する。

| 設計するもの | 規則 |
| --- | --- |
| 比較Viewの入力 | wrapperや所有修飾子を持たない`let`の値型。表示を決める全入力を比較する |
| 状態・注入・操作 | `@State`・`@Binding`・`@Bindable`・`@Environment`等と操作closureは通常のViewに保持 |
| 表示の依存 | 独自の参照モデルやglobal状態を比較境界から読まない。標準部品の外観・文字サイズはSwiftUIのenvironmentで更新する |
| 比較を使わない画面 | 状態や入力を持つ画面、参照依存がある表示、比較が高価な表示は通常のViewで構成 |
| データの等価比較 | 値型・enumの標準Equatable合成とgenericなEquatable制約を許可。手書き`==`は設けない |

クロージャやDynamicPropertyをライブラリが自動で比較から除外できる場合も、nibbleの比較Viewへは渡さない。`@SkipEquatable`、直接の`.equatable()`・`EquatableView`・`equatableBody`参照は禁止する。

比較項目の変更・復元と、入力が等しい状態での外観・文字サイズの追従をマウント済みViewで検査する。製品の操作も画像・録画で確認する。比較による描画回数や応答時間への効果は、同じ条件の測定に基づいて判断する。

## アニメーションの境界

表示変化の範囲を名前付き`AnimationScope`で囲み、valueによる変更検知またはproxyの`scope.animate`を使う。複数triggerのfactoryは`AnimationTrigger.animation`と型名を明記する。入力など親のアニメーションを受けない領域には`animationBarrier()`を置く。

製品の通知scopeは`Library.Notice`とし、通知の有無をvalueで検知する。表示・消去は0.16秒のopacity遷移、Reduce Motion有効時はduration 0秒とする。通知本文の更新と表示の有無を区別し、scopeを必要な表示部分に限定する。

`LibraryView`と`SnippetEditor`の外側の`animationBarrier(warnsOnLeaks: false)`は、OSのシートtransactionが内容へ伝わるのを防ぐ。内側の`detectAnimationLeaks()`と編集入力領域の警告付きbarrierは、アプリ内部の伝播をDebug実行時に診断する。標準シート・メニュー・キーボード自体の遷移はOS部品が管理する。

診断の対象はmodifierの位置へ届くtransactionであり、子孫の全表示変化やUIKitを自動検査する機能ではない。同じ状態更新による変化もscopeが自動分離するわけではないため、Reduce Motion、入力・スクロール・遷移を画像と録画で確認する。

## Lintと禁止する直接使用

`swift-library-policy`は字句解析とSwift構文木を使い、直接API、タスク開始、View比較の規約を検査する。ローカルとUbuntu CIは同じNixのPython環境とtree-sitter-language-pack 1.4.1を使用する。違反はファイル・行・列を表示して終了コード1で失敗する。

```sh
nix develop --command python3 scripts/check_swift_policy.py
nix flake check --no-update-lock-file --print-build-logs
```

### 直接APIの制限

| 禁止するもの | 代表例 | 使用する入口 |
| --- | --- | --- |
| 生のTaskの生成・保持・別名・関数参照 | `Task {}`、`Task.detached`、`Task<…>.init`、Task型handle | Tasking、または構造化された処理 |
| 別scheduler | `DispatchQueue`、`DispatchWorkItem`、`DispatchSource`、`OperationQueue`、`BlockOperation`、`Thread`、`Timer` | Taskingによる所有、協調的なsleep |
| SwiftUIの直接アニメーション | `withAnimation`、`withTransaction`、`Transaction`、`.animation`、`.transaction`、`.phaseAnimator`、`.keyframeAnimator` | scope・proxy・barrier |
| UIKit / Core Animationの直接アニメーション | `UIView.animate`・`transition`等、`UIViewPropertyAnimator`、CAAnimation系、`CATransaction`等 | ScopedAnimation |
| 直接の比較と比較除外 | `.equatable`、`EquatableView`、`.equatableBody`、`@SkipEquatable`、手書き`==` | AppMacrosの比較View、データの標準Equatable合成 |

正確な名前の集合は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)を正とする。予約名は別用途にも使わない。SQLiteのprivate helperには`writeTransaction`を使う。

字句解析はコメント・通常/raw/複数行文字列・regexの本文を読み飛ばし、実行される補間を検査する。改行・コメントを挟む呼出し、修飾名、backtick、型aliasも対象とする。

### タスク開始境界の制限

[scripts/swift_task_boundary.py](../scripts/swift_task_boundary.py)は次の構文を検査する。

| 検査対象 | 許可する形 |
| --- | --- |
| storeの構築 | 所有者のprivateプロパティへ`ViewTaskStore()`を`tasks`、`TaskSlot()`を`taskSlot`として直接代入 |
| 所有する型 | `View`・`UIViewController`・`@MainActor *TaskOwner`。`*Model`・`@Observable`は不可 |
| storeの参照 | 予約したプロパティへの対応メソッドの直接呼出し。型alias・生成関数・引数注入・返却・再代入・capture・メソッド参照は不可 |
| 開始メソッド | 所有者の`startTask`。ViewTaskStoreの開始は同期。TaskSlotのactor呼出しが必要な専用所有者には`async startTask`を許可するが、ViewTaskStore.startをasyncで包む形は不可 |
| 開始メソッドの使用 | 登録済みの開始境界からの直接呼出し。通常メソッドによるラップ、関数参照、別名化は不可 |
| 所有者のテスト | `@Test`の本体でローカルstoreの直接構築と開始を許可。operation内の再開始やaliasは不可 |

登録済みの開始境界は`startTask`、Buttonのaction、`onAppear`・`onDisappear`・`onChange`・`onOpenURL`、sheet/fullScreenCoverの`onDismiss`、UIViewControllerのoverride `viewDidLoad`・`viewDidAppear`・`viewWillAppear`、`@Test`の本体とする。Buttonのlabelやsheetのcontentなど、表示を構築するclosureは含めない。

通常の同期/asyncメソッド、initializer、getter・setter・observer、任意のclosure、SwiftUI `.task`、Taskingのoperationからの開始を拒否する。予約名以外の任意の`.replace`を一律に禁止する規則ではない。

### View比較境界の制限

[scripts/swift_equatable_policy.py](../scripts/swift_equatable_policy.py)は同じ構文木から次の形を検査する。

| 検査対象 | 許可する形 |
| --- | --- |
| 比較Viewの宣言 | `@Equatable`と`EquatableBodyView`をstructへ直接宣言。`View`・`Equatable`の重複準拠は不可 |
| 表示本体 | 同じstructの`equatableBody`。独自`body`による既定実装の上書きは不可 |
| 格納する入力 | 1つ以上の通常の`let`。可変入力、wrapper、所有修飾子、構文上の関数型・closureは不可 |
| 準拠の可視性 | `View`・`Equatable`・`EquatableBodyView`のtypealias、Viewの派生protocol、EquatableBodyViewの派生protocol・extension準拠は不可 |
| 宣言の配置 | `body`・`equatableBody`をextensionへ移さない。Equatable準拠もextensionへ移さない |

これらは比較境界を宣言から読み取れるようにするリポジトリ規約であり、SwiftやAppMacros自体の制限とは区別する。

### 検査対象と保証範囲

所有するSwiftソースを再帰的に探索し、新しいsourceディレクトリも検査する。`artifacts`・`.build`・`DerivedData`等の生成物は除外する。依存コードは`artifacts`以下に取得し、ライブラリ内部実装は対象に含めない。Swift sourceとsource directoryのsymlink、読めない入力、対象0件はエラーとする。

抑制コメント・ファイル単位の例外は設けない。未対応・壊れた構文も失敗させる。grammarが未対応の`isolated deinit`は`isolated`だけを同じbyte長の空白へ置換して解析し、本体の検査と元ソースの診断位置を保つ。この互換処理は回帰テストで確認する。

LintはSwiftの型解決・macro展開・全プログラムの副作用解析を行わない。独自macroや外部APIの内部動作、callback登録、操作の完了、参照型やalias越しの入力の意味は保証範囲外である。生成コードと型適合はSwift compiler、値だけで表示が決まることはレビュー、完了と表示反映は製品テストで確認する。

新しい入口や構文を認める場合は、規則・回帰テスト・製品テストを合わせて更新する。

## 依存とビルド

| パッケージ | 固定版 | product | 対応条件 |
| --- | --- | --- | --- |
| [swift-tasking](https://github.com/9uiLe/swift-tasking/tree/0.3.0) | 0.3.0 | `Tasking`の`ViewTaskStore`、`TaskingCore`の`TaskSlot` | Swift tools 6.0、iOS 13以上 |
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.1) | 0.2.1 | `ScopedAnimation` | Swift tools 6.2、iOS 17以上 |
| [swift-app-macros](https://github.com/9uiLe/swift-app-macros/tree/0.2.0) | 0.2.0 | `AppMacros` | Swift tools 6.3、iOS / macOS 26以上 |

製品のdeployment targetは26.0、検証ツールチェーンはXcode 26.5 / Swift 6.3.2とする。本体と共有拡張はTasking・ScopedAnimationの同じ固定版をリンクする。AppMacrosは比較Viewを持つ本体とそのテストにリンクする。共有拡張・研究・基盤targetには未使用のproductをリンクしない。

Xcode projectのexact versionと共有`app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`でrevisionを固定する。ネットワーク接続のあるMacで解決する。通常のセットアップでlockを更新しない。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

AppMacrosが使用するswift-syntax 603.0.2も同じlockに固定する。swift-syntaxはMac上のマクロコンパイラを構築する依存で、アプリへリンクするruntimeではない。Tasking・ScopedAnimationは追加の外部パッケージを持たない。補助ツールはNix、アプリのSwift PackageはXcode / SwiftPMで管理する。

マクロはビルド時にMac上で実行される。初回はパッケージのソースとlockを確認し、XcodeのprojectでAppMacrosMacrosの実行を有効にする。対象はswift-app-macros 0.2.0、revision `fc4e4623173a41fbde5a35bcf060ed79bfe51e4a`。手順は[README](../README.md#セットアップ)を参照する。全マクロの検証を無効にする設定は使用せず、依存更新時にも対象revisionの信頼を確認する。

3つの製品ライブラリはMITライセンスで、本体と共有拡張のbundleに`ThirdPartyNotices.txt`を含める。swift-syntaxはApache-2.0とRuntime Library Exceptionで提供される。

## 採用理由と更新条件

| 選定 | 理由 | 運用上の負担 |
| --- | --- | --- |
| Tasking | タスクの所有・寿命・重複方針を共通APIで表す | 操作ごとのID・終了条件、キャンセルと結果反映の整合性を管理する |
| ScopedAnimation | 表示変化の適用範囲をscopeとbarrierで表す | OS遷移との境界、診断位置、Reduce Motionを評価する |
| AppMacros | 全表示値の比較を生成し、View定義側に比較境界を置く | swift-syntaxのビルド時間、macOS 26 / Swift 6.3要件、マクロ展開と入力型を確認する |

依存更新ではexact version・共有lock・ライセンスを照合する。操作の直接await、重複・キャンセル、入力直後の保存・閉じる、共有元への復帰、通知の伝播、比較入力・外観・文字サイズの表示反映をiOS 26.5で確認する。

保守停止、対応OS・ツールチェーンの不適合、測定した応答・描画の悪化、必要な表現への不適合を見直し条件とする。結果には対象ソースと条件を付け、[製品の検証結果](mvp-validation.md)から参照できるようにする。
