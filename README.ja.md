# Signal Garden

自己紹介ポートフォリオと、技術情報収集・検索ページを1つにしたElixirプロジェクトです。
公開先はGitHub Pagesを想定しており、常時起動サーバーなしで安く運用できます。

## すぐ動かす

```bash
mix test
mix sg.collect
mix sg.export --out public
```

生成後、`public/index.html` が自己紹介ページ、`public/signals/index.html` が情報収集ページです。
情報収集ページはJSONを `fetch()` するため、ローカル確認時は `public/` をHTTPで配信してください。

## 現在できること

- RSS / Atom / YouTube RSSの収集
- 収集アイテムの正規化、タグ付け、重複排除
- GitHub Pages向けの静的HTML/JSON書き出し
- ブラウザ側JavaScriptでの検索、タグ/ソース絞り込み
- GitHub Actionsによる6時間ごとの収集とデプロイ

## GitHub Pagesで安く公開する

GitHub Pagesのソースを「GitHub Actions」にして、`main`へpushしてください。
`.github/workflows/pages.yml` が収集、静的書き出し、Pagesデプロイまで行います。

注意: GitHub Pagesでは非公開Inboxやサーバー側トークン保護はできません。
`public/data/items.json` に出した情報収集データは公開扱いです。
