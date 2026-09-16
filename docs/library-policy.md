# 非同期処理・アニメーション・View比較の実装規約

この規約は、本体、共有拡張、テスト、研究用アプリ、検証用Swiftに適用する。目的は、処理の完了、タスクの所有、表示の更新条件をコードから読み取れるようにすること。製品のデータと操作は[製品設計](decisions/0002-mvp-app.md)、実行手順は[MVP手順](mvp.md)、確認したソースと条件は[検証結果](mvp-validation.md)に定義する。

## 責務と使用するAPI

| 責務 | 実装する場所 | 使用するAPI |
| --- | --- | --- |
| 処理と結果反映を完了させる | モデルの操作メソッド | `async` / `await`、構造化されたSwift Concurrency |
| UIイベントから非同期処理を開始する | View、UIViewController、専用のタスク所有者 | `startTask`、swift-taskingの`ViewTaskStore` / `TaskSlot` |
| 表示値の比較で更新を制御する | 値だけを入力に持つ表示用View | swift-app-macrosの`@Equatable` / `EquatableBodyView` |
| アニメーションの適用範囲を決める | 変化させる表示部分とその境界 | swift-scoped-animationの`AnimationScope` / `animationBarrier` |

モデルが操作を完了し、UIがその操作を実行するタスクの寿命を管理する。表示入力の比較で更新を制御する範囲を「比較境界」、アニメーションを適用する範囲を「scope」と呼ぶ。状態・操作の所有と、表示値の比較を分けて設計する。

## 操作APIと開始API

### 操作の完了

モデルの操作APIは`async`とし、受理した処理と結果反映を待ってから戻る。呼出元は、そのAPIをawaitした直後に表示状態や永続化結果を検査できる。APIごとに成功・失敗・キャンセル・受け付けない条件を定義する。

同期メソッド、initializer、setter、observerは同期的な状態の初期化・更新を行う。これらの内部から非同期処理を開始しない。`async`メソッドも、非構造化タスクを開始して操作の完了前に戻る形にしない。

### タスクの開始

`startTask`はUI所有者の開始入口である。戻り値は開始を受理したかを表し、業務処理の完了は表さない。所有者はTaskingへ渡すoperationの中でモデルを直接awaitする。operationの中から別の非構造化タスクを開始しない。

モデルはTaskingのstoreや開始用closureを保持・受領しない。呼出元は状況に応じて次の形を選ぶ。

| 呼出元 | 実装方法 | 終了の責務 |
| --- | --- | --- |
| 既存のasync処理 | `await model.refresh()`等の直接呼出し | 呼出元が完了、エラー、キャンセルを扱う |
| scope内で並行する子処理 | `async let`、task group | 親処理が子処理の完了を待つ |
| Viewや状態IDに結び付く処理 | SwiftUI `.task` / `.task(id:)`から直接await | SwiftUIがView終了やID変更でキャンセルを要求する |
| 同期UIイベント | `startTask`と`ViewTaskStore.start` | UI所有者がID・寿命・重複方針・終了イベントを定義する |
| 単一処理を置換する専用所有者 | `@MainActor *TaskOwner`の`TaskSlot`と`startTask` | 所有者が終了待ちを提供する。製品MVPはこの形を使用しない |

actor、checked continuation、`CancellationError`を利用できる。既存タスク内での待機・協調には`Task.sleep`・`yield`・`checkCancellation`・`isCancelled`・`currentPriority`を使える。

### 実装例

`ExampleModel.refresh()`は読込と状態反映を完了まで待つ操作である。`ExampleView`はボタンからタスクを開始し、画面終了時にキャンセルを要求する。

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

この例の終了条件は、画面が消えたら停止を求める操作に適用する。シートの開閉をまたいで完了させる一覧操作には、sceneに対応する寿命と終了条件を設ける。

## 所有者と重複方針

`ViewTaskStore`を保持できる型は`View`、`UIViewController`、専用の`@MainActor *TaskOwner`とする。`*Model`と`@Observable`型はタスク所有者にしない。

製品では、`LibraryView`が一覧モデルと`LibraryTaskOwner`を`@State`で保持する。`SnippetEditor`は編集モデルと終了操作のstore、`ShareViewController`は共有データを読み込むstoreを持つ。

