defmodule HjosugiHub.Store do
  @moduledoc false

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
    Enum.map(items, fn %Item{} = item ->
      %{
        id: item.id,
        source_id: item.source_id,
        source_name: item.source_name,
        source_kind: item.source_kind,
        title: item.title,
        url: item.url,
        author: empty_to_nil(item.author),
        summary: item.summary,
        content: empty_to_nil(item.content),
        published_at: item.published_at,
        collected_at: item.collected_at,
        # Map.get, not item.score: hub.collect calls public_items/1 directly on
        # freshly merged items, which can include a struct deserialized from the
        # cache before :score existed. Dot access would raise KeyError there.
        score: Map.get(item, :score),
        tags: item.tags
      }
    end)
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

  # Re-clean cached text so items stored before a clean_text fix (e.g. raw
  # entity-escaped HTML from Lobsters) become plain text on the next read.
  defp resanitize(nil), do: nil
  defp resanitize(value) when is_binary(value), do: Util.clean_text(value)
  defp resanitize(value), do: value

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
