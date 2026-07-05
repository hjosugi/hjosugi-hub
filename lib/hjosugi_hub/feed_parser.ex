defmodule HjosugiHub.FeedParser do
  @moduledoc false

  require Record

  alias HjosugiHub.{Item, Store, Tagger, Util}

  @xml_attribute_fields Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  @xml_element_fields Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  @xml_text_fields Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")

  @xml_attribute_size length(@xml_attribute_fields) + 1
  @xml_element_size length(@xml_element_fields) + 1
  @xml_text_size length(@xml_text_fields) + 1

  Record.defrecordp(:xmlAttribute, @xml_attribute_fields)
  Record.defrecordp(:xmlElement, @xml_element_fields)
  Record.defrecordp(:xmlText, @xml_text_fields)

  def parse(body, feed, now \\ DateTime.utc_now()) do
    document = parse_xml(body)
    feed_element = first_element([document | descendant_elements(document, "feed")], "feed")
    rss_items = rss_item_elements(document)

    items =
      cond do
        feed_element ->
          feed_element |> child_elements("entry") |> Enum.map(&atom_item(&1, feed, now))

        rss_items != [] ->
          Enum.map(rss_items, &rss_item(&1, feed, now))

        true ->
          throw(:unsupported_feed)
      end

    {:ok, Enum.reject(items, &is_nil/1)}
  rescue
    error -> {:error, Exception.message(error)}
  catch
    reason -> {:error, inspect(reason)}
    :exit, reason -> {:error, inspect(reason)}
  end

  defp rss_item(item, feed, now) do
    title = item |> element_text("title") |> Util.clean_text()
    raw_content = first([element_text(item, "encoded"), element_text(item, "description")])
    content = Util.clean_text(raw_content)
    score = extract_score(raw_content)
    link = resolve_url(feed.url, element_text(item, "link"))
    raw_id = first([element_text(item, "guid"), link, title])

    if raw_id == "" do
      nil
    else
      published_at =
        first([element_text(item, "pubDate"), element_text(item, "date")]) |> Util.parse_date() ||
          now

      published_at = Store.clamp_published_at(published_at, now)

      author =
        first([element_text(item, "creator"), element_text(item, "author")]) |> Util.clean_text()

      categories = item |> elements_text("category") |> Enum.map(&Util.clean_text/1)
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
        score: score,
        tags: tags
      }
    end
  end

  defp atom_item(entry, feed, now) do
    title = entry |> element_text("title") |> Util.clean_text()
    raw_content = first([element_text(entry, "content"), element_text(entry, "summary")])
    content = Util.clean_text(raw_content)
    score = extract_score(raw_content)
    link = atom_link(entry, feed.url)
    raw_id = first([element_text(entry, "id"), link, title])

    if raw_id == "" do
      nil
    else
      published_at =
        first([element_text(entry, "published"), element_text(entry, "updated")])
        |> Util.parse_date() ||
          now

      published_at = Store.clamp_published_at(published_at, now)

      author =
        entry
        |> element_tags("author")
        |> List.first()
        |> author_name()

      categories =
        entry
        |> element_tags("category")
        |> Enum.map(&attr(&1, "term"))
        |> Enum.reject(&(&1 == ""))

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
        score: score,
        tags: tags
      }
    end
  end

  # Crowd-vote count where a feed exposes it (e.g. Hacker News "Points: 123").
  defp extract_score(raw) do
    case Regex.run(~r/Points:\s*(\d+)/i, to_string(raw)) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp atom_link(entry, base_url) do
    links = element_tags(entry, "link")

    preferred =
      Enum.find(links, fn tag ->
        rel = attr(tag, "rel")
        rel == "" or rel == "alternate"
      end) || List.first(links)

    href =
      case preferred do
        nil -> element_text(entry, "link")
        tag -> attr(tag, "href")
      end

    resolve_url(base_url, href)
  end

  defp author_name(nil), do: ""
  defp author_name(author), do: author |> element_text("name") |> Util.clean_text()

  defp parse_xml(body) do
    {:ok, _applications} = Application.ensure_all_started(:xmerl)

    xml = body |> to_string() |> :binary.bin_to_list()

    :xmerl_scan
    |> apply(:string, [xml, [quiet: true]])
    |> elem(0)
  end

  defp rss_item_elements(document) do
    channels =
      [document | descendant_elements(document, "channel")]
      |> Enum.filter(&element_name?(&1, "channel"))

    channel_items = Enum.flat_map(channels, &child_elements(&1, "item"))

    cond do
      channel_items != [] -> channel_items
      element_name?(document, "item") -> [document]
      true -> child_elements(document, "item")
    end
  end

  defp elements_text(element, tag) do
    element
    |> child_elements(tag)
    |> Enum.map(&text_content/1)
  end

  defp element_text(nil, _tag), do: ""

  defp element_text(element, tag) do
    element
    |> elements_text(tag)
    |> first()
  end

  defp element_tags(nil, _tag), do: []
  defp element_tags(element, tag), do: child_elements(element, tag)

  defp attr(nil, _name), do: ""

  defp attr(element, name) do
    element
    |> xmlElement(:attributes)
    |> Enum.find(&attribute_name?(&1, name))
    |> case do
      nil -> ""
      attribute -> attribute |> xmlAttribute(:value) |> to_string() |> Util.clean_text()
    end
  end

  defp first(values) do
    values
    |> Enum.map(&(to_string(&1) |> String.trim()))
    |> Enum.find("", &(&1 != ""))
  end

  defp first_element(elements, tag) do
    Enum.find(elements, &element_name?(&1, tag))
  end

  defp descendant_elements(element, tag) do
    element
    |> child_nodes()
    |> Enum.flat_map(fn
      node when is_tuple(node) ->
        if xml_element?(node) do
          descendants = descendant_elements(node, tag)

          if element_name?(node, tag) do
            [node | descendants]
          else
            descendants
          end
        else
          []
        end

      _node ->
        []
    end)
  end

  defp child_elements(element, tag) do
    element
    |> child_nodes()
    |> Enum.filter(&(xml_element?(&1) and element_name?(&1, tag)))
  end

  defp child_nodes(element) when is_tuple(element) do
    if xml_element?(element), do: xmlElement(element, :content), else: []
  end

  defp child_nodes(_element), do: []

  defp text_content(element) do
    element
    |> child_nodes()
    |> Enum.map(&node_text/1)
    |> Enum.join()
  end

  defp node_text(node) when is_tuple(node) do
    cond do
      xml_text?(node) ->
        node |> xmlText(:value) |> to_string()

      xml_element?(node) ->
        " " <> text_content(node) <> " "

      true ->
        ""
    end
  end

  defp node_text(_node), do: ""

  defp element_name?(element, name) do
    xml_element?(element) and local_name(xmlElement(element, :name)) == name
  end

  defp attribute_name?(attribute, name) do
    xml_attribute?(attribute) and local_name(xmlAttribute(attribute, :name)) == name
  end

  defp local_name(name) do
    name
    |> to_string()
    |> String.split(":")
    |> List.last()
  end

  defp xml_attribute?(term) do
    is_tuple(term) and tuple_size(term) == @xml_attribute_size and elem(term, 0) == :xmlAttribute
  end

  defp xml_element?(term) do
    is_tuple(term) and tuple_size(term) == @xml_element_size and elem(term, 0) == :xmlElement
  end

  defp xml_text?(term) do
    is_tuple(term) and tuple_size(term) == @xml_text_size and elem(term, 0) == :xmlText
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
end
