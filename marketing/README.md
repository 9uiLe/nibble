# nibble のアプリ用Webサイト

Firebase Hostingで配信する静的サイト。`public/` が配信ルートで、ビルドや外部JavaScriptは不要。

| パス | 用途 |
| --- | --- |
| `/` | アプリの概要 |
| `/support.html` | 使い方、削除と復元、キーボードの案内 |
| `/privacy.html` | プライバシーポリシー |
| `/contact.html` | 問い合わせ先と連絡時の注意 |

`/support`、`/privacy`、`/contact` は対応する `.html` へリダイレクトする。App Store ConnectのSupport URLには`/support.html`、Privacy Policy URLには`/privacy.html`を指定する。

## 公開前に決めること

現時点では公開用の問い合わせ先とFirebaseプロジェクトIDが未決定。次を設定してから公開・審査提出する。

1. `public/contact.html`の「準備中」を、実際に連絡できるメールアドレスまたは問い合わせフォームへのリンクへ置き換える。フォームを使う場合は、その提供元と問い合わせデータの扱いを`public/privacy.html`にも記す。
2. Firebaseプロジェクトを決める。プロジェクトIDはリポジトリに仮値を書かず、デプロイ時の`--project`で指定する。
3. 公開URLが決まったら、App Store ConnectのSupport URLとPrivacy Policy URLを登録する。アプリ内からプライバシーポリシーへ到達できる導線も追加・確認する。
4. 提出するアプリの最終archive、第三者SDKのデータフロー、App Privacy回答とポリシー本文の整合を確認する。Webページの作成だけではこの確認は完了しない。

## ローカル確認とデプロイ

リポジトリルートの`nix develop`に含まれるFirebase CLIを、このディレクトリで使用する。デプロイは公開操作なので、公開先と問い合わせ先を確認してから行う。

```sh
cd marketing
firebase emulators:start --only hosting --project PROJECT_ID
firebase deploy --only hosting --project PROJECT_ID
```

Firebase CLIの設定は`firebase.json`にある。Firebaseプロジェクトへのログインと作成は管理者が行う。
