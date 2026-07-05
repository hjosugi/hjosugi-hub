defmodule HjosugiHub.CollectorTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.{Collector, Item}

  defmodule StubFetcher do
    @behaviour HjosugiHub.Fetcher.Behaviour

    @impl true
    def fetch(%{id: "ok"} = feed, _timeout_ms) do
      item = %Item{
        id: "ok-1",
        source_id: feed.id,
        source_name: feed.name,
        source_kind: "rss",
        title: "Fresh item",
        url: "https://example.com/fresh",
        summary: "Fresh summary",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 12:30:00Z],
        tags: []
      }

      {:ok, [item], 200}
    end

    def fetch(%{id: "fail"}, _timeout_ms), do: {:error, "boom", 503}
    def fetch(%{id: "exit"}, _timeout_ms), do: exit(:crashed)
  end

  @tag capture_log: true
  test "injects a fetcher and reports mixed success failure and exits" do
    feeds = [
      %{id: "ok", name: "OK Feed", url: "https://example.com/ok.xml", enabled: true},
      %{id: "fail", name: "Fail Feed", url: "https://example.com/fail.xml", enabled: true},
      %{id: "exit", name: "Exit Feed", url: "https://example.com/exit.xml", enabled: true}
    ]

    result =
      Collector.collect(feeds,
        fetcher: StubFetcher,
        timeout_ms: 1,
        workers: 3,
        max_items: 10
      )

    assert [%Item{id: "ok-1"}] = result.items
    assert result.report.fresh_items == 1
    assert result.report.failed_sources == 2

    assert Enum.find(result.report.sources, &(&1.source_id == "ok")).items_seen == 1
    assert Enum.find(result.report.sources, &(&1.source_id == "fail")).last_error == "boom"
    assert Enum.find(result.report.sources, &(&1.source_id == "exit")).last_error =~ ":crashed"
  end

  test "accepts a two-argument fetcher function" do
    feed = %{id: "fun", name: "Function Feed", url: "https://example.com/fun.xml", enabled: true}

    fetcher = fn fetched_feed, _timeout_ms ->
      item = %Item{
        id: "fun-1",
        source_id: fetched_feed.id,
        source_name: fetched_feed.name,
        source_kind: "rss",
        title: "Function item",
        url: "https://example.com/fun",
        summary: "Function summary",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 12:30:00Z],
        tags: []
      }

      {:ok, [item], 200}
    end

    result =
      Collector.collect([feed], fetcher: fetcher, timeout_ms: 1, workers: 1, max_items: 10)

    assert [%Item{id: "fun-1"}] = result.items
    assert result.report.failed_sources == 0
  end

  test "disabled feeds are not fetched but existing cache entries are retained" do
    feeds = [
      %{
        id: "disabled",
        name: "Disabled Feed",
        url: "https://example.com/feed.xml",
        enabled: false
      }
    ]

    existing = [
      %Item{
        id: "disabled-1",
        source_id: "disabled",
        source_name: "Disabled Feed",
        source_kind: "rss",
        title: "Cached disabled item",
        url: "https://example.com/item",
        summary: "Cached for possible re-enable",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: []
      }
    ]

    result =
      Collector.collect(feeds, existing: existing, timeout_ms: 1, workers: 1, max_items: 10)

    assert [%Item{id: "disabled-1"}] = result.items
    assert result.report.sources == []
    assert result.report.fresh_items == 0
    assert result.report.failed_sources == 0
  end
end
