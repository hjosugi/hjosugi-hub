defmodule HjosugiHub.PublicItem do
  @moduledoc """
  Display fields of the public item maps built by `HjosugiHub.Store.public_items/1`.

  The feeds and the digest show the same fields, so the fallbacks for a
  missing title or summary and the tag cleanup live here.
  """

  alias HjosugiHub.Util

  def title(item) do
    case Util.trim(Map.get(item, :title)) do
      "" -> "Untitled radar item"
      title -> title
    end
  end

  def url(item), do: Util.trim(Map.get(item, :url))

  def summary(item) do
    Util.summarize(Map.get(item, :summary) || Map.get(item, :content) || "", 500)
  end

  def tags(item), do: Util.merge_tags(Map.get(item, :tags, []))
end
