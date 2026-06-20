defmodule SignalGarden.FeedParser do
  @moduledoc false

  require Record

  Record.defrecord(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecord(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecord(:xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl"))

  alias SignalGarden.{Item, Tagger, Util}

  def parse(body, feed, now \\ DateTime.utc_now()) do
    try do
      {doc, _rest} = :xmerl_scan.string(:binary.bin_to_list(body), quiet: true)

      items =
        case local_name(doc) do
          "rss" -> doc |> child("channel") |> children("item") |> Enum.map(&rss_item(&1, feed, now))
          "rdf" -> doc |> children("item") |> Enum.map(&rss_item(&1, feed, now))
          "feed" -> doc |> children("entry") |> Enum.map(&atom_item(&1, feed, now))
          other -> throw({:unsupported_feed, other})
        end

      {:ok, Enum.reject(items, &is_nil/1)}
    catch
      :exit, reason -> {:error, inspect(reason)}
      reason -> {:error, inspect(reason)}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  defp rss_item(node, feed, now) do
    title = node |> child("title") |> text() |> Util.clean_text()
    raw_content = first_text(node, ["encoded", "description"])
    content = Util.clean_text(raw_content)
    link = resolve_url(feed.url, node |> child("link") |> text())
    raw_id = first([node |> child("guid") |> text() |> String.trim(), link, title])

    if raw_id == "" do
      nil
    else
      published_at = first_text(node, ["pubDate", "date"]) |> Util.parse_date() || now
      author = first_text(node, ["creator", "author"]) |> Util.clean_text()
      categories = node |> children("category") |> Enum.map(&(text(&1) |> Util.clean_text()))
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

  defp atom_item(node, feed, now) do
    title = node |> child("title") |> text() |> Util.clean_text()
    raw_content = first_text(node, ["content", "summary"])
    content = Util.clean_text(raw_content)
    link = atom_link(node, feed.url)
    raw_id = first([node |> child("id") |> text() |> String.trim(), link, title])

    if raw_id == "" do
      nil
    else
      published_at = first_text(node, ["published", "updated"]) |> Util.parse_date() || now
      author = node |> child("author") |> child("name") |> text() |> Util.clean_text()
      categories = node |> children("category") |> Enum.map(&attr(&1, "term")) |> Enum.reject(&(&1 == ""))
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

  defp atom_link(node, base_url) do
    links = children(node, "link")

    preferred =
      Enum.find(links, fn link ->
        rel = attr(link, "rel")
        rel == "" or rel == "alternate"
      end) || List.first(links)

    preferred
    |> attr("href")
    |> then(&resolve_url(base_url, &1))
  end

  defp first_text(node, names) do
    names
    |> Enum.map(fn name -> node |> child(name) |> text() end)
    |> first()
  end

  defp first(values) do
    values
    |> Enum.map(&(to_string(&1) |> String.trim()))
    |> Enum.find("", &(&1 != ""))
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

  defp child(nil, _name), do: nil

  defp child(node, name) do
    node
    |> children(name)
    |> List.first()
  end

  defp children(nil, _name), do: []

  defp children(node, name) do
    node
    |> xmlElement(:content)
    |> Enum.filter(&element?/1)
    |> Enum.filter(&(local_name(&1) == name))
  end

  defp text(nil), do: ""

  defp text(node) do
    cond do
      text_node?(node) ->
        node |> xmlText(:value) |> to_string()

      element?(node) ->
        node |> xmlElement(:content) |> Enum.map_join(" ", &text/1)

      true ->
        ""
    end
  end

  defp attr(nil, _name), do: ""

  defp attr(node, name) do
    node
    |> xmlElement(:attributes)
    |> Enum.find(fn attribute -> local_name(attribute) == name end)
    |> case do
      nil -> ""
      attribute -> attribute |> xmlAttribute(:value) |> to_string()
    end
  end

  defp local_name(node) do
    name =
      cond do
        element?(node) -> xmlElement(node, :name)
        attribute?(node) -> xmlAttribute(node, :name)
        true -> ""
      end

    name
    |> name_to_string()
    |> String.split(":")
    |> List.last()
    |> String.downcase()
  end

  defp name_to_string({_namespace, local}), do: to_string(local)
  defp name_to_string(name), do: to_string(name)

  defp element?(node), do: Record.is_record(node, :xmlElement)
  defp text_node?(node), do: Record.is_record(node, :xmlText)
  defp attribute?(node), do: Record.is_record(node, :xmlAttribute)
end
