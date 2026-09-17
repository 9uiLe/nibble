# コピー・保存アニメーションの検証

RivePresentation、AboutIllustration、同梱アセットabout-story.rivの実行記録。対象は、メモ画面で文章を選んでコピーし、nibbleへ保存する6.2秒の自動ループである。採用する構成は[演出設計](decisions/0004-rive-presentation.md)、生成手順は[アセット手順](../app/Animations/README.md)に定義する。

## 対象ソースと環境

評価対象コミットは`33fdbef9d2f074eba58f76c9aa8123009bf16541`。下記の成功runは、開始・終了時に記録した入力ファイルとこのコミットの内容が証跡検査で一致した。実行時のHEAD名だけで対象ソースを判定しない。

| 条件 | 値 |
| --- | --- |
| 実行日 | 2026-09-18（JST。run IDはUTC） |
| Mac / ツールチェーン | Apple Silicon、macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2 |
| 依存 | Nix固定のRive CLI 1.0.4、exact指定・共有lockのrive-ios 6.27.0 |
| 端末 | iPhone SE第3世代 Simulator、iOS 26.5（23F77） |
| 画面 | 375×667 pt、PNG 750×1334 px |
| 専用UDID | `AED98CBE-D67C-44EB-8B9D-F94719466B1A` |
| アセット | Artboard 480×300、372 frames / 60 fps、80,316 bytes |
| RML SHA-256 | `4d91ffe44747c68ecd4afe03a493563b5fe6f3b380a1487014c321a1db43d3e1` |
| `.riv` SHA-256 | `d19985127a961abb687dcea6b819fb3eda2f63bf7681ad8145daf1a0a227cffd` |

最低対応OSはiOS 26.0、実行評価は26.5である。MarkdownはiOS runの入力に含まれない。文書のみの変更で結果を再利用する場合も、[証跡検査](review-evidence.md)で対象コミットの入力と媒体を照合する。

## 確認結果

### CLIの生成・構造・状態

| 観点 | 実行と観測 |
| --- | --- |
| 生成 | verifyとunsigned生成が成功。エラー・警告0 |
| 接続 | About / Presentation / AboutStory.Default、6プロパティの名前・型、default instanceと参照を検査 |
| 反復 | `--fit=contain --viewport=960x600`で90・462・834フレームを出力。3周期の同じ時点のPNGが完全一致し、いずれも`active=true` |
| Reduce Motion | `motionAllowed=false`で`active=false`。完成図のPNGが通常再生の保存後330フレームと一致 |
| 視覚 | コピー選択、複製の移動、保存後の完成図を原本PNGで確認 |

ログ、画像、読み戻し、照合結果は`artifacts/mobile-integration/`に保存した。同じ位相の画像一致は反復の確認であり、周期境界の動きやiOS描画性能の評価とは分ける。

### iOSのテスト・操作

| run ID | 結果 |
| --- | --- |
| `20260917T162046Z-test-d286ec` | Release製品テスト61件成功。実バイナリの契約、独立Session、800フレーム後のループ状態、Reduce Motionの切替、型不一致、欠損リソースを含む |
| `20260917T161619Z-rive-about-b44d0c` | 通常起動、2周期以上の再生、再生ボタンなし、ライト・ダーク・コントラスト、背景復帰、Reduce Motionの有効化・解除、最大文字の末尾到達が成功 |
| `20260917T161843Z-rive-about-reduced-b5794d` | Reduce Motion有効での初回静止、再生ボタンなし、ライト・ダーク・最大文字の末尾到達が成功 |

UI driverは設定値を読み戻し、終了時に元へ復元した。通常runの`motion-disabled.png`と`motion-disabled-still.png`は2秒間隔で完全一致した。runごとのmanifest、媒体、観測は`artifacts/ios/<run ID>/`に保持する。

### 画像と録画のレビュー範囲

通常runでは静止図、動作設定の解除後、大きな文字での上端と末尾を原本PNGで確認した。Reduce Motion runでは初回の完成図とダーク配色を確認した。コピー元に文章が残り、保存先に確認記号があること、背景面と本文の読みやすさを観察した。

| 録画 | 原本の長さ | 確認した範囲 |
| --- | --- | --- |
| 通常 | 101.162秒 | 5.088秒の抽出画像。通常速度のローカル再生中、11.050 / 17.345 / 44.583秒を間欠的に観測し、複数周期の移動場面と保存ボタンを確認 |
| Reduce Motion | 62.322秒 | 30.492秒の抽出画像で最大文字の設定画面を確認。アプリの静止図は別途原本PNGを確認 |

全編を連続して目視したレビューではない。媒体はローカル保存で、GitHubへの添付と公開先の閲覧確認は未実施。各runの`review.json`には実際の観測範囲を記入し、URLと公開閲覧欄は未記入としている。録画にはdriverの待機を含むため、長さをアプリの応答時間へ換算しない。

### 共通検査

`nix flake check --no-update-lock-file --print-build-logs`の7項目が成功した。Python回帰99件、共通UI設計の回帰35件、Swift規約、文書、workflow、Nix整形、生成物の照合を含む。ログは`artifacts/mobile-nix-final.log`に保存した。

