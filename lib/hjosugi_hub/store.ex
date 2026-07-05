defmodule HjosugiHub.Store do
  @moduledoc """
  Persistence and projection layer for cached radar data.

  It reads and writes term/JSON files, normalizes older item and feed-state
  shapes, merges collected items, and converts internal items into public maps
  for rendering.
  """

  alias HjosugiHub.{Item, JSON, Util}

  @future_published_at_tolerance_seconds 6 * 60 * 60

  def read_items(path) do
    with true <- File.exists?(path),
         {:ok, encoded} <- File.read(path),
         {:ok, terms} <- decode_items(encoded) do
      normalize_items(terms)
    else
      _ -> []
    end
  end

  def write_items(path, items) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, :erlang.term_to_binary(items))
  end

  def feed_state_path(cache_path) do
    cache_path |> Path.dirname() |> Path.join("feed-state.term")
  end

  def read_feed_state(path) do
    with true <- File.exists?(path),
         {:ok, encoded} <- File.read(path),
         {:ok, state} <- decode_items(encoded) do
      normalize_feed_state(state)
    else
      _ -> %{}
    end
  end

  def write_feed_state(path, state) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, :erlang.term_to_binary(normalize_feed_state(state)))
  end

  def read_json(path) do
    with true <- File.exists?(path),
         {:ok, encoded} <- File.read(path),
         {:ok, value} <- Elixir.JSON.decode(encoded) do
      value
    else
      _ -> %{}
    end
  end

  def write_json(path, value) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, JSON.encode!(value) <> "\n")
  end

  def merge_items(existing, incoming, max_items) do
    existing
    |> Enum.reduce(%{}, fn item, acc -> Map.put(acc, item.id, item) end)
    |> then(fn by_id ->
      Enum.reduce(incoming, by_id, fn item, acc ->
        Map.update(acc, item.id, item, fn current -> merge_item(current, item) end)
      end)
    end)
    |> Map.values()
    |> sort_items()
    |> Enum.take(max_items)
  end

  def public_items(items) do
    items
    |> Enum.map(fn %Item{} = item -> public_item(item) end)
    |> group_public_items()
  end

  def sort_items(items) do
    Enum.sort_by(items, &DateTime.to_unix(Util.item_time(&1)), :desc)
  end

  def clamp_published_at(published_at, collected_at) do
    clamp_published_at(published_at, collected_at, @future_published_at_tolerance_seconds)
  end

  def clamp_published_at(
        %DateTime{} = published_at,
        %DateTime{} = collected_at,
        tolerance_seconds
      ) do
    latest_reasonable = DateTime.add(collected_at, tolerance_seconds, :second)

    if DateTime.compare(published_at, latest_reasonable) == :gt do
      collected_at
    else
      published_at
    end
  end

  def clamp_published_at(published_at, _collected_at, _tolerance_seconds), do: published_at

  defp normalize_items(items) when is_list(items), do: Enum.map(items, &normalize_item/1)
  defp normalize_items(_items), do: []

  defp normalize_feed_state(state) when is_map(state) do
    Map.new(state, fn {feed_id, metadata} ->
      {to_string(feed_id), normalize_feed_metadata(metadata)}
    end)
  end

  defp normalize_feed_state(_state), do: %{}

  defp normalize_feed_metadata(metadata) when is_map(metadata) do
    metadata = Map.new(metadata, fn {key, value} -> {to_string(key), value} end)

    %{}
    |> put_non_empty(:etag, Map.get(metadata, "etag"))
    |> put_non_empty(:last_modified, Map.get(metadata, "last_modified"))
    |> put_non_empty(:last_checked_at, Map.get(metadata, "last_checked_at"))
    |> put_non_empty(:last_success_at, Map.get(metadata, "last_success_at"))
    |> put_non_empty(:first_failure_at, Map.get(metadata, "first_failure_at"))
    |> put_non_empty(:last_failure_at, Map.get(metadata, "last_failure_at"))
    |> put_non_empty(:last_status, Map.get(metadata, "last_status"))
    |> put_non_empty(:last_error, Map.get(metadata, "last_error"))
    |> put_non_negative_integer(:consecutive_failures, Map.get(metadata, "consecutive_failures"))
    |> put_integer(:last_response_code, Map.get(metadata, "last_response_code"))
  end

  defp normalize_feed_metadata(_metadata), do: %{}

  defp decode_items(encoded) do
    {:ok, :erlang.binary_to_term(encoded, [:safe])}
  rescue
    ArgumentError -> :error
  end

  # Rebuild every cached item through the current struct so fields added after it
  # was serialized (e.g. :score) get their defaults instead of missing keys.
  defp normalize_item(%{} = item) do
    collected_at = Map.get(item, :collected_at)

    %Item{
      id: Map.get(item, :id),
      source_id: Map.get(item, :source_id),
      source_name: Map.get(item, :source_name),
      source_kind: Map.get(item, :source_kind),
      title: Map.get(item, :title),
      url: Map.get(item, :url),
      author: Map.get(item, :author),
      summary: resanitize(Map.get(item, :summary)),
      content: resanitize(Map.get(item, :content)),
      published_at: clamp_published_at(Map.get(item, :published_at), collected_at),
      collected_at: collected_at,
      score: Map.get(item, :score),
      tags: Map.get(item, :tags, [])
    }
  end

  defp merge_item(current, incoming) do
    %{incoming | collected_at: current.collected_at || incoming.collected_at}
  end

  defp public_item(%Item{} = item) do
    %{
      id: Map.get(item, :id),
      source_id: Map.get(item, :source_id),
      source_name: Map.get(item, :source_name),
      source_kind: Map.get(item, :source_kind),
      title: Map.get(item, :title),
      url: Map.get(item, :url),
      author: empty_to_nil(Map.get(item, :author)),
      summary: Map.get(item, :summary),
      content: empty_to_nil(Map.get(item, :content)),
      published_at: Map.get(item, :published_at),
      collected_at: Map.get(item, :collected_at),
      # Map.get, not item.score: hub.collect calls public_items/1 directly on
      # freshly merged items, which can include a struct deserialized from the
      # cache before :score existed. Dot access would raise KeyError there.
      score: Map.get(item, :score),
      tags: Map.get(item, :tags, [])
    }
    |> put_non_empty(:normalized_url, Util.normalize_url(Map.get(item, :url)))
  end

  defp group_public_items(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {item, index}, groups ->
      key = public_item_group_key(item, index)

      Map.update(groups, key, %{index: index, items: [item]}, fn group ->
        %{group | items: [item | group.items]}
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.index)
    |> Enum.map(fn group ->
      group.items
      |> Enum.reverse()
      |> merge_public_item_group()
    end)
  end

  defp public_item_group_key(%{normalized_url: normalized_url}, _index)
       when is_binary(normalized_url) and normalized_url != "" do
    {:url, normalized_url}
  end

  defp public_item_group_key(_item, index), do: {:ungrouped, index}

  defp merge_public_item_group([item]) do
    Map.put(item, :sources, [public_item_source(item)])
  end

  defp merge_public_item_group([representative | _rest] = items) do
    representative
    |> Map.put(:tags, Util.merge_tags(Enum.map(items, &Map.get(&1, :tags, []))))
    |> Map.put(:sources, Enum.map(items, &public_item_source/1))
  end

  defp public_item_source(item) do
    %{
      item_id: Map.get(item, :id),
      source_id: Map.get(item, :source_id),
      source_name: Map.get(item, :source_name),
      source_kind: Map.get(item, :source_kind),
      title: Map.get(item, :title),
      url: Map.get(item, :url),
      score: Map.get(item, :score)
    }
  end

  # Re-clean cached text so items stored before a clean_text fix (e.g. raw
  # entity-escaped HTML from Lobsters) become plain text on the next read.
  defp resanitize(nil), do: nil
  defp resanitize(value) when is_binary(value), do: Util.clean_text(value)
  defp resanitize(value), do: value

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

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
end
