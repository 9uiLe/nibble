# Rive表示基盤の検証

RivePresentation、AboutIllustration、AboutStoryアセットを対象とする実行記録。採用する責務と振る舞いは[演出設計](decisions/0004-rive-presentation.md)、再生成は[アセット手順](../app/Animations/README.md)に定義する。本書は観測した結果と、その保証範囲を記録する。

## 対象ソースと環境

評価する製品ソースは `d127c4dfa682ebf4e2119c7d4aca0af6a9afa7f0`。下表の成功runは、実行開始・終了時の入力ファイルとこのコミットの内容が証跡検査で一致した記録である。実行時の作業ツリーには未コミットの変更が含まれるため、manifestのHEAD名だけでは対象を判断しない。

| 条件 | 値 |
| --- | --- |
| 実行日 | 2026-09-17 |
| Mac / ツールチェーン | Apple Silicon、macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2 |
| 依存 | Nix固定のRive CLI 1.0.4、exact指定・共有lockのrive-ios 6.27.0 |
| 端末 | iPhone SE第3世代 Simulator、iOS 26.5（23F77） |
| 画面 | 375×667 pt、PNG 750×1334 px |
| 専用UDID | `AED98CBE-D67C-44EB-8B9D-F94719466B1A` |
| 生成物 | about-story.riv、4,884 bytes |
| SHA-256 | `0fc5cf5e179c69db4e8a90818d6270eda4d1445f54762142c2079d5bd447fabf` |

最低対応OSはiOS 26.0、実行評価は26.5である。文書のみを変更したコミットで結果を再利用する際も、[証跡検査](review-evidence.md)で入力と媒体の一致を確認する。MarkdownはiOSの検証入力に含めない。

## 確認結果

### CLIによる生成・構造・表示

- verify、inspect、unsigned生成はエラー・警告0。
- About / Presentation / AboutStory.Defaultと7つのData Bindingプロパティを確認した。
- 開始、持ち上げ、移動、ペースト、収束、Reduce Motionを800×416で出力した。開始・移動・収束・静止の原本を開き、元のカードが残ること、複製が前面を移ること、入力先の行と確認記号が現れることを確認した。
- データ読み戻しでは、通常再生後にactive=falseとなった。motionAllowed=falseで初期化した出力は完成図となった。

ログ、画像、data-dumpは `artifacts/rive/` に保存した。時刻別画像と読み戻しは連続再生の観測と区別する。ハッシュ照合は宣言済みソースと出力の対応を検査するもので、生成の実行やバイナリの意味を証明しない。実際の生成物の契約はiOSテストでも検査した。

### iOSのビルド・挙動・閲覧

| run ID | 内容 | 結果 |
| --- | --- | --- |
| `20260917T141448Z-test-55ddb0` | Release製品テスト | 61件成功、失敗0。実.rivの契約、File共有と独立した可変状態、完了・再視聴・Reduce Motion、欠損リソースを含む |
| `20260917T141124Z-rive-about-aed5e7` | 通常起動・再生・一時停止・配色・復帰・閲覧 | 成功。再生操作のAX高さ44 pt、5秒のバックグラウンド滞在後の再生位置保持、ライト・ダーク・最大文字で末尾と設定への戻りを確認 |
| `20260917T141552Z-rive-about-reduced-b1efcf` | Reduce Motion・静止図・閲覧 | 成功。設定false→true→falseを読み戻し、再生ボタンなし、ライト・ダーク・最大文字で末尾へ到達 |

各runのmanifest、媒体、レビュー申告は `artifacts/ios/<run ID>/` に保存する。通常runの一時停止中のライト→ダーク→コントラスト強調→ライトのPNGでは、配色が反映され、カードの位置と形が保たれた。説明文と図は重ならず、最大文字でも末尾の段落まで到達した。Reduce MotionのPNGは完成図と通常時と同じ説明文を示した。

| 録画 | 原本の長さ | 確認した抽出時刻 |
| --- | --- | --- |
| 通常 | 92.082秒 | 4.575 / 46.510 / 82.773秒 |
| Reduce Motion | 60.183秒 | 3.405 / 30.090 / 54.335秒 |

原本PNGと上記の抽出フレームを目視した。全編を連続再生した確認とは扱わない。PR添付のブラウザー確認は、ログインした所有者の閲覧条件で画像の読込サイズと動画プレーヤーの読込を確認したもの。アクセス条件と原本・プレーヤーそれぞれの動画時間は各runのreview.jsonに記録する。

