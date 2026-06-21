defmodule HjosugiHub.FeedParser do
  @moduledoc false

  alias HjosugiHub.{Item, Tagger, Util}

  def parse(body, feed, now \\ DateTime.utc_now()) do
    xml = to_string(body)

    items =
      cond do
        Regex.match?(~r/<(?:[A-Za-z0-9_.-]+:)?feed\b/iu, xml) ->
          xml |> blocks("entry") |> Enum.map(&atom_item(&1, feed, now))

        Regex.match?(~r/<(?:[A-Za-z0-9_.-]+:)?item\b/iu, xml) ->
          xml |> blocks("item") |> Enum.map(&rss_item(&1, feed, now))

        true ->
          throw(:unsupported_feed)
      end

    {:ok, Enum.reject(items, &is_nil/1)}
  rescue
    error -> {:error, Exception.message(error)}
  catch
    reason -> {:error, inspect(reason)}
  end

  defp rss_item(xml, feed, now) do
    title = xml |> element_text("title") |> Util.clean_text()
    raw_content = first([element_text(xml, "encoded"), element_text(xml, "description")])
    content = Util.clean_text(raw_content)
    link = resolve_url(feed.url, element_text(xml, "link"))
    raw_id = first([element_text(xml, "guid"), link, title])

    if raw_id == "" do
      nil
    else
      published_at =
        first([element_text(xml, "pubDate"), element_text(xml, "date")]) |> Util.parse_date() ||
          now

      author =
        first([element_text(xml, "creator"), element_text(xml, "author")]) |> Util.clean_text()

      categories = xml |> elements_text("category") |> Enum.map(&Util.clean_text/1)
      tags = Tagger.apply(title, content, [Map.get(feed, :tags, []), categories])

      %Item{
        id: Util.stable_id(feed.id, raw_id),
        source_id: feed.id,
        source_name: feed.name,
        source_kind: Map.get(feed, :kind, "rss"),
        title: title,
        url: link,
        author: author,
        summary: Util.summarize(content),
        content: Util.truncate(content, 1500),
        published_at: published_at,
        collected_at: now,
        tags: tags
      }
    end
  end

  defp atom_item(xml, feed, now) do
    title = xml |> element_text("title") |> Util.clean_text()
    raw_content = first([element_text(xml, "content"), element_text(xml, "summary")])
    content = Util.clean_text(raw_content)
    link = atom_link(xml, feed.url)
    raw_id = first([element_text(xml, "id"), link, title])

    if raw_id == "" do
      nil
    else
      published_at =
        first([element_text(xml, "published"), element_text(xml, "updated")]) |> Util.parse_date() ||
          now

      author = xml |> element_text("author") |> element_text("name") |> Util.clean_text()

      categories =
        xml |> element_tags("category") |> Enum.map(&attr(&1, "term")) |> Enum.reject(&(&1 == ""))

      tags = Tagger.apply(title, content, [Map.get(feed, :tags, []), categories])

      %Item{
        id: Util.stable_id(feed.id, raw_id),
        source_id: feed.id,
        source_name: feed.name,
        source_kind: Map.get(feed, :kind, "atom"),
        title: title,
        url: link,
        author: author,
        summary: Util.summarize(content),
        content: Util.truncate(content, 1500),
        published_at: published_at,
        collected_at: now,
        tags: tags
      }
    end
  end

  defp atom_link(xml, base_url) do
    links = element_tags(xml, "link")

    preferred =
      Enum.find(links, fn tag ->
        rel = attr(tag, "rel")
        rel == "" or rel == "alternate"
      end) || List.first(links)

    href =
      case preferred do
        nil -> element_text(xml, "link")
        tag -> attr(tag, "href")
      end

    resolve_url(base_url, href)
  end

  defp blocks(xml, tag) do
    tag_re = tag_pattern(tag)
    re = Regex.compile!("<#{tag_re}\\b[^>]*>(.*?)</#{tag_re}>", "isu")

    re
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn [block] -> block end)
  end

  defp elements_text(xml, tag) do
    xml
    |> blocks(tag)
    |> Enum.map(&strip_cdata/1)
  end

  defp element_text(xml, tag) do
    xml
    |> elements_text(tag)
    |> first()
  end

  defp element_tags(xml, tag) do
    tag_re = tag_pattern(tag)
    re = Regex.compile!("<#{tag_re}\\b[^>]*(?:/>|>.*?</#{tag_re}>)", "isu")
    Regex.scan(re, xml) |> Enum.map(fn [match] -> match end)
  end

  defp attr(xml, name) do
    re = Regex.compile!("\\b#{Regex.escape(name)}\\s*=\\s*([\"'])(.*?)\\1", "isu")

    case Regex.run(re, xml) do
      [_all, _quote, value] -> Util.clean_text(value)
      _ -> ""
    end
  end

  defp first(values) do
    values
    |> Enum.map(&(to_string(&1) |> strip_cdata() |> String.trim()))
    |> Enum.find("", &(&1 != ""))
  end

  defp strip_cdata(value) do
    Regex.replace(~r/^\s*<!\[CDATA\[(.*)\]\]>\s*$/su, to_string(value), "\\1")
  end

  defp resolve_url(_base_url, nil), do: ""

  defp resolve_url(base_url, raw_url) do
    raw_url = String.trim(raw_url || "")

    if raw_url == "" do
      ""
    else
      uri = URI.parse(raw_url)

      cond do
        uri.scheme in ["http", "https"] and is_binary(uri.host) ->
          URI.to_string(uri)

        is_nil(uri.scheme) ->
          base_url |> URI.parse() |> URI.merge(raw_url) |> URI.to_string()

        true ->
          ""
      end
    end
  rescue
    _ -> ""
  end

  defp tag_pattern(tag), do: "(?:[A-Za-z0-9_.-]+:)?" <> Regex.escape(tag)
end
