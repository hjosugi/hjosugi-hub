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

    @impl true
    def fetch(%{id: "not-modified"}, _timeout_ms, validators),
      do: {:not_modified, 304, validators}

    def fetch(%{id: "fresh-with-state"} = feed, _timeout_ms, _validators) do
      item = %Item{
        id: "state-1",
        source_id: feed.id,
        source_name: feed.name,
        source_kind: "rss",
        title: "Fresh state item",
        url: "https://example.com/state",
        summary: "Fresh state summary",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 12:30:00Z],
        tags: []
      }

      {:ok, [item], 200, %{etag: ~s("new")}}
    end

    def fetch(feed, timeout_ms, _validators), do: fetch(feed, timeout_ms)
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

  test "keeps existing items and records state for not-modified feeds" do
    feeds = [
      %{id: "not-modified", name: "Not Modified Feed", url: "https://example.com/cached.xml"},
      %{id: "fresh-with-state", name: "Fresh State Feed", url: "https://example.com/state.xml"}
    ]

    existing = [
      %Item{
        id: "cached-1",
        source_id: "not-modified",
        source_name: "Not Modified Feed",
        source_kind: "rss",
        title: "Cached item",
        url: "https://example.com/cached",
        summary: "Cached summary",
        published_at: ~U[2026-06-19 12:00:00Z],
        collected_at: ~U[2026-06-19 12:30:00Z],
        tags: []
      }
    ]

    result =
      Collector.collect(feeds,
        existing: existing,
        feed_state: %{"not-modified" => %{etag: ~s("old")}},
        fetcher: StubFetcher,
        timeout_ms: 1,
        workers: 2,
        max_items: 10
      )

    assert Enum.map(result.items, & &1.id) |> Enum.sort() == ["cached-1", "state-1"]
    assert result.report.fresh_items == 1
    assert result.report.not_modified_sources == 1
    assert result.report.failed_sources == 0

    cached_status = Enum.find(result.report.sources, &(&1.source_id == "not-modified"))
    assert cached_status.response_code == 304
    assert cached_status.not_modified == true
    assert cached_status.last_error == nil

    assert result.feed_state["not-modified"] == %{etag: ~s("old")}
    assert result.feed_state["fresh-with-state"] == %{etag: ~s("new")}
  end

  test "retries transient failures inside the feed worker" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    fetcher = fn feed, _timeout_ms, _metadata ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

      if attempt == 1 do
        {:error, "temporary unavailable", 503}
      else
        {:ok, [item(feed, "retry-1")], 200, %{etag: ~s("retry-ok")}}
      end
    end

    result =
      Collector.collect(
        [%{id: "retry", name: "Retry Feed", url: "https://example.com/retry.xml"}],
        fetcher: fetcher,
        timeout_ms: 1,
        workers: 1,
        max_retries: 2,
        retry_backoff_ms: 0
      )

    assert [%Item{id: "retry-1"}] = result.items
    assert Agent.get(attempts, & &1) == 2
    assert [%{retries: 1, last_error: nil}] = result.report.sources
    assert result.feed_state["retry"] == %{etag: ~s("retry-ok")}
  end

  test "does not retry permanent client errors" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    fetcher = fn _feed, _timeout_ms, _metadata ->
      Agent.update(attempts, &(&1 + 1))
      {:error, "not found", 404}
    end

    result =
      Collector.collect([%{id: "gone", name: "Gone Feed", url: "https://example.com/gone.xml"}],
        fetcher: fetcher,
        timeout_ms: 1,
        workers: 1,
        max_retries: 2,
        retry_backoff_ms: 0
      )

    assert result.items == []
    assert Agent.get(attempts, & &1) == 1
    assert [%{retries: 0, last_error: "not found", response_code: 404}] = result.report.sources
  end

  defp item(feed, id) do
    %Item{
      id: id,
      source_id: feed.id,
      source_name: feed.name,
      source_kind: "rss",
      title: "Retried item",
      url: "https://example.com/retried",
      summary: "Retried summary",
      published_at: ~U[2026-06-20 12:00:00Z],
      collected_at: ~U[2026-06-20 12:30:00Z],
      tags: []
    }
  end
end
