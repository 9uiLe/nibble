# Tasking・ScopedAnimationの検証結果

対象は[非同期処理とアニメーションの実装規約](library-policy.md)を適用した本体・共有拡張・Lint。2026-09-14にXcode 26.5、Swift 6.3.2、iOS 26.5（23F77）Simulatorで確認した。実機検証と署名配布は受け入れ範囲に含めない。

## 対象と結果

製品の最終参照コミットは`9686f3afea431bdb570adce9b538340bfd9caca6`。基本操作driverは`0010636`で一意な検索語を使い、既存行との取り違えを防ぐ。以後の検証記録の編集は製品コードを変更しない。iPhone 17 ProのUDIDは`114E57E6-E37D-4F50-907A-8B0B6B03C92E`、iPhone SE第3世代のUDIDは`A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`。

| 確認 | 結果 | 証跡・再現方法 |
| --- | --- | --- |
| 共通検査 | 4 check成功。Python 25テスト中12件がSwift規約の検査。17 Swiftファイルに違反なし | `nix flake check --no-update-lock-file --print-build-logs`、`artifacts/library-policy/nix-verified.log` |
| 製品Releaseテスト | SEで19件成功、失敗・skipなし | `scripts/ios.py test --project-config app/project.json --configuration Release --device <SEのUDID>`、`20260914T074447Z-test-716832` |
| 所有する操作 | 背景化で一時操作を止める間のscene読込、二重open、キャンセル後のopen、同一項目の重複抑止と別項目の操作、30回の連続入力直後の保存・閉じるを検査 | `OwnedActionTests`の6件。最新本文、下書きの再開、保存後に下書きが復活しないことを照合 |
| 研究用Releaseテスト | 14テスト成功。パラメータ展開後の実行件数16、失敗・skipなし | `scripts/ios.py test --project-config validation/research-project.json --configuration Release --device <SEのUDID>`、`20260914T070723Z-test-d695ae`。非構造化Taskをasync letへ変更した検索世代テストを含む |
| 本体・共有拡張Debug | ビルドと17 Proでの実行成功 | `scripts/ios.py run --project-config app/project.json --configuration Debug --device <17 ProのUDID>`、`20260914T074415Z-run-51aa18` |
| generic iOS archive | 成功。本体・共有拡張の両bundleにライセンス通知を含み、原本と一致 | `artifacts/library-policy/archive-owned.log`、`Nibble-owned.xcarchive`。署名を省略したSDKビルドであり配布可否は判定しない |

規約テストは生のTask・型alias・関数参照・直接scheduler・アニメーションAPIを拒否し、ライブラリの入口と構造化された処理を許可する。コメント・raw/複数行文字列・regex・実行される補間、修飾名、改行、抑制コメント、診断位置、壊れた入力、再帰探索、symlinkと対象0件を確認する。Swiftの型解決やmacro展開は検査範囲外である。

## 操作と表示

17 Pro、標準文字サイズ、ライト外観、ダミーの日本語・結合文字・絵文字・空白を使用した。操作はNixのsim-use、撮影はAppleのsimctlで行う。以下のrun IDは`artifacts/ios/`配下のログ・manifest・画像・録画を指す。

| 導線 | 確認内容 | run ID |
| --- | --- | --- |
| 本体の基本操作（Release） | 作成・コピー・日本語検索・編集を閉じる・ピン留め・削除・復元・下書き破棄。コピーのUTF-8と復元したUUIDが一致 | `20260914T074827Z-mvp-ui-9d04f2` |
| 再起動（Release） | 保存済みUUIDが表示されるcold startを2回録画 | `20260914T074958Z-owned-cold-start-bc44e1` |
| Safari共有→拡張→保存→本体コピー（Debug） | 共有providerから本文を取り込み、保存後にhostへ戻る。App Groupを通じて本体に反映され、コピーのUTF-8が一致 | `20260914T074729Z-tasking-share-bdbc0f` |
| 通知と編集（Debug、Reduce Motion無効） | 5回のcold startで保存済みUUIDを読込。2回のコピーで通知を表示し、最後の操作後に消去。編集画面を開いて閉じられる | `20260914T074623Z-scoped-notice-disabled-aa3ca1` |
| 通知と編集（Debug、Reduce Motion有効） | 5回のcold startで保存済みUUIDを読込。通知の表示と自動消去、編集・閉じる操作を完了。設定のselected状態を確認して実行 | `20260914T074447Z-scoped-notice-enabled-f1664b` |

