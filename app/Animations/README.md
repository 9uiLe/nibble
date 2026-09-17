# 説明アニメーションの制作と配布

Aboutの図は、モバイルのメモ画面で文章を選んでコピーし、nibbleに保存する流れを表す。元の文章を残し、複製を保存先へ運ぶ。二つの枠は同じ端末で使うアプリを並べた説明図で、端末間同期を表さない。説明文はiOSのホスト、図形・動き・自動ループはRiveが管理する。

## 正本と生成物

| ファイル | 役割 |
| --- | --- |
| [about/scene.rml](about/scene.rml) | 編集の正本。図形、タイムライン、State Machine、View Model、Data Bindingを定義する |
| [about/rive.yaml](about/rive.yaml) | CLIプロジェクト名と主Artboardの指定 |
| [assets.json](assets.json) | 検査対象の制作ディレクトリ、配布先、接続契約、CLI版、ソースと出力のハッシュ |
| [about-story.riv](../Nibble/Animations/about-story.riv) | アプリへ同梱する生成済みバイナリ |

操作ラベルはRML内のベクター輪郭として保持する。外部画像、フォントファイル、Luauスクリプト、シェーダーは使用しない。制作・プレビュー・生成はRive CLIで完結し、Rive Editorや`.rev`の手作業を工程に含めない。`.riv`だけを直接修正せず、正本を編集して生成する。

## 再生成とレビュー

Apple Silicon Macで[セットアップ](../../README.md#セットアップ)を完了し、リポジトリルートから実行する。CLI 1.0.4はNixで固定され、生成にRiveアカウントへのログインやRiveの署名は必要ない。

```sh
nix develop --command python3 scripts/rive_assets.py build
nix develop --command python3 scripts/rive_assets.py check
nix develop --command rive app/Animations/about
```

`build`はCLI版とRMLの構造を照合し、`--verify`、`--once`によるunsigned生成を実行する。エラーや警告があれば失敗する。成功時は配布先の`.riv`とassets.jsonのハッシュを更新する。最後のコマンドはライブプレビューである。

`check`はCLIやApple SDKなしで、宣言済みプロジェクトの入力・出力ハッシュとRMLの契約を検査する。ArtboardからState Machine・View Modelへの参照、default instanceのexport、必須プロパティの型と初期値定義の存在、ID重複、旧inputs・スクリプト・シェーダーの混入を確認する。初期値の意味、描画結果、バイナリの互換性は別途検証する。

生成後はRML、生成物、manifestを一緒にレビューする。CLIのinspect、時刻別画像、入力とデータ読み戻しで構造と挙動を確認し、画像を実際に開いて形・配色・構図を評価する。主要な動きは開始、持ち上げ、移動、最大変形、収束で確認し、タイミングと割り込みは再生でも確認する。iOSでは同じ`.riv`の表示と外部制御を検証する。結果と媒体は`artifacts/`へ保存し、[証跡の手順](../../docs/review-evidence.md)で対象ソースと対応付ける。

## Aboutの接続契約

Artboard **About**（480×300）、State Machine **Presentation**、View Model **AboutStory**、exportするdefault instance **Default**を使用する。プロパティは全てView Modelのrootに置く。

| プロパティ | 型・初期値・値域 | 更新方向と意味 |
| --- | --- | --- |
| motionAllowed | Boolean、true、true/false | ホスト→Rive。falseで完成図へ移り、trueへ戻すと先頭から自動再生する |
| active | Boolean、false、true/false | Rive→ホスト。ループ状態ではtrue（画面外などで停止中も保持）。Reduce Motionの完成図ではfalse |
| paper | Color、FFFFFDFC、32-bit ARGB | ホスト→Rive。画面とカード |
| ink | Color、FF31373D、32-bit ARGB | ホスト→Rive。内容を表す線 |
| accent | Color、FFD66C39、32-bit ARGB | ホスト→Rive。選択、保存、確認記号 |
| muted | Color、FFBFC5CB、32-bit ARGB | ホスト→Rive。輪郭と補助的なUI |

色の初期値はライト用の制作値である。ホストは表示時に外観とコントラストに合わせた配色を設定する。`active`は演出専用で、実際のコピーや保存の成功を表さない。ホスト実装の名前・型は[AboutIllustration](../Nibble/AboutIllustration.swift)に定義する。

## 状態と時間

**CopyAndSave**を自動再生し、6.2秒周期で繰り返す。文章選択、コピーメニュー、複製の移動、保存操作、完了の順に進む。チェックと「保存しました」は保存操作後に表示する。主動作は5.4秒までに収束し、完成図を残して次の周期へ移る。ループ境界は次の説明の開始として先頭へ戻す。再生・停止・再視聴の操作ボタンは設けない。

| 条件 | 振る舞い |
| --- | --- |
| motionAllowed=trueで入場 | CopyAndSaveを自動で繰り返す。active=true |
| motionAllowed=falseで入場、または途中でfalseへ変更 | Overviewの完成図へ移る。active=false |
| motionAllowedをtrueへ変更 | CopyAndSaveの先頭から自動ループを再開する |
| 画面外・バックグラウンド | ホストがフレーム進行を止め、Sessionと再生位置を保持する |
| 停止条件の解除 | 同じSessionの位置から進む |
| Session破棄後の再入場 | 新しいSessionで開始し、現在のmotionAllowedを適用する |

背景は透過し、ホストの背景面を使用する。モバイルの枠と選択・保存の反応を残し、ライト・ダーク・コントラスト強調の配色をホストから渡す。

ホストは停止中の配色更新にCanvasの`renderingRevision`を用いる。表示と再生位置を分けて管理する契約は[RivePresentation](../Packages/RivePresentation/README.md)に定義する。読み上げと文字拡大はホストの説明文が担当し、図の意味をアクセシビリティツリーへ重複して追加しない。

## アセットの追加・契約変更

1. 制作ディレクトリにRMLとrive.yamlを置き、名前、型、初期値、更新方向、状態遷移を定義する。
2. assets.jsonに制作ディレクトリ、配布先、接続契約を登録する。検査はこの宣言を対象とし、未登録のディレクトリを自動発見しない。
3. ホストの`RiveContract`と操作を実装し、生成物をアプリのBundleへ同梱する。
4. `build`と`check`を実行し、実バイナリの契約・状態・表示をiOSで確認する。
5. 制作ソース、生成物、manifest、ホスト、設計資料、検証記録を同じ変更としてレビューする。

採用版のCLI help・schemaとApple runtime APIで、制作可能性と実行可能性を別々に確認する。機能や依存の変更は[演出設計](../../docs/decisions/0004-rive-presentation.md)の制約に従い、終了コードやハッシュ照合だけで表現・動作を合格にしない。
