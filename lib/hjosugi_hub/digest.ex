defmodule HjosugiHub.Digest do
  @moduledoc """
  Weekly ranking behind the /digest/ page.

  Scored public items are grouped into 7-day windows counted back from the
  export time, and each window keeps its top items by score multiplied by the
  feed weight. Items without a numeric score are left out.
  """

  alias HjosugiHub.{PublicItem, Util}

  @week_count 4
  @items_per_week 10
  @window_seconds 7 * 24 * 60 * 60

  @doc "Non-empty digest windows, most recent first."
  def sections(public_items, generated_at) do
    by_window =
      public_items
      |> Enum.filter(&is_number(Map.get(&1, :score)))
      |> Enum.group_by(&window_index(&1, generated_at))

    for index <- 0..(@week_count - 1), items = Map.get(by_window, index, []), items != [] do
      end_at = DateTime.add(generated_at, -index * @window_seconds, :second)
      start_at = DateTime.add(end_at, -@window_seconds, :second)

      %{
        index: index,
        label: label(index),
        period: "#{date(start_at)} - #{date(end_at)} UTC",
        items: items |> rank() |> Enum.take(@items_per_week) |> Enum.with_index(1) |> entries()
      }
    end
  end

  @doc "Formats a score or weight without a trailing `.0`."
  def format_number(number) when is_integer(number), do: Integer.to_string(number)

  def format_number(number) when is_float(number) do
    number
    |> :erlang.float_to_binary(decimals: 1)
    |> String.replace_suffix(".0", "")
  end

  # Which window an item falls in; nil when it is in the future or too old.
  defp window_index(item, generated_at) do
    age = DateTime.diff(generated_at, Util.item_time(item), :second)

    if age >= 0 and age < @week_count * @window_seconds do
      div(age, @window_seconds)
    end
  end

  # Ties fall back to raw score, recency, then stable text keys so the order
  # never depends on the input order.
  defp rank(items) do
    Enum.sort_by(items, fn item ->
      {
        -rank_score(item),
        -item.score,
        -DateTime.to_unix(Util.item_time(item)),
        String.downcase(PublicItem.title(item)),
        Util.trim(Map.get(item, :source_id)),
        Util.trim(Map.get(item, :id)),
        PublicItem.url(item)
      }
    end)
  end

  defp entries(ranked) do
    Enum.map(ranked, fn {item, rank} ->
      %{
        rank: rank,
        title: PublicItem.title(item),
        url: PublicItem.url(item),
        summary: PublicItem.summary(item),
        source_name: source_name(item),
        tags: PublicItem.tags(item),
        item_date: date(Util.item_time(item)),
        score: item.score,
        weight: weight(item),
        rank_score: rank_score(item)
      }
    end)
  end

  defp source_name(item) do
    case Util.trim(Map.get(item, :source_name)) do
      "" -> Util.trim(Map.get(item, :source_id))
      name -> name
    end
  end

  defp rank_score(item), do: item.score * weight(item)

  defp weight(%{weight: weight}) when is_number(weight), do: weight
  defp weight(_item), do: 1.0

  defp label(0), do: "Last 7 days"
  defp label(index), do: "#{index * 7 + 1}-#{(index + 1) * 7} days ago"

  defp date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")
end