Reduce MotionはSettingsの「アクセシビリティ → 動作 → 視差効果を減らす」で変更し、検証後に元の無効へ戻した。sim-useのUISwitch操作には`--duration 0.05`を指定する。通知の確認はコピー2回、表示の読取、最後の操作から2.3秒待機して消去を読取、編集を開いて閉じる手順で行う。

OSのシート開閉に伴うtransactionは画面外側のbarrierで除き、内部のscope・detector・入力barrierを評価する。最終のDebug実行開始（16:44:15 JST）以降、本体・拡張の`ScopedAnimation`カテゴリと`Unhandled ViewTaskStore`をAppleのlog showで検索した結果は0件だった。ログは`artifacts/library-policy/boundary-diagnostics-final.log`。これは実行した導線と診断位置の範囲での確認であり、全transactionの静的保証ではない。

画像と録画から抽出したフレームを確認し、一覧の通知、編集の本文・保存・閉じる操作、共有画面を視認できることを確認した。動画全編の人間によるリアルタイム再生、VoiceOverの読み上げ、実機のhitch測定は行っていない。録画時間にはdriverの待機・画面読取を含むため、アプリの応答時間に換算しない。画像・動画は本変更のPRへ添付する。

## 検索の比較と性能の範囲

検索の比較対象コードは`8473b36`。最終参照点でも保存層・検索SQLは同じ。比較元は[MVPの検索測定](mvp-validation.md#検索の測定)の`a498ba4`。両方ともSE Simulator、iOS 26.5、Release、同じ検索テスト・本文・保存件数、先頭100件の取得、各条件30回。値は中央値 / 最大（ms）。比較元のraw値は`artifacts/mvp/search-timing-final.json`、本変更は`artifacts/library-policy/search-timing.json`に保存した。

| 件数・検索語 | 比較元 | 本変更 |
| --- | --- | --- |
| 0件・東 | 0.0478 / 5.3921 | 0.0305 / 2.6171 |
| 0件・見つからない語句 | 0.0442 / 0.4370 | 0.0255 / 0.0737 |
| 20件・東 | 0.0382 / 0.0688 | 0.0441 / 0.1097 |
| 20件・見つからない語句 | 0.0249 / 0.0379 | 0.0288 / 0.0440 |
| 1,000件・東 | 0.1169 / 0.1988 | 0.1574 / 0.3064 |
| 1,000件・見つからない語句 | 0.3166 / 0.4478 | 0.3997 / 0.5089 |
| 10,000件・東 | 0.1211 / 0.3527 | 0.1254 / 0.2040 |
| 10,000件・見つからない語句 | 4.5901 / 6.3731 | 4.7760 / 7.4709 |

これはSQLite actorの検索要求から返却までの値で、Taskingの操作開始、IME、View更新、描画を含まない。10,000件の該当なし検索の中央値は4.5901→4.7760 ms、最大は6.3731→7.4709 msだった。検索SQL・データ・処理方式は同じであり、異なる実行時のホスト負荷も含む変動をライブラリによる改善・悪化と断定しない。

通知の指定時間は通常0.16秒、Reduce Motion有効時0秒とする。UI応答・フレーム時間について変更前後の定量比較は行っておらず、動画や検索の値を実機性能の保証に使わない。配布判断時の性能予算・実機計測と、MVP全体で残る検証範囲は[MVPの制約](mvp-validation.md#検証範囲の制約)を参照する。

## archiveの再現

```sh
xcodebuild -project app/Nibble.xcodeproj -scheme Nibble \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath artifacts/library-policy/DeviceDerivedData \
  -archivePath artifacts/library-policy/Nibble-owned.xcarchive \
  -clonedSourcePackagesDirPath artifacts/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO archive
```
