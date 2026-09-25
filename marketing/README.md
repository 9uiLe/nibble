# nibble のアプリ用Webサイト

Firebase Hostingで`https://nibble-10d8b.web.app`へ配信する静的サイト。`public/` が配信ルートで、ビルドや外部JavaScriptは不要。

| パス | 用途 |
| --- | --- |
| `/` | アプリの概要 |
| `/support.html` | 使い方、削除と復元、キーボードの案内 |
| `/privacy.html` | プライバシーポリシー |
| `/contact.html` | 問い合わせ先と連絡時の注意 |

`/support`、`/privacy`、`/contact` は対応する `.html` へリダイレクトする。App Store ConnectのSupport URLには`/support.html`、Privacy Policy URLには`/privacy.html`を指定する。

## アプリ提出時に確認すること

Firebaseプロジェクトは`nibble-10d8b`、問い合わせ先は[Googleフォーム](https://forms.gle/yTHhEVNZxB8KD6M9A)を使う。アプリ提出時には次を確認する。

1. フォームに返信先メールアドレスと内容の入力欄があり、想定する利用者が送信でき、担当者が受信できることを確認する。
2. App Store ConnectのSupport URLに`https://nibble-10d8b.web.app/support.html`、Privacy Policy URLに`https://nibble-10d8b.web.app/privacy.html`を登録する。アプリ内からもプライバシーポリシーへ到達できることを確認する。
3. 最終archive、第三者SDKのデータフロー、App Privacy回答とポリシー本文の整合を確認する。

## ローカル確認とデプロイ

リポジトリルートの`nix develop`に含まれるFirebase CLIを、このディレクトリで使用する。デプロイは公開操作なので、公開先と問い合わせ先を確認してから行う。

```sh
cd marketing
firebase emulators:start --only hosting --project nibble-10d8b
firebase deploy --only hosting --project nibble-10d8b
```

Firebase CLIの設定は`firebase.json`にある。Firebaseプロジェクトへのログインと作成は管理者が行う。

`nix flake check --no-update-lock-file --print-build-logs`はHTMLの内部リンクとHostingの転送先を検査する。公開サイトの応答とフォームの送受信は別に確認する。
