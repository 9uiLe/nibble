# KeyboardValueConversion

キーボード内の値へ、通常のかな漢字変換候補だけを返す境界。公開productは一つで、`@MainActor JapaneseValueConverter`を利用する。host proxy、周囲の本文、UITextInput、画面、入力履歴を所有しない。

`candidates(reading:)`は直接入力されたかなを変換し、`CandidateResult.candidates([String])`、`.inputTooLong(InputLimits)`、`.noCandidates`を返す。初期化は辞書を読み込まず、最初の有効な非空入力で辞書を作る。`reset()`は未確定変換のcacheを停止し、`release()`は所有する変換器と辞書への参照を手放す。OSがprocessのRSSを直ちに減らす保証ではない。

変換要求の上限は64 graphemeかつUTF-8 256 bytes。UTF-8を先に最大257 bytesだけ調べ、大きい結合文字列を文字数走査へ渡さない。超過は変換だけを拒否する。呼出元は原文値を保持し、入力・削除・原文のまま確定を継続できるようにし、上限と理由を表示する。値そのものの長さ制限・切詰め・trim・正規化を加えない。候補の選択や値の原文確定は呼出元の責務。

同期MainActor APIであり、上限内の変換にも実行時間がある。UI応答の性能は製品導線で別に確認する。このpackageのテストはSwiftPMのiOS schemeで実行し、候補結果・上限・解放後再利用を検証する。

依存はAzooKeyKanaKanjiConverter exact 0.11.2、traits=[]。通常辞書、Zenzai off、learning nothing、予測false、TextReplacer empty、特殊provider空、preload falseを明示する。依存のWithDefaultDictionary productによりemojiとEfficientNGram tokenizer資源も同梱されるが、候補生成でemoji置換・neural model・外部通信を利用しない。宣言上のllama binary downloadと最終link/resourceは区別する。直接依存と6つの解決済みpinはPackage.resolvedに保存し、同梱告知は共有ThirdPartyNotices.txtへ含める。
