# 説明アニメーションの制作と配布

「nibbleについて」のイラストは、メモ画面の文章を選び、コピーした複製をnibbleへ保存する流れを表す。二つのモバイル画面を並べ、元の文章が残ることと保存先に項目が増えることを示す。図形と時間はRive、説明文と画面の設定はiOSのホストが管理する。

本書は制作ファイル、外部との接続、再生成、検証の手順を定める。配置と表現の理由は[演出設計](../../docs/decisions/0004-rive-presentation.md)、iOSの所有関係は[RivePresentation](../Packages/RivePresentation/README.md)、対象ソースの観測は[検証記録](../../docs/rive-validation.md)を参照する。

## 制作ファイルと環境

| ファイル | 役割 |
| --- | --- |
| [about/scene.rml](about/scene.rml) | 編集の正本。図形、タイムライン、状態遷移、Data Bindingを定義する |
| [about/rive.yaml](about/rive.yaml) | CLIプロジェクト名と主Artboardの指定 |
| [assets.json](assets.json) | 制作ディレクトリ、配布先、接続契約、CLI版、入力と出力のハッシュを登録するmanifest |
| [about-story.riv](../Nibble/Animations/about-story.riv) | アプリのBundleへ同梱する生成済みバイナリ |

制作・プレビュー・生成にはNixで固定したRive CLI 1.0.4をApple Silicon Macで使用する。表示先はrive-ios 6.27.0のApple runtime APIとData Bindingである。採用版との整合を優先し、機能を使う前にCLIのhelp・schemaとランタイムの対応を別々に確認する。

図中のラベルはRML内のベクター輪郭であり、外部画像・フォントファイルを必要としない。Luauスクリプトとシェーダーは使用しない。Rive Editor、`.rev`、ログイン、Riveの署名は本構成の制作工程に含まれない。`.riv`を直接修正せず、RMLから再生成する。

## 接続契約

Artboardは描画面、State Machineは演出の状態と遷移、View Modelは外部と受け渡す型付きデータを定義する。ホストは次の名前で読み込み、View Modelのdefault instanceを各Sessionへ生成する。

| 対象 | 名前・条件 |
| --- | --- |
| Artboard | `About`、480×300、背景透過 |
| State Machine | `Presentation` |
| View Model | `AboutStory` |
| default instance | `Default`、export有効 |
| タイムライン | `CopyAndSave`：372 frames / 60 fps / loop、`Overview`：静止した完成図 |

プロパティはすべてView Modelのroot（直下）に置く。

| プロパティ | 型・初期値・値域 | 更新方向と意味 |
| --- | --- | --- |
| `motionAllowed` | Boolean、true、true/false | ホスト→Rive。動きが許可されるかを指定する |
| `active` | Boolean、false、true/false | Rive→ホスト。ループ状態でtrue、完成図の状態でfalse。フレーム停止中も値を保持する |
| `paper` | Color、FFFFFDFC、32-bit ARGB | ホスト→Rive。画面とカードの面 |
| `ink` | Color、FF31373D、32-bit ARGB | ホスト→Rive。内容を表す線 |
| `accent` | Color、FFD66C39、32-bit ARGB | ホスト→Rive。選択、保存、確認記号 |
| `muted` | Color、FFBFC5CB、32-bit ARGB | ホスト→Rive。輪郭と補助的なUI |

色の初期値はライト用の制作値で、ホストが表示時に外観とコントラストに合う値を設定する。`active`の初期値はfalseであり、State Machineが状態を評価して更新する。これは実際のコピーや保存の結果ではない。ホストの[AboutIllustration](../Nibble/AboutIllustration.swift)は名前・型を宣言し、入力だけを書き込む。

## 演出の状態と時間

`CopyAndSave`は、文章選択→コピーメニュー→複製の移動→保存操作→完了表示を6.2秒で繰り返す。主動作は5.4秒までに収束する。完成図を保持する時間を含めて一周期とし、境界で次の説明の開始位置へ戻る。