| 設定・API | 意味と規則 |
| --- | --- |
| `ActionID` | 重複判定の単位。項目ごとに独立させる操作は、操作種別とUUIDを含める |
| `cancelExisting` | 同じIDの実行へキャンセルを要求して次を開始する。結果反映時にも要求の有効性を確認する |
| `ignoreNew` | 同じIDが実行中なら次の開始要求を受け付けない |
| `allowConcurrent` | 同時実行しても整合する条件を定義した操作に使う |
| `ActionLifetime` | キャンセル対象を分類する値。Viewやsceneのイベントを自動監視しない |
| `waitForIdle`等 | 所有者の終了待ち。所有・重複・キャンセルのテストで使う |

製品の操作ごとの設定は[操作の寿命と整合性](decisions/0002-mvp-app.md#操作の寿命と整合性)に定義する。一覧読込・コピー・項目更新はsceneBoundの有限処理として扱い、一覧Viewの`onDisappear`ではキャンセルしない。background化では`LibraryTaskOwner.endScreen()`で編集開始を止め、同期APIの`clearNotice()`で通知を消す。

編集終了は`SnippetEditor.onDisappear`、共有データ読込は`ShareViewController.viewDidDisappear`でscreenBoundをキャンセルする。所有者が保持するモデル、画面、完了通知の解放条件も確認する。

## 完了・キャンセル・永続化

キャンセルは協調的な停止要求である。確定済みのDB変更を巻き戻す機能として使わない。操作の入口と結果反映には次の条件を設ける。

| 操作 | 条件 |
| --- | --- |
| 一覧取得 | 読込後にキャンセル、要求識別子、検索条件を照合して結果を反映 |
| コピー | DB読込の前後でキャンセルを確認。本文のクリップボード書込と通知設定で完了 |
| 編集開始・項目更新 | 開始時のキャンセル・重複条件を確認し、受理したDB処理を完了させる |
| 自動保存 | 編集中の同じ下書きへのsnapshotだけを受理。受理した書込の適用はDBの入力番号で判断 |
| 編集終了 | キャンセルされておらず`phase == .editing`の場合だけ受理。永続化成功後はキャンセルが届いていてもUIへ成功を返す |
| 共有データ読込 | 取得の前後でキャンセルを確認。キャンセルを入力エラーとして表示しない |
| 通知期限 | 待機後にキャンセルと通知IDを確認し、その通知だけを消す |

### 下書きと終了操作

`Draft`は入力のUTF-8が変化すると`sequence`を増やす。画面はその時点の下書きを固定したsnapshotを作り、`.task(id: snapshot.sequence)`から`persist(snapshot)`を直接awaitする。setterはタスクを開始しない。SwiftUIが入力更新を集約するため、すべてのキーストロークを個別保存する契約にはしない。

`finish(_:)`は保存・別項目への保存・閉じる・破棄の入口とする。入力を固定して`editing → finishing`へ遷移し、成功時は`finished`、失敗時は入力を保持して`editing`へ戻る。終了処理中と終了後は入力変更も終了の再実行も受け付けない。

保存と閉じるは自動保存の開始に依存せず、固定した入力を保存層へ渡す。保存層がトランザクション内で下書きのUUID・対象項目・更新番号・入力番号を照合する。同じ入力番号の原文比較にはUTF-8を使う。別項目への保存では、置き換え条件に合わない下書きを保持する。具体的な条件は[入力の保存と編集の終了](decisions/0002-mvp-app.md#入力の保存と編集の終了)に従う。

### 通知とエラー

通知のID・本文・取り消し対象は1つの値として保持する。コピー等の操作完了に表示期間を含めず、`.task(id: notice?.id)`から`expireNotice(id:)`をawaitする。

業務上の失敗はモデルの表示状態へ変換する。編集失敗には説明と回復可能な操作を持たせ、入力を残す。非同期の書込結果は対象snapshotの入力番号と編集状態を確認し、新しい入力や終了結果へ古いエラーを反映しない。

Taskingのstoreへ流出した非キャンセルエラーはDebug assertionの対象になる。空のcatchで失敗を消さず、キャンセルを正常な終了として扱うcatchと区別する。

## Viewの比較境界

比較Viewは`@Equatable`を付けた`@MainActor EquatableBodyView`とし、準拠と等価比較をMainActorに隔離する。同じstructの`equatableBody`に内容を書く。ライブラリの既定の`body`が等価比較を適用するため、呼出側は通常のViewとして配置する。

```swift
import AppMacros
import SwiftUI

@Equatable
struct CaptionContent: @MainActor EquatableBodyView {
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

正確な名前の集合は[scripts/check_swift_policy.py](../scripts/check_swift_policy.py)を正とする。予約名は別用途にも使わない。SQLiteのhelperには`readTransaction`・`writeTransaction`を使い、共通の確定・rollbackはprivateな`performTransaction`に閉じ込める。

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
| [swift-scoped-animation](https://github.com/9uiLe/swift-scoped-animation/tree/v0.2.2) | 0.2.2 | `ScopedAnimation` | Swift tools 6.2、iOS 17以上 |
| [swift-app-macros](https://github.com/9uiLe/swift-app-macros/tree/0.3.0) | 0.3.0 | `AppMacros` | Swift tools 6.3、iOS / macOS 26以上 |

製品のdeployment targetは26.0、検証ツールチェーンはXcode 26.5 / Swift 6.3.2とする。本体と共有拡張はTasking・ScopedAnimationの同じ固定版をリンクする。AppMacrosは比較Viewを持つ本体とそのテストにリンクする。共有拡張・研究・基盤targetには未使用のproductをリンクしない。

Xcode projectのexact versionと共有`app/Nibble.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`でrevisionを固定する。ネットワーク接続のあるMacで解決する。通常のセットアップでlockを更新しない。

```sh
xcodebuild -resolvePackageDependencies \
  -project app/Nibble.xcodeproj -scheme Nibble \
  -clonedSourcePackagesDirPath artifacts/SourcePackages
```

AppMacrosのPackage.swiftがexact versionを要求するswift-syntax 603.0.2も同じlockに固定する。swift-syntaxはMac上のマクロコンパイラを構築する依存で、アプリへリンクするruntimeではない。単独で別の版へ更新せず、AppMacrosの要求とツールチェーンの互換性を確認する。Tasking・ScopedAnimationは追加の外部パッケージを持たない。補助ツールはNix、アプリのSwift PackageはXcode / SwiftPMで管理する。

マクロはビルド時にMac上で実行される。初回はパッケージのソースとlockを確認し、XcodeのprojectでAppMacrosMacrosの実行を有効にする。対象はswift-app-macros 0.3.0、revision `9b6d5d699b44990029cdfa61cddf35cec46d1520`。手順は[README](../README.md#セットアップ)を参照する。全マクロの検証を無効にする設定は使用せず、依存更新時にも対象revisionの信頼を確認する。

3つの製品ライブラリはMITライセンスで、本体と共有拡張のbundleに`ThirdPartyNotices.txt`を含める。swift-syntaxはApache-2.0とRuntime Library Exceptionで提供される。

## 採用理由と更新条件

| 選定 | 理由 | 運用上の負担 |
| --- | --- | --- |
| Tasking | タスクの所有・寿命・重複方針を共通APIで表す | 操作ごとのID・終了条件、キャンセルと結果反映の整合性を管理する |
| ScopedAnimation | 表示変化の適用範囲をscopeとbarrierで表す | OS遷移との境界、診断位置、Reduce Motionを評価する |
| AppMacros | 全表示値の比較を生成し、View定義側に比較境界を置く | swift-syntaxのビルド時間、macOS 26 / Swift 6.3要件、マクロ展開と入力型を確認する |

依存更新ではexact version・共有lock・ライセンスを照合する。操作の直接await、重複・キャンセル、入力直後の保存・閉じる、共有元への復帰、通知の伝播、比較入力・外観・文字サイズの表示反映をiOS 26.5で確認する。

保守停止、対応OS・ツールチェーンの不適合、測定した応答・描画の悪化、必要な表現への不適合を見直し条件とする。結果には対象ソースと条件を付け、[製品の検証結果](mvp-validation.md)から参照できるようにする。