### 共通検査

`nix flake check --no-update-lock-file --print-build-logs`の7項目が成功した。Python回帰99件には生成契約の5件とLegacy API検出を含む。共通UI設計の回帰35件、Swift規約、文書、workflow、Nix整形、生成物の照合も成功した。

これらは検査規則と記録の整合性を評価する。例えばRML検査は初期値定義の存在を確認するが、その値の意味を判定しない。SwiftのLegacy API検査は指定した6つの入口識別子を検出する構文検査であり、全APIの型解決ではない。

## 検証で区別する失敗条件

以下は評価対象の完成版とは異なる作業ツリーの観測である。対象ファイルは各runのmanifestのハッシュで識別し、成功runへ上書きしない。

| 条件と記録 | 観測 | 完成版の確認境界 |
| --- | --- | --- |
| Frameworkの探索経路。`20260917T134530Z-rive-about-852d43`、`20260917T134730Z-rive-about-d49595` | テストhostの起動だけでは通常アプリ起動時のRiveRuntime解決を保証できなかった | 本体のDebug / Releaseに必要なrunpathを設定。通常のinstall・launchを含むRelease UI runで起動を確認 |
| 一時停止中の外観。`20260917T140536Z-rive-lifecycle-aacdd7` | Data Bindingの配色変更が描画されなかった。driverの操作成功は視覚品質の合格を意味しない | `renderingRevision`で表示用Viewを更新する実装を、通常runの停止中の配色変更と位置保持で確認 |
| SimulatorのReduce Motion操作 | Settingsの行中央へのタップではswitch値が変化しない実行があった | driverはAXからswitch位置を取得し、設定値を読み戻す。成功runは変更と復元の両方を記録 |

## サイズと描画コスト

### Simulator用アプリの容量

比較元は `584142d32dbc9be907bb20513d0c1e1d446d8001`、比較先は上記の評価対象と一致する製品入力。同じXcode、Release、iOS Simulator 26.5、arm64 + x86_64で、テストbundleとdSYMを除いた非圧縮ファイルの合計を比較した。集計は `artifacts/rive/simulator-size.json` に保存した。

| 非圧縮Simulator bundle | 比較元 | Riveを含む構成 |
| --- | ---: | ---: |
| 本体（共有拡張を含む） | 7,345,008 bytes | 17,825,550 bytes |
| 同梱RiveRuntime.framework | 0 bytes | 10,144,296 bytes |
| 共有拡張 | 2,082,519 bytes | 2,083,317 bytes |

本体は10,480,542 bytes増加した。拡張の798 bytes増加は共有ライセンス文書で、拡張にRiveRuntimeはリンクしない。アニメーション自体は4,884 bytes。この結果はApp Storeの圧縮・端末別ダウンロード量を示さない。

### CLIの描画

headlessベンチマークの条件は400×208、300 frames。advance平均0.001 ms、render平均0.142 ms / p95 0.383 ms / 最大0.486 msだった。CLIの測定値であり、iOSのfpsやGPU時間には換算しない。

## 未評価の条件

実機はMVPの評価範囲外。iOS 26.0での実行、GPUのフレーム時間・電力、VoiceOverの音声・ローター操作、利用者調査による理解度は未評価。AXラベル・操作領域とSimulatorの画像だけでこれらの成功を主張しない。

スクロールによる画面外停止は実装を照合したが、不可視中のGPU停止は直接計測していない。待機時のプロセス計測はロード、OSキャッシュ、他のUIも含むため、Rive単独のコストには使わない。署名配布とTestFlightでの動作は本記録の対象に含めない。

## 再実行の手順

[セットアップ](../README.md#セットアップ)を済ませ、専用のiOS 26.5 Simulatorを指定する。以下のUDIDは本記録の端末であり、別環境ではその環境の専用端末へ置き換える。UI driverの実行前に、SimulatorのSettingsで「アクセシビリティ→動作」を開く。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A
nix develop --command python3 scripts/check-about-ui.py \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A
nix develop --command python3 scripts/check-about-ui.py \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A --reduce-motion enabled
```

UI driverはReduce Motionの実値を読み、指定値へ変更し、終了時に元へ戻す。外観、文字サイズ、コントラストも保存・復元する。コマンドの成功後に、対象コミットとの照合、原本と録画の観察、レビュー申告と添付の確認を[証跡の手順](review-evidence.md)に従って行う。
