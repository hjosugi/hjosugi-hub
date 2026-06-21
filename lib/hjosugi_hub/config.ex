defmodule HjosugiHub.Config do
  @moduledoc false

  def site(path \\ "config/site.exs"), do: load!(path)
  def feeds(path \\ "config/feeds.exs"), do: load!(path)

  def avatar_url(site) do
    handle =
      site
      |> Map.get(:links, [])
      |> Enum.find_value(Map.get(site, :handle, ""), fn link ->
        if String.downcase(Map.get(link, :label, "")) == "github" do
          link
          |> Map.get(:url, "")
          |> String.trim()
          |> String.replace_prefix("https://github.com/", "")
          |> String.trim("/")
        end
      end)
      |> to_string()

    if Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, handle) do
      "https://github.com/#{handle}.png?size=160"
    else
      ""
    end
  end

  def enabled_feeds(feeds) do
    Enum.count(feeds, &Map.get(&1, :enabled, true))
  end

  # Ranking bias per source. A feed may set its own :weight; otherwise it falls
  # back to a default for its :kind (crowd-voted aggregators rank highest).
  @kind_weights %{
    "aggregator" => 1.3,
    "newsletter" => 1.2,
    "engineering" => 1.15,
    "official" => 1.0,
    "youtube" => 1.0
  }

  def feed_weight(feed) do
    case Map.get(feed, :weight) do
      weight when is_number(weight) -> weight / 1
      _ -> Map.get(@kind_weights, Map.get(feed, :kind), 1.0)
    end
  end

  defp load!(path) do
    {value, _binding} = Code.eval_file(path)
    value
  end
end
