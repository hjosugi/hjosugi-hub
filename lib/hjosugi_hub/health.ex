defmodule HjosugiHub.Health do
  @moduledoc """
  Builds the public `health.json`: what was exported, and how the last
  collection run went.

  The collection report is decoded JSON and the feed state is a cached term,
  so their keys may be strings or atoms and every value is read defensively.
  Only counts and warning summaries are published, never per-source details.
  """

  @stale_failure_threshold 7

  @doc """
  `export` describes the export itself: `:generated_at`, `:generated_text`,
  `:enabled_feeds`, `:item_count`, and `:asset_version`.
  """
  def report(export, collection_report, feed_state, feeds) do
    state_sources = enabled_feed_state(feed_state, MapSet.new(feeds, & &1.id))
    report_sources = list(collection_report, :sources)

    failed_in_state = Enum.count(state_sources, &(string(&1, :last_status) == "error"))

    failed_sources =
      integer(collection_report, :failed_sources) ||
        positive_count(report_sources, &(string(&1, :status) == "error")) ||
        failed_in_state

    stale_sources =
      integer(collection_report, :stale_sources) ||
        positive_count(report_sources, &(get(&1, :stale) in [true, "true"])) ||
        Enum.count(state_sources, &stale?/1)

    # A feed can still be failing in the cached state even when the report of
    # the latest run does not mention it.
    failing_sources = max(failed_sources, failed_in_state)

    collection_status =
      string(collection_report, :status) ||
        derived_status(collection_report, failed_sources, stale_sources)

    %{
      status: status(collection_status, failing_sources, stale_sources),
      service: "hjosugi-hub",
      generated_at: DateTime.to_iso8601(export.generated_at),
      generated_text: export.generated_text,
      enabled_feeds: export.enabled_feeds,
      item_count: export.item_count,
      asset_version: export.asset_version,
      collection_status: collection_status,
      collection_started_at: timestamp(collection_report, :started_at),
      collection_finished_at: timestamp(collection_report, :finished_at),
      fresh_items: integer(collection_report, :fresh_items),
      successful_sources: integer(collection_report, :successful_sources),
      failed_sources: failed_sources,
      failing_sources: failing_sources,
      stale_sources: stale_sources,
      warnings: warnings(collection_report, failed_sources, stale_sources)
    }
  end

  defp enabled_feed_state(feed_state, enabled_ids) when is_map(feed_state) do
    for {feed_id, state} <- feed_state,
        MapSet.member?(enabled_ids, to_string(feed_id)),
        is_map(state),
        do: state
  end

  defp enabled_feed_state(_feed_state, _enabled_ids), do: []

  defp stale?(state) do
    string(state, :last_status) == "error" and
      (integer(state, :consecutive_failures) || 0) >= @stale_failure_threshold
  end

  # nil rather than 0, so the caller falls through to its next source of truth.
  defp positive_count(sources, fun) do
    case Enum.count(sources, fun) do
      0 -> nil
      count -> count
    end
  end

  defp derived_status(report, failed_sources, stale_sources) do
    cond do
      failed_sources > 0 or stale_sources > 0 -> "warning"
      report == %{} -> nil
      true -> "ok"
    end
  end

  defp status("critical", _failing_sources, _stale_sources), do: "critical"

  defp status(_collection_status, failing_sources, stale_sources)
       when failing_sources > 0 or stale_sources > 0,
       do: "warning"

  defp status(collection_status, _failing_sources, _stale_sources), do: collection_status || "ok"

  # Warnings written by the collector win; otherwise summarize the counts.
  defp warnings(report, failed_sources, stale_sources) do
    case list(report, :warnings) do
      [] ->
        for {code, count, message} <- [
              {"feed_failures", failed_sources, "feed(s) failed during collection."},
              {"stale_feeds", stale_sources, "feed(s) reached the consecutive failure threshold."}
            ],
            count > 0,
            do: %{code: code, count: count, message: "#{count} #{message}"}

      reported ->
        Enum.map(reported, fn warning ->
          %{
            code: string(warning, :code),
            count: integer(warning, :count),
            message: string(warning, :message)
          }
        end)
    end
  end

  defp list(map, key) do
    case get(map, key) do
      value when is_list(value) -> value
      _ -> []
    end
  end

  defp string(map, key) do
    case get(map, key) do
      value when is_binary(value) -> value
      # nil and booleans are atoms too; they are not status names.
      value when is_boolean(value) or is_nil(value) -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      _ -> nil
    end
  end

  defp integer(map, key) do
    case get(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp timestamp(map, key) do
    case get(map, key) do
      %DateTime{} = value -> DateTime.to_iso8601(value)
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp get(_map, _key), do: nil
end
