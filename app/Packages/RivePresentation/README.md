# RivePresentation

iOS 26.0以上向けのRive表示基盤。Rive iOSの新Apple runtime APIとData Bindingを使うSwift Packageである。製品固有のファイル、配色、文章、演出の状態は含めない。

## 公開する責務

- `RiveResource.load(named:in:)`：指定Bundleのローカル`.riv`を非同期に読み込む。Resourceを保持してFileとWorkerを再利用できる。
- `RiveContract`：Artboard、State Machine、View Model、必須のroot property名と型。
- `makeSession`：契約の名前と型を検査し、独立した可変の再生状態を作る。必須プロパティが欠ける・型が違う場合は表示前に失敗する。
- `RiveSession`：新APIの`rive`と型付きData Bindingの`data`を保持する。一つの表示に一つのsessionを使う。
- `RiveCanvas`：SwiftUIから表示し、画面離脱・アプリ非アクティブ時に停止する。ホストが渡す`paused`でも停止する。
- `renderingRevision`：停止中に配色などを更新した場合の描画更新番号。値が変わると表示用Viewだけを作り直し、同じFile・Artboard・State Machine・View Modelから時間を進めずに描画する。ロードや演出の再開には使わない。

ロードと生成はMainActorのasync APIで、途中のキャンセルを確認してから結果を返す。Viewのbody内で生成せず、`.task`から待ち、`@State`等の所有者に結果を保持する。1個のsessionを複数のCanvasに同時に渡さない。

ホストはロード中と失敗時の表示、再試行、Reduce Motion、スクロールによる画面外判定、読み上げ、表示比率、必要なfit、タッチの有無を決める。Canvasは表示サイズを強制しない。インタラクティブなアセットでは実際のfitとタッチ座標を対象端末で検証する。

Data Bindingの値やtriggerの更新は演出への要求である。業務処理の成功通知として扱わない。購読は画面所有の`.task`で行い、キャンセルで解除する。Legacy APIへの接続や自動フォールバックは提供しない。

## 依存と移設

RiveRuntime 6.27.0をexact指定する。ホストアプリのPackage.resolvedも共有する。このディレクトリを別リポジトリへ移してもPackage.swiftとSourcesだけで利用できる。ホスト側が持つRML、`.riv`、接続契約、アクセシビリティの判断は移設先の製品が管理する。

このリポジトリでは、実際の生成物に対する契約検査、独立したインスタンス、状態遷移を本体のiOS 26.5テストtargetで確認する。[設計と評価境界](../../../docs/decisions/0004-rive-presentation.md)を参照。
