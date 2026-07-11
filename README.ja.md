<!-- i18n: language-switcher -->
[English](README.md) | [日本語](README.ja.md)

# Hjosugi Hub

自己紹介ポートフォリオと、技術情報収集・検索ページを1つにしたElixirプロジェクトです。
公開先はGitHub Pagesを想定しており、常時起動サーバーなしで安く運用できます。

この日本語READMEは概要と運用手順に絞っています。詳細な正本は
[README.md](README.md)、同期方針は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## すぐ動かす

```bash
mix test
mix hub.collect
mix hub.export --out public
```

生成後、`public/index.html` が自己紹介ページ、`public/radar/index.html` が情報収集ページです。
情報収集ページはJSONを `fetch()` するため、ローカル確認時は `public/` をHTTPで配信してください。
読み込まれる公開JSONは `public/radar-data/items.json` です。

## 現在できること

- RSS / Atom / YouTube RSSの収集
- 収集アイテムの正規化、タグ付け、重複排除
- GitHub Pages向けの静的HTML/JSON書き出し
- ブラウザ側JavaScriptでの検索、タグ/ソース絞り込み
- GitHub Actionsによる毎朝6時(JST)の収集とデプロイ

## GitHub Pagesで安く公開する

Hjosugi Hub の本番公開先は GitHub Pages です。常時起動サーバー、DB、有料Workerは不要です。
GitHubのリポジトリ名は `hjosugi-hub` にしてください。デフォルトのGitHub Pagesドメインでは
`https://hjosugi.github.io/hjosugi-hub/` に公開されます。

デプロイは [`.github/workflows/pages.yml`](.github/workflows/pages.yml) が行います。

1. `mix test`
2. `mix hub.collect --timeout 20000 --workers 6 --max-items 1000`
3. `mix hub.export --out public --base-url <GitHub Pages URL>`
4. `actions/deploy-pages` で `public/` をGitHub Pagesへ公開

GitHub側の初回設定:

1. `hjosugi/hjosugi-hub` のRepository settingsを開く
2. **Pages** を開く
3. **Build and deployment** -> **Source** を **GitHub Actions** にする
4. `main`へpushするか、Actionsタブから **Deploy Hjosugi Hub** を手動実行する

deploy workflow は毎朝6時(JST)にも実行され、公開radarデータを更新します。
GitHub Actions のscheduleはUTC基準なので、cronは `0 21 * * *` です。
GitHub Pagesが解決したURLを `mix hub.export --base-url` に渡すため、`robots.txt` と
`sitemap.xml` も実際のPages URLに揃います。Secretsは不要です。

`public/` は生成物なのでGitにはcommitしません。GitHub Pagesにはworkflow artifactとして渡します。

注意: GitHub Pagesでは非公開Inboxやサーバー側トークン保護はできません。
`public/radar-data/items.json` に出した情報収集データは公開扱いです。
