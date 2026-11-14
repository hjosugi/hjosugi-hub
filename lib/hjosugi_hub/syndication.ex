defmodule HjosugiHub.Syndication do
  @moduledoc """
  Feeds published alongside the radar: Atom (`radar.xml`), JSON Feed
  (`feed.json`), and the OPML list of followed sources (`feeds.opml`).

  Both item feeds carry the newest public items. Absolute links are only
  included when the export knows its public base URL.
  """

  alias HjosugiHub.{HTML, PublicItem, Util}

  @item_limit 50

  def title(site) do
    case Util.trim(Map.get(site, :handle)) do
      "" -> "hjosugi-hub radar"
      handle -> "#{handle} radar"
    end
  end

  def description(site), do: "Search collected technical reading items from #{site.handle}."

  def opml(site, feeds) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>#{HTML.escape(Map.get(site, :handle, "hjosugi-hub"))} feeds</title>
      </head>
      <body>
    #{Enum.map_join(feeds, "\n", &opml_outline/1)}
      </body>
    </opml>
    """
  end

  defp opml_outline(feed) do
    name = HTML.escape(Map.get(feed, :name, Map.get(feed, :id, "")))
    kind = HTML.escape(Map.get(feed, :kind, "rss"))
    url = HTML.escape(Map.get(feed, :url, ""))

    ~s(    <outline text="#{name}" title="#{name}" type="rss" xmlUrl="#{url}" category="#{kind}" kind="#{kind}"/>)
  end

  def atom(site, base_url, public_items, generated_at) do
    items = newest(public_items)

    updated_at =
      case items do
        [newest | _rest] -> Util.item_time(newest)
        [] -> generated_at
      end

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>#{HTML.escape(title(site))}</title>
      <subtitle>#{HTML.escape(description(site))}</subtitle>
      <id>#{HTML.escape(feed_id(site, base_url))}</id>
      #{atom_feed_links(base_url)}
      <updated>#{DateTime.to_iso8601(updated_at)}</updated>
      <author><name>#{HTML.escape(author_name(site))}</name></author>
    #{Enum.map_join(items, "\n", &atom_entry/1)}
    </feed>
    """
  end

  defp atom_feed_links(""), do: ""

  defp atom_feed_links(base_url) do
    Enum.join(
      [
        atom_link("alternate", "text/html", Util.absolute_url(base_url, "radar/")),
        atom_link("self", "application/atom+xml", Util.absolute_url(base_url, "radar.xml"))
      ],
      "\n  "
    )
  end

  defp atom_link(rel, type, href) do
    ~s(<link rel="#{rel}" type="#{type}" href="#{HTML.escape(href)}"/>)
  end

  defp atom_entry(item) do
    """
      <entry>
        <title>#{HTML.escape(PublicItem.title(item))}</title>
        <id>#{item_id(item)}</id>
        <updated>#{DateTime.to_iso8601(Util.item_time(item))}</updated>
    #{atom_published(item)}
    #{atom_entry_link(PublicItem.url(item))}
        <summary type="text">#{HTML.escape(PublicItem.summary(item))}</summary>
    #{atom_entry_author(Util.trim(Map.get(item, :author)))}
    #{Enum.map_join(PublicItem.tags(item), "\n", &~s(    <category term="#{HTML.escape(&1)}"/>))}
      </entry>
    """
    |> String.trim_trailing()
  end

  defp atom_published(%{published_at: %DateTime{} = published_at}) do
    "    <published>#{DateTime.to_iso8601(published_at)}</published>"
  end

  defp atom_published(_item), do: ""

  defp atom_entry_link(""), do: ""
  defp atom_entry_link(url), do: "    " <> atom_link("alternate", "text/html", url)

  defp atom_entry_author(""), do: ""
  defp atom_entry_author(author), do: "    <author><name>#{HTML.escape(author)}</name></author>"

  @doc """
  JSON Feed 1.1 document. `images` gives the site-relative paths of the feed's
  `:icon` and `:favicon`.
  """
  def json(site, base_url, public_items, images) do
    %{
      version: "https://jsonfeed.org/version/1.1",
      title: title(site),
      description: description(site),
      language: "en",
      authors: [%{name: author_name(site)}],
      items: public_items |> newest() |> Enum.map(&json_item/1)
    }
    |> put_present(:home_page_url, Util.absolute_url(base_url, "radar/"))
    |> put_present(:feed_url, Util.absolute_url(base_url, "feed.json"))
    |> put_present(:icon, Util.absolute_url(base_url, Keyword.fetch!(images, :icon)))
    |> put_present(:favicon, Util.absolute_url(base_url, Keyword.fetch!(images, :favicon)))
  end

  defp json_item(item) do
    summary = PublicItem.summary(item)

    %{
      id: item_id(item),
      title: PublicItem.title(item),
      content_text: summary,
      summary: summary,
      date_modified: DateTime.to_iso8601(Util.item_time(item)),
      tags: PublicItem.tags(item)
    }
    |> put_present(:url, PublicItem.url(item))
    |> put_present(:date_published, json_published(item))
    |> put_present(:authors, json_authors(Util.trim(Map.get(item, :author))))
  end

  defp json_published(%{published_at: %DateTime{} = published_at}),
    do: DateTime.to_iso8601(published_at)

  defp json_published(_item), do: ""

  defp json_authors(""), do: []
  defp json_authors(author), do: [%{name: author}]

  defp newest(public_items) do
    public_items
    |> Enum.sort_by(&DateTime.to_unix(Util.item_time(&1)), :desc)
    |> Enum.take(@item_limit)
  end

  # Feed readers key on these ids, so they must not change between exports:
  # the public URL when there is one, otherwise a URN hashed from stable fields.
  defp feed_id(site, ""), do: urn("feed", Map.get(site, :handle, "hjosugi-hub"))
  defp feed_id(_site, base_url), do: Util.absolute_url(base_url, "radar/")

  defp item_id(item) do
    seed =
      [:source_id, :id, :normalized_url, :url, :title]
      |> Enum.map(&Util.trim(Map.get(item, &1)))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(<<0>>)

    urn("item", seed)
  end

  defp urn(type, seed) do
    digest =
      :crypto.hash(:sha256, Util.trim(seed))
      |> binary_part(0, 16)
      |> Base.encode16(case: :lower)

    "urn:hjosugi-hub:#{type}:#{digest}"
  end

  defp author_name(site) do
    Enum.find(
      [Util.trim(Map.get(site, :display_name)), Util.trim(Map.get(site, :handle)), "hjosugi"],
      &(&1 != "")
    )
  end

  defp put_present(map, _key, value) when value in ["", []], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