| 入力・寿命 | Riveの状態と再生位置 |
| --- | --- |
| `motionAllowed=true`で開始 | CopyAndSaveを先頭から自動ループする。`active=true` |
| `motionAllowed=false`で開始、または再生中にfalseへ変更 | Overviewの完成図へ移る。`active=false` |
| `motionAllowed`をfalseからtrueへ変更 | CopyAndSaveの先頭から自動ループする |
| ホストがフレーム進行を停止 | 選択中の状態、再生位置、Data Binding値を保持する |
| ホストがフレーム進行を再開 | 保持した位置から進む。停止中の入力は次の評価で反映する |
| Sessionを破棄して新規生成 | default instanceから開始し、現在のホスト設定を適用する |

アセットへ直接触れる操作や再生ボタンは設けない。図の下の説明文が意味と読み上げを担う。nibbleはmotionAllowedをtrueに固定する。表示範囲外での停止、停止中の配色更新は[ホストとCanvasの契約](../Packages/RivePresentation/README.md#停止と再描画)に従って接続する。

## 編集と再生成

[セットアップ](../../README.md#セットアップ)後、リポジトリルートで実行する。

```sh
nix develop --command rive app/Animations/about
nix develop --command python3 scripts/rive_assets.py build
nix develop --command python3 scripts/rive_assets.py check
```

最初のコマンドはライブプレビューを起動する。RMLの編集結果を確認して終了し、`build`で配布物を生成する。`build`はCLI版とRMLの構造を照合し、`--verify`、`--once`によるunsigned生成を実行する。エラー・警告があると失敗し、成功時は配布先の`.riv`とmanifestのハッシュを更新する。

`check`はCLIやApple SDKを使わず、manifestへ登録されたアセットを検査する。

| 検査するもの | 検査の境界 |
| --- | --- |
| 入力・出力のハッシュ | 保存したソースと生成物の対応。描画や生成処理そのものの正しさは判定しない |
| Artboardからの参照 | State Machine、View Model、exportしたdefault instanceの接続 |
| プロパティ | 必須の名前・型・初期値定義の存在。初期値の意味と状態遷移は別に確認する |
| 制作要素 | ID重複、旧inputs、スクリプト、シェーダーの混入 |

制作ソース、生成物、manifestを一緒にレビューする。ハッシュだけを書き換えて再生成の代用にしない。

## 表現と実行の検証

生成に成功した後、次の独立した観点を確認する。

1. **構造**：CLIのinspectと実バイナリのiOSテストで、接続名・型・独立したSessionを確認する。
2. **静止画**：開始、選択、持ち上げ、移動、最大変形、収束を出力して開き、輪郭・配色・重なり・構図を確認する。
3. **時間と状態**：複数周期を再生し、保存前後の順序と周期境界を確認する。`motionAllowed`の初期値と途中変更を試し、`active`を読み戻す。
4. **iOS統合**：同じ`.riv`を対象アプリで動かし、外観、Reduce Motion、背景復帰、文字拡大、失敗時の表示を確認する。
5. **負担**：容量と必要な描画指標を条件付きで記録する。CLI、Simulator、実機の測定を区別する。

画像出力ではviewportとfitを明示し、実際の画像寸法と内容を確認する。終了コードの成功だけでフラグの適用を判断しない。記録を`artifacts/`へ保存し、[証跡の手順](../../docs/review-evidence.md)で対象ソースと対応付ける。

## アセットの追加・契約変更

1. 制作ディレクトリへRMLとrive.yamlを置き、表現の目的、名前・型・初期値・更新方向、状態遷移を定義する。
2. assets.jsonへ制作ディレクトリ、配布先、接続契約を登録する。未登録のディレクトリは検査対象にならない。
3. ホストの`RiveContract`、所有者、表示条件を定め、生成物を対象Bundleへ同梱する。
4. `build`と`check`、影響範囲の表現・実行検証を行う。
5. アセット、ホスト、設計資料、検証記録を同じ変更としてレビューする。

機能や依存を変更するときは、[演出設計の保守条件](../../docs/decisions/0004-rive-presentation.md#保守と受け入れ)に従う。
