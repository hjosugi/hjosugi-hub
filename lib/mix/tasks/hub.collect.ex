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
        max_items: :integer,
        only: :string,
        dry_run: :boolean
      )

    feeds_path = Keyword.get(opts, :feeds, "config/feeds.exs")
    cache_path = CLI.cache_path(opts, "radar-cache/items.term")
    feed_state_path = Store.feed_state_path(cache_path)
    json_path = Keyword.get(opts, :json, "radar-cache/items.json")
    report_path = Keyword.get(opts, :report, "radar-cache/collection-report.json")
    timeout_ms = Keyword.get(opts, :timeout, CLI.env_int("REQUEST_TIMEOUT_MS", 15_000))
    workers = Keyword.get(opts, :workers, CLI.env_int("FEED_WORKERS", 6))
    max_items = Keyword.get(opts, :max_items, CLI.env_int("MAX_ITEMS", 1000))
    dry_run? = Keyword.get(opts, :dry_run, false)

    feeds = feeds_path |> Config.feeds() |> filter_feeds(Keyword.get(opts, :only))
    existing = Store.read_items(cache_path)
    feed_state = Store.read_feed_state(feed_state_path)

    result =
      Collector.collect(feeds,
        existing: existing,
        feed_state: feed_state,
        timeout_ms: timeout_ms,
        workers: workers,
        max_items: max_items
      )

    if dry_run? do
      print_dry_run(result)
    else
      Store.write_items(cache_path, result.items)
      Store.write_feed_state(feed_state_path, result.feed_state)
      Store.write_json(json_path, Store.public_items(result.items))
      Store.write_json(report_path, result.report)
      print_summary(result)
    end
  end

  defp filter_feeds(feeds, nil), do: feeds
  defp filter_feeds(feeds, ""), do: feeds

  defp filter_feeds(feeds, only) do
    ids =
      only
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    known_ids = MapSet.new(feeds, & &1.id)
    unknown_ids = ids |> MapSet.difference(known_ids) |> MapSet.to_list() |> Enum.sort()

    if unknown_ids != [] do
      Mix.raise("--only references unknown feed id(s): #{Enum.join(unknown_ids, ", ")}")
    end

    Enum.filter(feeds, &MapSet.member?(ids, &1.id))
  end

  defp print_summary(result) do
    Mix.shell().info(
      "collected feeds: fresh=#{result.report.fresh_items} failed=#{result.report.failed_sources} total=#{result.report.total_items}"
    )
  end

  defp print_dry_run(result) do
    Mix.shell().info("dry-run: not writing cache, JSON, or report files")
    print_summary(result)

    Enum.each(result.report.sources, fn source ->
      status =
        cond do
          source.not_modified ->
            "not-modified"

          source.last_error ->
            "error=#{source.last_error}"

          true ->
            "items=#{source.items_seen}"
        end

      Mix.shell().info("source #{source.source_id}: code=#{source.response_code} #{status}")
    end)

    result.fresh_items
    |> Enum.take(5)
    |> Enum.each(fn item ->
      Mix.shell().info("sample #{item.source_id}: #{item.title} <#{item.url}>")
    end)
  end
end
