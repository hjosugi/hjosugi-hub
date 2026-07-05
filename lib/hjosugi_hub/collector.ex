defmodule HjosugiHub.Collector do
  @moduledoc false

  alias HjosugiHub.{Fetcher, Store}

  def collect(feeds, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 15_000)
    workers = Keyword.get(opts, :workers, 6)
    max_items = Keyword.get(opts, :max_items, 1000)
    existing = Keyword.get(opts, :existing, [])
    feed_state = Keyword.get(opts, :feed_state, %{})
    fetcher = Keyword.get(opts, :fetcher, Fetcher)
    started_at = DateTime.utc_now()
    enabled = Enum.filter(feeds, &Map.get(&1, :enabled, true))

    # Feeds are network-bound, so fetch them in parallel: each runs in its own
    # lightweight process, capped at `workers` at a time. A slow or hung feed is
    # killed on timeout without taking the others down.
    results =
      fetch_all(enabled, timeout_ms, workers, fetcher, feed_state)
      |> then(&Enum.zip(enabled, &1))
      |> Enum.map(fn {feed, result} -> normalize_result(feed, result) end)

    fresh_items =
      results
      |> Enum.flat_map(fn
        {_feed, {:ok, items, _status, _metadata}} -> items
        {_feed, _error} -> []
      end)

    items = Store.merge_items(existing, fresh_items, max_items)
    next_feed_state = merge_feed_state(feed_state, results)

    report = %{
      started_at: started_at,
      finished_at: DateTime.utc_now(),
      sources: Enum.map(results, &source_status/1),
      fresh_items: length(fresh_items),
      total_items: length(items),
      not_modified_sources:
        Enum.count(results, fn {_feed, result} ->
          match?({:not_modified, _status, _metadata}, result)
        end),
      failed_sources:
        Enum.count(results, fn {_feed, result} -> match?({:error, _reason, _status}, result) end)
    }

    %{items: items, fresh_items: fresh_items, feed_state: next_feed_state, report: report}
  end

  defp normalize_result(feed, {:ok, {:ok, items, status}}), do: {feed, {:ok, items, status, %{}}}
  defp normalize_result(feed, {:ok, result}), do: {feed, result}
  defp normalize_result(feed, {:exit, reason}), do: {feed, {:error, inspect(reason), 0}}

  defp fetch_all(enabled, timeout_ms, workers, fetcher, feed_state) do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      enabled
      |> Task.async_stream(&fetch_feed(&1, timeout_ms, fetcher, feed_state),
        max_concurrency: workers,
        timeout: timeout_ms + 10_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  defp fetch_feed(feed, timeout_ms, fetcher, feed_state) when is_function(fetcher, 3) do
    fetcher.(feed, timeout_ms, feed_metadata(feed_state, feed))
  end

  defp fetch_feed(feed, timeout_ms, fetcher, _feed_state) when is_function(fetcher, 2) do
    fetcher.(feed, timeout_ms)
  end

  defp fetch_feed(feed, timeout_ms, fetcher, feed_state) when is_atom(fetcher) do
    if function_exported?(fetcher, :fetch, 3) do
      fetcher.fetch(feed, timeout_ms, feed_metadata(feed_state, feed))
    else
      fetcher.fetch(feed, timeout_ms)
    end
  end

  defp source_status({feed, {:ok, items, status, _metadata}}) do
    %{
      source_id: feed.id,
      source_name: feed.name,
      response_code: status,
      items_seen: length(items),
      not_modified: false,
      last_error: nil
    }
  end

  defp source_status({feed, {:not_modified, status, _metadata}}) do
    %{
      source_id: feed.id,
      source_name: feed.name,
      response_code: status,
      items_seen: 0,
      not_modified: true,
      last_error: nil
    }
  end

  defp source_status({feed, {:error, reason, status}}) do
    %{
      source_id: feed.id,
      source_name: feed.name,
      response_code: status,
      items_seen: 0,
      not_modified: false,
      last_error: reason
    }
  end

  defp merge_feed_state(feed_state, results) do
    Enum.reduce(results, normalize_feed_state(feed_state), fn
      {feed, {:ok, _items, _status, metadata}}, acc ->
        put_feed_metadata(acc, feed, metadata)

      {feed, {:not_modified, _status, metadata}}, acc ->
        put_feed_metadata(acc, feed, metadata)

      {_feed, _result}, acc ->
        acc
    end)
  end

  defp put_feed_metadata(state, feed, metadata) when map_size(metadata) == 0 do
    Map.delete(state, feed.id)
  end

  defp put_feed_metadata(state, feed, metadata) do
    Map.put(state, feed.id, metadata)
  end

  defp feed_metadata(feed_state, feed),
    do: Map.get(normalize_feed_state(feed_state), feed.id, %{})

  defp normalize_feed_state(feed_state) do
    Map.new(feed_state, fn {feed_id, metadata} -> {to_string(feed_id), metadata} end)
  end
end
