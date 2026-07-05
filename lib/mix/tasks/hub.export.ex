defmodule Mix.Tasks.Hub.Export do
  use Mix.Task

  @shortdoc "Export the static GitHub Pages site"

  alias HjosugiHub.{CLI, Config, Renderer, Store}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts =
      CLI.parse_options!(args,
        site: :string,
        feeds: :string,
        cache: :string,
        data: :string,
        out: :string,
        report: :string,
        base_url: :string
      )

    site = Config.site(Keyword.get(opts, :site, "config/site.exs"))
    feeds = Config.feeds(Keyword.get(opts, :feeds, "config/feeds.exs"))
    cache_path = CLI.cache_path(opts, "radar-cache/items.term")
    items = Store.read_items(cache_path)
    feed_state = Store.read_feed_state(Store.feed_state_path(cache_path))

    report_path =
      Keyword.get(opts, :report, Path.join(Path.dirname(cache_path), "collection-report.json"))

    collection_report = Store.read_json(report_path)
    out_dir = Keyword.get(opts, :out, "public")
    base_url = Keyword.get(opts, :base_url, System.get_env("PUBLIC_BASE_URL", ""))

    Renderer.export(site, feeds, items, out_dir, base_url,
      collection_report: collection_report,
      feed_state: feed_state
    )

    Mix.shell().info("exported static site: out=#{out_dir} items=#{length(items)}")
  end
end
