# Tasking・ScopedAnimationの検証結果

実施日：2026-09-14。対象はswift-tasking 0.3.0とswift-scoped-animation 0.2.1を使う製品ソース`9686f3afea431bdb570adce9b538340bfd9caca6`と、表に示すSwift規約Lintである。タスクの所有・寿命・重複方針、アニメーションの適用範囲を評価した。

この文書は対象ソースの数値・画像・動画を保存する観測記録である。実装する契約は[実装規約](library-policy.md)、モデルの操作を直接awaitしUI所有者が開始する構成の評価は[`16868e6`の検証記録](async-policy-validation.md)を参照する。製品全体の観測と未検証条件は[MVPの検証結果](mvp-validation.md)で管理する。

## 対象と結果

実施日は2026-09-14。環境はXcode 26.5、Swift 6.3.2、iOS 26.5（23F77）Simulator。実機検証と署名配布はMVPの受け入れ範囲に含めない。

| 条件 | 値 |
| --- | --- |
| 製品・UI検証のソース | `9686f3afea431bdb570adce9b538340bfd9caca6` |
| iPhone 17 Pro | UDID `114E57E6-E37D-4F50-907A-8B0B6B03C92E`。基本操作、共有、通知、再起動 |
| iPhone SE第3世代 | UDID `A1E0BB4A-A327-47C0-B9FB-42863D2A51D8`。製品・研究用のReleaseテスト |
| 共通検査 | ローカルMacとUbuntu 24.04。`flake.lock`とNixの共通コマンドを使用 |
| 証跡 | [PR #7](https://github.com/9uiLe/nibble/pull/7)に画像4点・動画5点。生ログはGit管理対象外の`artifacts/` |

以下のrun IDは`artifacts/ios/`配下の検証単位を指す。manifestは実行成否、assertions、対象コミット、未コミット状態、対象ファイルのSHA-256を記録する。検証時の未コミット変更は文書であり、製品・検証スクリプトのSHA-256をコミット済みソースと照合した。

| 確認 | 結果 | 証跡・再現方法 |
| --- | --- | --- |
| 共通検査 | 4 check成功、Python 25テスト中12件が規約の回帰テスト。17 Swiftファイルに違反なし | `nix flake check --no-update-lock-file --print-build-logs`、`artifacts/library-policy/nix-verified.log`。[Ubuntu CI](https://github.com/9uiLe/nibble/actions/runs/34820368446)は`c898c40`で成功 |
| 製品Releaseテスト | SEで19件成功、失敗・skipなし | `scripts/ios.py test --project-config app/project.json --configuration Release --device <SEのUDID>`、`20260914T074447Z-test-716832` |
| 所有する操作 | 背景化で一時操作を止める間のscene読込、二重open、キャンセル後のopen、同じ項目の重複抑止と別項目の操作、30回連続入力直後の保存・閉じるを検査 | `OwnedActionTests`の6件。最新本文、下書き再開、保存後に下書きが復活しないことを照合 |
| 研究用Releaseテスト | 14テスト、パラメータ展開後16実行が成功。失敗・skipなし | `scripts/ios.py test --project-config validation/research-project.json --configuration Release --device <SEのUDID>`、`20260914T070723Z-test-d695ae`。async letによる検索世代テストを含む |
| 本体・共有拡張Debug | ビルドと17 Proでの実行成功 | `scripts/ios.py run --project-config app/project.json --configuration Debug --device <17 ProのUDID>`、`20260914T074415Z-run-51aa18` |
| generic iOS archive | 成功。両bundleに含めたライセンス通知が原本と一致 | `artifacts/library-policy/archive-owned.log`、`Nibble-owned.xcarchive`。署名を省略したSDKビルドであり、配布可否は判定しない |

規約テストは、生のTask・型alias・関数参照・直接scheduler・アニメーションAPIの拒否と、ライブラリの入口・構造化された処理の許可を検査する。コメント、raw/複数行文字列、regex、実行される補間、修飾名、改行、抑制コメント、診断位置、不正な入力、再帰探索、symlink、対象0件を含む。Swiftの型解決やmacro展開は検査範囲外である。

## 操作と表示

17 Pro、標準文字サイズ、ライト外観、ダミーの日本語・結合文字・絵文字・空白を使用した。操作はNixのsim-use、撮影はAppleのsimctlで行った。

| 導線 | 確認内容 | run ID・録画 |
| --- | --- | --- |
| 本体の基本操作、Release | 作成・コピー・日本語検索・編集を閉じる・ピン留め・削除・復元・下書き破棄。コピーのUTF-8と復元したUUIDが一致 | `20260914T074827Z-mvp-ui-9d04f2`、[録画](https://github.com/user-attachments/assets/dd68871b-b6ca-4d79-8a10-5cdcb5da282d) |
| 再起動、Release | 保存済みUUIDが表示されるcold startを2回録画 | `20260914T074958Z-owned-cold-start-bc44e1`、[録画](https://github.com/user-attachments/assets/5450c00d-b106-4049-a2de-1e6acd5455f0) |
| Safari共有→拡張→保存→本体コピー、Debug | 共有providerから本文を取り込み、保存後にhostへ戻る。App Groupを通じて本体に反映し、コピーのUTF-8が一致 | `20260914T074729Z-tasking-share-bdbc0f`、[録画](https://github.com/user-attachments/assets/560a95f1-059f-482e-90eb-fccb849cacab) |
| Reduce Motion無効、Debug | 5回のcold startで保存済みUUIDを読込。2回のコピーで通知を表示し、最後の操作後に消去。編集を開いて閉じられる | `20260914T074623Z-scoped-notice-disabled-aa3ca1`、[録画](https://github.com/user-attachments/assets/cb625302-79d6-4c24-a266-affc459c4d01) |
| Reduce Motion有効、Debug | 5回のcold startで保存済みUUIDを読込。通知の表示・自動消去、編集開閉が成功。設定のselected状態を確認して実行 | `20260914T074447Z-scoped-notice-enabled-f1664b`、[録画](https://github.com/user-attachments/assets/860a0344-82ba-4835-a75d-ded4358711f4) |

基本操作driverは実行ごとに一意な日本語タイトルを作成・検索し、その行でコピーと復元を照合する。共有はSafariのダミーフォームからテキストを共有し、保存後のhost復帰と本体でのコピーを照合する。フォームの起動方法と基本操作コマンドは[MVP手順](mvp.md)に記載する。

Reduce MotionはSettingsの「アクセシビリティ → 動作 → 視差効果を減らす」で変更し、selected状態を読み取る。sim-useのUISwitch操作には`--duration 0.05`を指定する。各設定でプロセス再起動と一覧読込を5回確認し、コピー2回→通知の読取→最後の操作から2.3秒待機して消去を読取→編集を開閉する。検証後の設定は無効に戻した。

| 一覧 | 編集 | コピー通知 | 共有拡張 |
| --- | --- | --- | --- |
| [画像](https://github.com/user-attachments/assets/480a63bf-e6d9-4a71-b1f3-67f4323c2cda) | [画像](https://github.com/user-attachments/assets/b5bbccf2-dfcb-417a-ad43-903ab8885ee4) | [画像](https://github.com/user-attachments/assets/b1d87755-0c4f-4189-8eac-f2b9c7b0c731) | [画像](https://github.com/user-attachments/assets/df553a8f-538d-42b8-83a6-d7586b48b652) |

画像と録画から抽出したフレームで、一覧の通知、編集の本文・保存・閉じる操作、共有画面を確認した。PR上では画像の読込と、動画5点のreadyState 4・エラーなしを確認した。動画全編の人間によるリアルタイム再生は未実施。録画にはdriverの待機・画面読取が含まれるため、長さをアプリの応答時間へ換算しない。

## アニメーションとタスクの診断

OSのシート開閉に伴うtransactionは画面外側のbarrierで除き、内部のscope・detector・入力barrierを評価した。Debug実行開始（2026-09-14 16:44:15 JST）以降、本体・拡張の`ScopedAnimation`カテゴリと`Unhandled ViewTaskStore`をAppleのlog showで検索した結果は0件だった。ログは`artifacts/library-policy/boundary-diagnostics-final.log`。

これは記載した導線と診断位置に届いたtransactionの確認であり、全表示変化や全タスクの静的保証ではない。通知の指定時間は通常0.16秒、Reduce Motion有効時0秒。実際のUI応答・フレーム時間の定量比較は行っていない。

## 検索測定と適用限界

SQLite actorの検索測定は[MVPの検索測定](mvp-validation.md#検索の測定)に条件・ソース・全測定値を記載する。SE Simulator、iOS 26.5、Release、同じテスト・本文・件数・先頭100件取得、各条件30回の比較である。10,000件の該当なし検索の中央値 / 最大は、`a498ba4`で4.5901 / 6.3731 ms、`8473b36`で4.7760 / 7.4709 msだった。保存層と検索SQLは`8473b36`と`9686f3a`で同じである。

測定区間はSQLite actorへの検索要求から返却までで、Taskingの操作開始、IME、View更新、描画を含まない。実行時のホスト負荷も含む変動をライブラリによる改善・悪化と断定しない。実機hitch、VoiceOverの読み上げ、各表示設定の全組み合わせは未実施。製品全体の適用限界は[MVPの制約](mvp-validation.md#検証範囲の制約)を参照する。

## archiveの再現

以下はリポジトリルートから実行する。本体と共有拡張を含むgeneric iOS archiveを署名なしで構築する。

```sh
xcodebuild -project app/Nibble.xcodeproj -scheme Nibble \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath artifacts/library-policy/DeviceDerivedData \
  -archivePath artifacts/library-policy/Nibble-owned.xcarchive \
  -clonedSourcePackagesDirPath artifacts/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO archive
```
