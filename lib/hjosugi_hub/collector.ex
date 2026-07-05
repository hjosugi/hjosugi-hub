defmodule HjosugiHub.Collector do
  @moduledoc """
  Collection pipeline for enabled feeds.

  It fetches feeds concurrently with retries and conditional validators, merges
  new items into the cache, updates feed health state, and returns a report for
  export/status checks.
  """

  alias HjosugiHub.{Fetcher, Store}

  def collect(feeds, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 15_000)
    workers = Keyword.get(opts, :workers, 6)
    max_items = Keyword.get(opts, :max_items, 1000)
    existing = Keyword.get(opts, :existing, [])
    feed_state = Keyword.get(opts, :feed_state, %{})
    fetcher = Keyword.get(opts, :fetcher, Fetcher)
    max_retries = Keyword.get(opts, :max_retries, 1)
    retry_backoff_ms = Keyword.get(opts, :retry_backoff_ms, 500)
    stale_failure_threshold = Keyword.get(opts, :stale_failure_threshold, 7)
    started_at = DateTime.utc_now()
    enabled = Enum.filter(feeds, &Map.get(&1, :enabled, true))

    # Feeds are network-bound, so fetch them in parallel: each runs in its own
    # lightweight process, capped at `workers` at a time. A slow or hung feed is
    # killed on timeout without taking the others down.
    results =
      fetch_all(enabled, timeout_ms, workers, fetcher, feed_state, max_retries, retry_backoff_ms)
      |> then(&Enum.zip(enabled, &1))
      |> Enum.map(fn {feed, result} -> normalize_result(feed, result) end)

    fresh_items =
      results
      |> Enum.flat_map(fn
        {_feed, {:ok, items, _status, _metadata}, _retries} -> items
        {_feed, _result, _retries} -> []
      end)

    items = Store.merge_items(existing, fresh_items, max_items)
    next_feed_state = merge_feed_state(feed_state, results, started_at)
    sources = Enum.map(results, &source_status(&1, next_feed_state, stale_failure_threshold))
    failed_sources = Enum.count(sources, &(&1.status == "error"))
    successful_sources = Enum.count(sources, &(&1.status in ["ok", "not_modified"]))
    stale_sources = Enum.count(sources, & &1.stale)
    status = report_status(length(enabled), successful_sources, failed_sources, stale_sources)

    report = %{
      status: status,
      started_at: started_at,
      finished_at: DateTime.utc_now(),
      sources: sources,
      enabled_sources: length(enabled),
      successful_sources: successful_sources,
      fresh_items: length(fresh_items),
      total_items: length(items),
      not_modified_sources:
        Enum.count(results, fn {_feed, result, _retries} ->
          match?({:not_modified, _status, _metadata}, result)
        end),
      failed_sources: failed_sources,
      stale_sources: stale_sources,
      warnings: report_warnings(status, sources)
    }

    %{items: items, fresh_items: fresh_items, feed_state: next_feed_state, report: report}
  end

  defp normalize_result(feed, {:ok, {{:ok, items, status}, retries}}),
    do: {feed, {:ok, items, status, %{}}, retries}

  defp normalize_result(feed, {:ok, {result, retries}}), do: {feed, result, retries}
  defp normalize_result(feed, {:exit, reason}), do: {feed, {:error, inspect(reason), 0}, 0}

  defp fetch_all(enabled, timeout_ms, workers, fetcher, feed_state, max_retries, retry_backoff_ms) do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      enabled
      |> Task.async_stream(
        &fetch_with_retries(&1, timeout_ms, fetcher, feed_state, max_retries, retry_backoff_ms),
        max_concurrency: workers,
        timeout: timeout_ms + 10_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  defp fetch_with_retries(feed, timeout_ms, fetcher, feed_state, max_retries, retry_backoff_ms) do
    do_fetch_with_retries(feed, timeout_ms, fetcher, feed_state, max_retries, retry_backoff_ms, 0)
  end

  defp do_fetch_with_retries(
         feed,
         timeout_ms,
         fetcher,
         feed_state,
         max_retries,
         retry_backoff_ms,
         retries
       ) do
    result = fetch_feed(feed, timeout_ms, fetcher, feed_state)

    if retryable?(result) and retries < max_retries do
      if retry_backoff_ms > 0 do
        Process.sleep(retry_backoff_ms * (retries + 1))
      end

      do_fetch_with_retries(
        feed,
        timeout_ms,
        fetcher,
        feed_state,
        max_retries,
        retry_backoff_ms,
        retries + 1
      )
    else
      {result, retries}
    end
  end

  defp fetch_feed(feed, timeout_ms, fetcher, feed_state) when is_function(fetcher, 3) do
    fetcher.(feed, timeout_ms, feed_validators(feed_state, feed))
  end

  defp fetch_feed(feed, timeout_ms, fetcher, _feed_state) when is_function(fetcher, 2) do
    fetcher.(feed, timeout_ms)
  end

  defp fetch_feed(feed, timeout_ms, fetcher, feed_state) when is_atom(fetcher) do
    if function_exported?(fetcher, :fetch, 3) do
      fetcher.fetch(feed, timeout_ms, feed_validators(feed_state, feed))
    else
      fetcher.fetch(feed, timeout_ms)
    end
  end

  defp source_status({feed, {:ok, items, status, _metadata}, retries}, feed_state, threshold) do
    feed
    |> source_base("ok", status, length(items), false, nil, retries)
    |> put_state_fields(feed_state, threshold)
  end

  defp source_status({feed, {:not_modified, status, _metadata}, retries}, feed_state, threshold) do
    feed
    |> source_base("not_modified", status, 0, true, nil, retries)
    |> put_state_fields(feed_state, threshold)
  end

  defp source_status({feed, {:error, reason, status}, retries}, feed_state, threshold) do
    feed
    |> source_base("error", status, 0, false, reason, retries)
    |> put_state_fields(feed_state, threshold)
  end

  defp source_base(
         feed,
         status_name,
         response_code,
         items_seen,
         not_modified,
         last_error,
         retries
       ) do
    %{
      status: status_name,
      source_id: feed.id,
      source_name: feed.name,
      response_code: response_code,
      items_seen: items_seen,
      not_modified: not_modified,
      retries: retries,
      last_error: last_error
    }
  end

  defp put_state_fields(source, feed_state, threshold) do
    state = Map.get(feed_state, source.source_id, %{})

    Map.merge(source, %{
      consecutive_failures: failure_count(state),
      stale: stale?(state, threshold),
      last_checked_at: Map.get(state, :last_checked_at),
      last_success_at: Map.get(state, :last_success_at),
      first_failure_at: Map.get(state, :first_failure_at),
      last_failure_at: Map.get(state, :last_failure_at)
    })
  end

  defp merge_feed_state(feed_state, results, checked_at) do
    Enum.reduce(results, normalize_feed_state(feed_state), fn
      {feed, {:ok, _items, status, metadata}, _retries}, acc ->
        mark_success(acc, feed, metadata, checked_at, "ok", status)

      {feed, {:not_modified, status, metadata}, _retries}, acc ->
        mark_success(acc, feed, metadata, checked_at, "not_modified", status)

      {feed, {:error, reason, status}, _retries}, acc ->
        mark_failure(acc, feed, reason, status, checked_at)
    end)
  end

  defp mark_success(state, feed, metadata, checked_at, last_status, response_code) do
    current = Map.get(state, feed.id, %{})
    validators = validator_metadata(metadata)

    next =
      current
      |> Map.drop([
        :etag,
        :last_modified,
        :first_failure_at,
        :last_failure_at,
        :last_error
      ])
      |> Map.merge(validators)
      |> Map.merge(%{
        consecutive_failures: 0,
        last_checked_at: DateTime.to_iso8601(checked_at),
        last_success_at: DateTime.to_iso8601(checked_at),
        last_status: last_status,
        last_response_code: response_code
      })

    Map.put(state, feed.id, next)
  end

  defp mark_failure(state, feed, reason, response_code, checked_at) do
    current = Map.get(state, feed.id, %{})
    failures = failure_count(current) + 1
    checked_at = DateTime.to_iso8601(checked_at)

    next =
      current
      |> Map.merge(%{
        consecutive_failures: failures,
        first_failure_at: Map.get(current, :first_failure_at) || checked_at,
        last_failure_at: checked_at,
        last_checked_at: checked_at,
        last_status: "error",
        last_error: to_string(reason),
        last_response_code: response_code
      })

    Map.put(state, feed.id, next)
  end

  defp feed_validators(feed_state, feed) do
    feed_state
    |> normalize_feed_state()
    |> Map.get(feed.id, %{})
    |> validator_metadata()
  end

  defp normalize_feed_state(feed_state) do
    Map.new(feed_state, fn {feed_id, metadata} ->
      {to_string(feed_id), normalize_feed_metadata(metadata)}
    end)
  end

  defp normalize_feed_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
    |> then(fn metadata ->
      %{}
      |> put_non_empty(:etag, Map.get(metadata, :etag))
      |> put_non_empty(:last_modified, Map.get(metadata, :last_modified))
      |> put_non_empty(:last_checked_at, Map.get(metadata, :last_checked_at))
      |> put_non_empty(:last_success_at, Map.get(metadata, :last_success_at))
      |> put_non_empty(:first_failure_at, Map.get(metadata, :first_failure_at))
      |> put_non_empty(:last_failure_at, Map.get(metadata, :last_failure_at))
      |> put_non_empty(:last_status, Map.get(metadata, :last_status))
      |> put_non_empty(:last_error, Map.get(metadata, :last_error))
      |> put_non_negative_integer(:consecutive_failures, Map.get(metadata, :consecutive_failures))
      |> put_integer(:last_response_code, Map.get(metadata, :last_response_code))
    end)
  end

  defp normalize_feed_metadata(_metadata), do: %{}

  defp validator_metadata(metadata) when is_map(metadata) do
    metadata = normalize_feed_metadata(metadata)

    %{}
    |> put_non_empty(:etag, Map.get(metadata, :etag))
    |> put_non_empty(:last_modified, Map.get(metadata, :last_modified))
  end

  defp validator_metadata(_metadata), do: %{}

  defp report_status(enabled_sources, successful_sources, failed_sources, stale_sources) do
    cond do
      enabled_sources > 0 and successful_sources == 0 and failed_sources > 0 -> "critical"
      failed_sources > 0 or stale_sources > 0 -> "warning"
      true -> "ok"
    end
  end

  defp report_warnings(status, sources) do
    failed = Enum.filter(sources, &(&1.status == "error"))
    stale = Enum.filter(sources, & &1.stale)

    []
    |> maybe_warning(status == "critical", %{
      code: "no_successful_sources",
      message: "No feeds were collected successfully."
    })
    |> maybe_warning(failed != [], %{
      code: "feed_failures",
      count: length(failed),
      source_ids: Enum.map(failed, & &1.source_id),
      message: "#{length(failed)} feed(s) failed during collection."
    })
    |> maybe_warning(stale != [], %{
      code: "stale_feeds",
      count: length(stale),
      source_ids: Enum.map(stale, & &1.source_id),
      message: "#{length(stale)} feed(s) reached the consecutive failure threshold."
    })
    |> Enum.reverse()
  end

  defp maybe_warning(warnings, true, warning), do: [warning | warnings]
  defp maybe_warning(warnings, false, _warning), do: warnings

  defp stale?(metadata, threshold) when is_integer(threshold) and threshold > 0,
    do: failure_count(metadata) >= threshold

  defp stale?(_metadata, _threshold), do: false

  defp failure_count(metadata), do: Map.get(metadata, :consecutive_failures, 0)

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) do
    key
    |> to_string()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> key
  end

  defp put_non_empty(map, _key, nil), do: map
  defp put_non_empty(map, _key, ""), do: map
  defp put_non_empty(map, key, value), do: Map.put(map, key, to_string(value))

  defp put_non_negative_integer(map, key, value) do
    case parse_integer(value) do
      integer when is_integer(integer) and integer >= 0 -> Map.put(map, key, integer)
      _ -> map
    end
  end

  defp put_integer(map, key, value) do
    case parse_integer(value) do
      integer when is_integer(integer) -> Map.put(map, key, integer)
      _ -> map
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp retryable?({:error, _reason, status}), do: status == 0 or status in 500..599
  defp retryable?(_result), do: false
end
