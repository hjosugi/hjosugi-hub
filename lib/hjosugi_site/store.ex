defmodule HjosugiSite.Store do
  @moduledoc false

  alias HjosugiSite.{Item, JSON, Util}

  def read_items(path) do
    if File.exists?(path) do
      path |> File.read!() |> :erlang.binary_to_term() |> normalize_items()
    else
      []
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
        tags: item.tags
      }
    end)
  end

  def sort_items(items) do
    Enum.sort_by(items, &DateTime.to_unix(Util.item_time(&1)), :desc)
  end

  defp normalize_items(items) when is_list(items), do: Enum.map(items, &normalize_item/1)
  defp normalize_items(_items), do: []

  defp normalize_item(%Item{} = item), do: item

  defp normalize_item(%{} = item) do
    %Item{
      id: Map.get(item, :id),
      source_id: Map.get(item, :source_id),
      source_name: Map.get(item, :source_name),
      source_kind: Map.get(item, :source_kind),
      title: Map.get(item, :title),
      url: Map.get(item, :url),
      author: Map.get(item, :author),
      summary: Map.get(item, :summary),
      content: Map.get(item, :content),
      published_at: Map.get(item, :published_at),
      collected_at: Map.get(item, :collected_at),
      tags: Map.get(item, :tags, [])
    }
  end

  defp merge_item(current, incoming) do
    %{incoming | collected_at: current.collected_at || incoming.collected_at}
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
