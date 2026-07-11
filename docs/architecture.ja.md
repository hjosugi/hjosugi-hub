<!-- i18n: language-switcher -->
[English](architecture.md) | [日本語](architecture.ja.md)

# Hjosugi Hub アーキテクチャ

Hjosugi Hubは静的サイトパイプラインです。Elixirはローカル開発時に実行され、GitHub Actionsはビルドを行います。展開されたサイトは`public/`以下のプレーンファイルです。

## データフロー

```text
config/feeds.exs
  -> HjosugiHub.Fetcher
  -> HjosugiHub.FeedParser
  -> HjosugiHub.Collector
  -> HjosugiHub.Store.merge_items
  -> radar-cache/items.term
  -> HjosugiHub.Renderer
  -> public/
```

`mix hub.collect`はネットワーク収集フェーズを担当します。フィード定義を読み込み、有効なソースを並行して取得し、RSS/Atom/YouTube RSSを`HjosugiHub.Item`構造体にパースし、新しいアイテムと以前のキャッシュをマージし、`radar-cache/items.term`に書き込みます。

`mix hub.export`は静的エクスポートフェーズを担当します。`config/site.exs`、`config/feeds.exs`、およびローカルキャッシュを読み込み、ポートフォリオ、レーダーページ、JSONペイロード、`health.json`、`robots.txt`、静的アセットを`public/`にレンダリングします。

## モジュールの責務

`HjosugiHub.Config`は、サイトとフィードの設定を読み込み、検証します。

`HjosugiHub.Fetcher`は条件付きフィードメタデータを用いたHTTPリクエストを行います。
`HjosugiHub.Fetcher.Behaviour`はテストや代替フェッチャーを明示的に管理します。

`HjosugiHub.FeedParser`はフィードXMLを正規化し、アイテム構造体に変換し、著者、カテゴリ、リンク、スコア、公開日時などのソースメタデータを抽出します。

`HjosugiHub.Collector`は取得の並行性を調整し、フィードごとの結果をレポートに変換し、条件付きリクエストのためにフィードの状態を保持します。

`HjosugiHub.Store`はキャッシュとJSONの境界線です。レガシーキャッシュエントリを安全に読み込み、アイテムを安定したIDでマージし、ソートして公開用JSONを書き出します。

`HjosugiHub.Renderer`はサイト設定と公開アイテムをHTML、JSON、CSP、アセットバージョン、`health.json`、`robots.txt`、`sitemap.xml`に変換します。

`HjosugiHub.HTML`、`HjosugiHub.JSON`、`HjosugiHub.Util`、`HjosugiHub.Tagger`は、エスケープ、エンコード、テキストクリーンアップ、安定ID、日付、要約、タグ付けの純粋なヘルパーです。

`HjosugiHub.Kofun`と`HjosugiHub.Dochicken`は、静的ページで使用されるインラインピクセルアートSVGを生成します。

`Mix.Tasks.Hub.Collect`と`Mix.Tasks.Hub.Export`は、コレクターとレンダラーのCLIシェルです。`HjosugiHub.CLI`は共有オプションの解析を中央管理します。

## パブリック境界線

`public/`以下に書かれたすべては公開可能で、GitHub Pagesにデプロイされます。
これには`radar-data/items.json`、`radar-data/site.json`、`radar-data/feeds.json`、`health.json`、HTMLからリンクされたスクリーンショット、静的アセットが含まれます。
`config/site.exs`、`config/feeds.exs`、または生成されたキャッシュエントリに秘密情報やプライベートノート、トークン保護されたURLを置かないでください。

生成されたローカル状態はgitに含まれません：

- `radar-cache/items.term`: GitHub Actionsのキャッシュによって復元されるアイテムキャッシュ
- `radar-cache/feed-state.term`: フィードごとの条件付きリクエストメタデータ
- `radar-cache/collection-report.json`: 最新のコレクションレポート
- `public/`: 最終的な静的エクスポートで、GitHub Pagesにアーティファクトとして渡される

## キャッシュのライフサイクル

デプロイワークフローでは、`actions/cache`が`radar-cache/items.term`をロール式の`hjosugi-hub-items-`リストアキーを使って復元します。
`mix hub.collect`は新しいフィードアイテムをその復元キャッシュとマージし、更新されたキャッシュと公開用JSONを書き出します。
キャッシュミスは有効です：エクスポートは現在のコレクション実行で取得可能なものであれば成功します。

静的エクスポートはGitHub Pagesから一切読まれません。
それは、チェックアウトされた設定、復元されたキャッシュ、現在のコレクション結果、テンプレート、リポジトリ内のアセットに基づいて決定的です。