defmodule HjosugiSite.Collector do
  @moduledoc false

  alias HjosugiSite.{Fetcher, Store}

  def collect(feeds, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 15_000)
    workers = Keyword.get(opts, :workers, 6)
    max_items = Keyword.get(opts, :max_items, 1000)
    existing = Keyword.get(opts, :existing, [])
    started_at = DateTime.utc_now()
    enabled = Enum.filter(feeds, &Map.get(&1, :enabled, true))

    results =
      enabled
      |> Task.async_stream(&Fetcher.fetch(&1, timeout_ms),
        max_concurrency: workers,
        timeout: timeout_ms + 10_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()
      |> then(&Enum.zip(enabled, &1))
      |> Enum.map(fn {feed, result} -> normalize_result(feed, result) end)

    fresh_items =
      results
      |> Enum.flat_map(fn
        {_feed, {:ok, items, _status}} -> items
        {_feed, _error} -> []
      end)

    items = Store.merge_items(existing, fresh_items, max_items)

    report = %{
      started_at: started_at,
      finished_at: DateTime.utc_now(),
      sources: Enum.map(results, &source_status/1),
      fresh_items: length(fresh_items),
      total_items: length(items),
      failed_sources: Enum.count(results, fn {_feed, result} -> match?({:error, _reason, _status}, result) end)
    }

    %{items: items, report: report}
  end

  defp normalize_result(feed, {:ok, result}), do: {feed, result}
  defp normalize_result(feed, {:exit, reason}), do: {feed, {:error, inspect(reason), 0}}

  defp source_status({feed, {:ok, items, status}}) do
    %{
      source_id: feed.id,
      source_name: feed.name,
      response_code: status,
      items_seen: length(items),
      last_error: nil
    }
  end

  defp source_status({feed, {:error, reason, status}}) do
    %{
      source_id: feed.id,
      source_name: feed.name,
      response_code: status,
      items_seen: 0,
      last_error: reason
    }
  end
end