これらは構造と記録の整合を検査する。RML検査は初期値定義の存在を確認するが、その値の意味は判定しない。ハッシュ照合だけでは生成物の動作を保証せず、実バイナリの接続はiOSテストでも確認した。

## 容量と描画負荷

### 同条件のSimulator用アプリ容量

比較元は`d127c4dfa682ebf4e2119c7d4aca0af6a9afa7f0`の製品入力、比較先は本書の評価対象。同じXcode、Release、iOS Simulator 26.5の通常ビルドについて、テストbundleとdSYMを除いた非圧縮ファイルの合計を集計した。集計条件とファイル別の値は`artifacts/mobile-integration/simulator-size.json`にある。

| 対象 | 比較元 | 評価対象 | 差 |
| --- | ---: | ---: | ---: |
| 本体（共有拡張を含む） | 17,825,550 bytes | 17,877,158 bytes | +51,608 bytes |
| about-story.riv | 4,884 bytes | 80,316 bytes | +75,432 bytes |
| RiveRuntimeの実行バイナリ | 10,140,992 bytes | 10,140,992 bytes | 0 bytes |

アセットにはモバイル画面とラベルのベクター輪郭を含む。外部フォント・画像・新しい依存の追加はない。この集計はApp Storeの圧縮後サイズや端末別ダウンロード量を示さない。比較元の環境・実行記録は[固定コミットの検証資料](https://github.com/9uiLe/nibble/blob/414fba981fe5d60284fd016bcb371a1dcd38e492/docs/rive-validation.md)を参照する。

### CLIベンチマークの限界

900フレームの測定で`--viewport=960x600 --fit=contain`を指定したが、ログはそれぞれ制作キャンバスの400×208と480×300を示した。同寸法の比較は成立せず、並行したXcodeコンパイルもある。ログ`before-bench-fit.log`と`after-bench-fit.log`は上記のartifactsディレクトリに保持し、性能改善の根拠には使用しない。iOSのfps・GPU時間・電力はこの測定から判断しない。

## TestFlightへの送信

評価対象コミットから配布スクリプトを実行し、共通検査、依存解決、署名付きarchive、アップロードが成功した。

| 公開メタデータ | 値 |
| --- | --- |
| version / build | 0.1.0 / `202609171623` |
| 構成 | Release、最低iOS 26.0、SDK 26.5 |
| 本体 / 共有拡張 | `nibble.9uiLe.com` / `nibble.9uiLe.com.share` |
| manifest | `artifacts/testflight/202609171623/manifest.json` |
| 完了状態 | `destination=upload`、`stage=upload`、`completed=true` |
| 暗号化申告 | `uses_non_exempt_encryption=false` |

確認したのはスクリプトが返す工程の成否と公開manifestである。認証設定、秘密鍵、Keychain、保護された生ログは直接参照していない。Apple側の処理、「本人用」への配信、端末でのインストールと動作は、このビルドでは未確認。配布構成と各工程の責務は[TestFlight手順](testflight.md)に定義する。

## 成功判定に使用しない実行

| run ID | 観測と扱い |
| --- | --- |
| `20260917T161424Z-rive-about-a38952` | アプリ切替途中にSettingsとNibbleが混在するAXツリーを読み、復帰判定で失敗。対象bundleと説明文を待つdriverの条件を用いた成功runと分けて保持 |
| `20260917T160745Z-test-6ccc45` | 製品テスト61件は成功したが、driver変更前の入力。本書の対象ソース照合には`20260917T162046Z-test-d286ec`を使用 |

失敗runの記録は成功runで上書きしない。対象は各manifestの入力ハッシュで識別する。

## 未評価の条件

- iOS 26.0での実行、実機の描画時間・電力・応答、App Storeの配信サイズ。
- 画面外でのGPU停止の直接計測。停止条件の実装照合とGPUの観測は別の確認である。
- VoiceOverの音声・ローター操作、利用者調査による理解度とループの注意への影響。
- 読込失敗・キャンセル時の画面操作による回復確認。テストによる欠損リソース検出と分ける。
- 録画全編の連続レビュー、公開添付の閲覧確認、TestFlightビルド`202609171623`の実機確認。

CLIの成功、画像一致、Simulatorの操作成功だけで、これらを確認済みとはしない。

## 再実行

[セットアップ](../README.md#セットアップ)後、専用のiOS 26.5 Simulatorを指定する。以下のUDIDは本記録の端末であり、別環境ではその環境の専用端末へ置き換える。UI driverの実行前に、SimulatorのSettingsで「アクセシビリティ→動作」を開く。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A
nix develop --command python3 scripts/check-about-ui.py \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A
nix develop --command python3 scripts/check-about-ui.py \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A --reduce-motion enabled
```

UI driverはReduce Motion・外観・文字サイズ・コントラストの実値を保存し、変更後の値を確認し、終了時に復元する。成功後は対象コミットとの照合、原本と録画の観察、レビュー申告と必要な添付を[証跡の手順](review-evidence.md)に従って行う。
