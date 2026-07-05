defmodule Mix.Tasks.Hub.Collect do
  use Mix.Task

  @shortdoc "Collect RSS/Atom feeds into radar-cache/"

  alias HjosugiHub.{CLI, Collector, Config, Store}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts =
      CLI.parse_options!(args,
        feeds: :string,
        cache: :string,
        data: :string,
        json: :string,
        report: :string,
        timeout: :integer,
        workers: :integer,
        max_items: :integer
      )

    feeds_path = Keyword.get(opts, :feeds, "config/feeds.exs")
    cache_path = CLI.cache_path(opts, "radar-cache/items.term")
    json_path = Keyword.get(opts, :json, "radar-cache/items.json")
    report_path = Keyword.get(opts, :report, "radar-cache/collection-report.json")
    timeout_ms = Keyword.get(opts, :timeout, CLI.env_int("REQUEST_TIMEOUT_MS", 15_000))
    workers = Keyword.get(opts, :workers, CLI.env_int("FEED_WORKERS", 6))
    max_items = Keyword.get(opts, :max_items, CLI.env_int("MAX_ITEMS", 1000))

    feeds = Config.feeds(feeds_path)
    existing = Store.read_items(cache_path)

    result =
      Collector.collect(feeds,
        existing: existing,
        timeout_ms: timeout_ms,
        workers: workers,
        max_items: max_items
      )

    Store.write_items(cache_path, result.items)
    Store.write_json(json_path, Store.public_items(result.items))
    Store.write_json(report_path, result.report)

    Mix.shell().info(
      "collected feeds: fresh=#{result.report.fresh_items} failed=#{result.report.failed_sources} total=#{result.report.total_items}"
    )
  end
end
