defmodule Mix.Tasks.Hub.Collect do
  use Mix.Task

  @shortdoc "Collect RSS/Atom feeds into data/items.term and data/items.json"

  alias HjosugiHub.{Collector, Config, Store}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          feeds: :string,
          data: :string,
          json: :string,
          report: :string,
          timeout: :integer,
          workers: :integer,
          max_items: :integer
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    feeds_path = Keyword.get(opts, :feeds, "config/feeds.exs")
    data_path = Keyword.get(opts, :data, "data/items.term")
    json_path = Keyword.get(opts, :json, "data/items.json")
    report_path = Keyword.get(opts, :report, "data/collection-report.json")
    timeout_ms = Keyword.get(opts, :timeout, env_int("REQUEST_TIMEOUT_MS", 15_000))
    workers = Keyword.get(opts, :workers, env_int("FEED_WORKERS", 6))
    max_items = Keyword.get(opts, :max_items, env_int("MAX_ITEMS", 1000))

    feeds = Config.feeds(feeds_path)
    existing = Store.read_items(data_path)

    result =
      Collector.collect(feeds,
        existing: existing,
        timeout_ms: timeout_ms,
        workers: workers,
        max_items: max_items
      )

    Store.write_items(data_path, result.items)
    Store.write_json(json_path, Store.public_items(result.items))
    Store.write_json(report_path, result.report)

    Mix.shell().info(
      "collected feeds: fresh=#{result.report.fresh_items} failed=#{result.report.failed_sources} total=#{result.report.total_items}"
    )
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  rescue
    _ -> default
  end
end
