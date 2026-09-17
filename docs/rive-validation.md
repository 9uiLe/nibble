# Rive表示基盤の検証

対象はRivePresentation、AboutIllustration、AboutStoryアセット。採用契約は[演出設計](decisions/0004-rive-presentation.md)、制作と再生成は[アセット手順](../app/Animations/README.md)に定義する。

## 環境と対象

2026-09-17、Apple Silicon Mac、macOS 26.2、Xcode 26.5（17F42）、Swift 6.3.2、Rive CLI 1.0.4、rive-ios 6.27.0。CLIはNix、Swift Packageはexact指定と共有lockで固定する。

実行端末はiPhone SE第3世代のSimulator、iOS 26.5（23F77）、375×667 pt、画像750×1334 px、UDID `AED98CBE-D67C-44EB-8B9D-F94719466B1A`。最低対応iOS 26.0と実行評価26.5を区別する。

生成物は4,884 bytes、SHA-256 `0fc5cf5e179c69db4e8a90818d6270eda4d1445f54762142c2079d5bd447fabf`。各runの入力と最終コミットは証跡検査で照合する。Markdownの追記はiOSの検証入力に含めない。

## 制作と構造

- verify、inspect、unsigned生成にエラー・警告なし。
- About / Presentation / AboutStory.Defaultと7つのData Bindingプロパティを確認。
- 開始、持ち上げ、移動、ペースト、収束、Reduce Motionを800×416で出力。開始・移動・収束・静止の原本を開いて確認した。元のカードが残り、複製が前面を移り、入力先の行と確認記号が現れる。
- 通常再生後はactive=false。motionAllowed=falseで初期化した場合も完成図になる。画像抽出とデータの読み戻しは連続再生の確認と区別する。

記録は `artifacts/rive/` のverify.json、inspect.json、build.json、時刻別PNGとdata-dump。RMLと配布用ファイルの更新漏れ、型・参照・初期値の不整合、旧inputs・スクリプト混入をPython回帰テストで検査する。宣言済みアセットのハッシュ照合は生成工程の代替ではない。実バイナリの契約はiOSのテストでも検査する。

## iOSの実行

| run | 内容 | 結果 |
| --- | --- | --- |
| `20260917T141448Z-test-55ddb0` | Release製品テスト | 61件成功、失敗0。実際の.rivの契約、File共有と独立した可変状態、完了・再視聴・Reduce Motion、ロード失敗を含む |
| `20260917T141124Z-rive-about-aed5e7` | 通常再生・一時停止・配色・復帰・閲覧 | 成功。再生操作のAX高さ44 pt、5秒のバックグラウンド滞在後に続きから再生、ライト・ダーク・最大文字で末尾と設定への戻りを確認 |

| `20260917T141552Z-rive-about-reduced-b1efcf` | Reduce Motion・静止図・閲覧 | 成功。設定false→true→falseを読み戻し、再生ボタンなし、ライト・ダーク・最大文字で末尾へ到達 |

通常runの原本PNGと録画の4.575 / 46.510 / 82.773秒の抽出フレームを確認した。録画は92.082秒。全編再生とは申告しない。一時停止中のライト→ダーク→コントラスト強調→ライトで、図の配色が反映され、カードの位置と形は保たれた。説明文と図が重ならず、最大文字でも末尾の段落まで到達した。

Reduce Motionの原本PNGと録画の3.405 / 30.090 / 54.335秒の抽出フレームを確認した。原本60.183秒。完成図から表示し、説明文は通常時と同じ内容を読める。

共通のNix検査は7項目を実施する。生成契約の5件と旧API検出を含むPython回帰99件、共通UI設計35件、Swift規約、文書、workflow、Nix整形を含む。

実行手順は、専用Simulatorの設定を「アクセシビリティ→動作」に開いてから以下を実行する。driverはReduce Motionの実際の値を読み、指定値へ変更し、終了時に元へ戻す。外観・文字サイズ・コントラストも保存・復元する。

```sh
nix develop --command python3 scripts/ios.py test \
  --project-config app/project.json --configuration Release \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A
nix develop --command python3 scripts/check-about-ui.py \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A
nix develop --command python3 scripts/check-about-ui.py \
  --device AED98CBE-D67C-44EB-8B9D-F94719466B1A --reduce-motion enabled
```

## 見つかった問題と回帰確認

- テストhostでは起動したが、通常起動でRiveRuntimeを解決できなかった。アプリのDebug / Releaseへ `@executable_path/Frameworks` のrunpathを設定し、通常のinstall・launchを含むUI runで確認した。失敗run `20260917T134530Z-rive-about-852d43` と `20260917T134730Z-rive-about-d49595` は保存した。
- `20260917T140536Z-rive-lifecycle-aacdd7` で、手動停止中のData Bindingによる配色更新が描画されないことを確認した。表示用Viewだけを時間差0で再描画する契約を設け、通常runに停止中の外観切替を追加した。Fileと再生状態は保持する。
- Reduce Motionの初期driverでは、Settingsの行中央を押してもswitchが変化しなかった。AXで取得したswitchの位置と変更後の値を検査するdriverへ修正した。設定未反映のrunは検証成功として扱わない。

## 性能と限界

CLIのheadlessベンチマークは400×208、300 frames、advance平均0.001 ms、render平均0.142 ms / p95 0.383 ms / 最大0.486 ms。これはiOSのfpsやGPU時間を示さない。

Simulator用Releaseアプリのサイズを、同じXcode・SDK・arm64 + x86_64、テストbundleとdSYMを除いた非圧縮のファイル合計で比較する。比較元はAboutの文章設計を持つ `584142d3`。依存追加による容量増を評価するもので、App Storeの圧縮・端末別ダウンロード量ではない。

| 非圧縮Simulator bundle | 導入前 | 導入後 |
| --- | ---: | ---: |
| 本体（共有拡張を含む） | 7,345,008 bytes | 17,825,550 bytes |
| 同梱RiveRuntime.framework | 0 bytes | 10,144,296 bytes |
| 共有拡張 | 2,082,519 bytes | 2,083,317 bytes |

本体は10,480,542 bytes増加した。拡張の798 bytes増加は共有ライセンス文書で、拡張にRiveRuntimeはリンクしない。アニメーション自体は4,884 bytes。記録は `artifacts/rive/simulator-size.json`。

実機、iOS 26.0での実行、GPUのフレーム時間・電力、VoiceOverの音声・ローター操作、利用者調査による理解の改善は未評価。AXラベル・操作領域とSimulatorの画像だけでこれらの成功を主張しない。スクロールによる画面外停止は実装を照合したが、不可視中のGPU停止を直接計測していない。待機時のプロセス計測はロード・OSキャッシュ・他のUIも含むため、Rive単独のコストとみなさない。
