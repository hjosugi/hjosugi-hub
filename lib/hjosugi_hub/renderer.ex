defmodule HjosugiHub.Renderer do
  @moduledoc """
  Static site exporter for the hub.

  It renders EEx templates, public data files, feeds, health metadata, and
  static assets from validated site/feed config plus cached radar items.
  """

  require EEx

  alias HjosugiHub.{Config, HTML, Kofun, Store, Util}

  @template_dir Path.expand("../../priv/static_site/templates", __DIR__)
  @index_template Path.join(@template_dir, "index.html.eex")
  @radar_template Path.join(@template_dir, "radar.html.eex")
  @digest_template Path.join(@template_dir, "digest.html.eex")
  @gallery_template Path.join(@template_dir, "gallery.html.eex")
  @not_found_template Path.join(@template_dir, "404.html.eex")

  @external_resource @index_template
  @external_resource @radar_template
  @external_resource @digest_template
  @external_resource @gallery_template
  @external_resource @not_found_template

  @asset_dir Path.expand("../../priv/static_site/assets", __DIR__)
  @feed_item_limit 50
  @digest_week_count 4
  @digest_items_per_week 10
  @digest_window_seconds 7 * 24 * 60 * 60
  @og_image_path "static/og-image.svg"
  @stale_failure_threshold 7
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "base-uri 'none'",
                               "object-src 'none'",
                               "img-src 'self' https://github.com https://avatars.githubusercontent.com https://i.ytimg.com",
                               "script-src 'self'",
                               "style-src 'self'",
                               "connect-src 'self'",
                               "font-src 'self'",
                               "form-action 'self'"
                             ],
                             "; "
                           )

  EEx.function_from_file(:defp, :index_template, @index_template, [:assigns], [])
  EEx.function_from_file(:defp, :radar_template, @radar_template, [:assigns], [])
  EEx.function_from_file(:defp, :digest_template, @digest_template, [:assigns], [])
  EEx.function_from_file(:defp, :gallery_template, @gallery_template, [:assigns], [])
  EEx.function_from_file(:defp, :not_found_template, @not_found_template, [:assigns], [])

  def export(site, feeds, items, out_dir, base_url \\ "", opts \\ []) do
    asset_version = asset_version()
    public_feeds = enabled_public_feeds(feeds)
    public_items = public_items(items, public_feeds)
    assigns = build_assigns(site, public_feeds, public_items, base_url, asset_version)
    collection_report = Keyword.get(opts, :collection_report, %{})
    feed_state = Keyword.get(opts, :feed_state, %{})

    write_rendered(out_dir, "index.html", :index, page_assigns(assigns, :index))
    write_radar_pages(out_dir, assigns)
    write_digest_page(out_dir, assigns)

    write_rendered(
      Path.join(out_dir, "friends"),
      "index.html",
      :gallery,
      page_assigns(assigns, :friends, %{root: "../"})
    )

    write_rendered(
      out_dir,
      "404.html",
      :not_found,
      page_assigns(assigns, :not_found, %{root: not_found_root(assigns.base_url)})
    )

    remove_legacy_public_data(out_dir)
    Store.write_json(Path.join(out_dir, "radar-data/items.json"), public_items)
    Store.write_json(Path.join(out_dir, "radar-data/site.json"), site)
    Store.write_json(Path.join(out_dir, "radar-data/feeds.json"), public_feeds_json(public_feeds))
    File.write!(Path.join(out_dir, "feeds.opml"), feeds_opml(site, public_feeds))
    File.write!(Path.join(out_dir, "radar.xml"), atom_feed(assigns, public_items))
    Store.write_json(Path.join(out_dir, "feed.json"), json_feed(assigns, public_items))

    Store.write_json(
      Path.join(out_dir, "health.json"),
      health(assigns, public_items, collection_report, feed_state, public_feeds)
    )

    copy_assets(out_dir, asset_version)
    File.write!(Path.join(out_dir, "static/favicon.svg"), Kofun.favicon_svg())
    File.write!(Path.join(out_dir, @og_image_path), og_image_svg(site))
    File.write!(Path.join(out_dir, ".nojekyll"), "")
    File.write!(Path.join(out_dir, "robots.txt"), robots(assigns.base_url))

    if assigns.base_url != "" do
      File.write!(Path.join(out_dir, "sitemap.xml"), sitemap(assigns.base_url))
    end

    :ok
  end

  defp remove_legacy_public_data(out_dir) do
    out_dir
    |> Path.join("data")
    |> File.rm_rf!()
  end

  defp public_items(items, feeds) do
    enabled_source_ids = MapSet.new(feeds, & &1.id)
    weights = Map.new(feeds, fn feed -> {feed.id, Config.feed_weight(feed)} end)

    items
    |> Enum.filter(&MapSet.member?(enabled_source_ids, &1.source_id))
    |> Store.public_items()
    |> Enum.map(fn item -> Map.put(item, :weight, Map.fetch!(weights, item.source_id)) end)
  end

  defp build_assigns(site, feeds, public_items, base_url, asset_version) do
    now = DateTime.utc_now()

    %{
      site: site,
      feeds: feeds,
      enabled_feeds: length(feeds),
      featured: Enum.filter(Map.get(site, :projects, []), &Map.get(&1, :featured, false)),
      others: Enum.reject(Map.get(site, :projects, []), &Map.get(&1, :featured, false)),
      avatar_url: Config.avatar_url(site),
      kofun: Kofun.pet_html(),
      items: public_items,
      digest_sections: digest_sections(public_items, now),
      generated_at: now,
      generated_text: Calendar.strftime(now, "%Y-%m-%d %H:%M UTC"),
      year: now.year,
      base_url: String.trim_trailing(base_url || "", "/"),
      asset_version: asset_version,
      content_security_policy: @content_security_policy
    }
  end

  # The radar template backs two separate pages: /radar/ (the full searchable
  # reading list) and /popular/ (a GitHub-picks page scoped to github.com
  # links). `root` is the relative path back to the site root.
  @radar_pages [
    {"radar", "all", "../"},
    {"popular", "github", "../"}
  ]

  defp write_radar_pages(out_dir, assigns) do
    Enum.each(@radar_pages, fn {path, category, root} ->
      page = if category == "github", do: :popular, else: :radar
      scoped = page_assigns(assigns, page, %{category: category, root: root})
      write_rendered(Path.join(out_dir, path), "index.html", :radar, scoped)
    end)
  end

  defp write_digest_page(out_dir, assigns) do
    write_rendered(
      Path.join(out_dir, "digest"),
      "index.html",
      :digest,
      page_assigns(assigns, :digest, %{root: "../"})
    )
  end

  defp write_rendered(dir, file, template, assigns) do
    File.mkdir_p!(dir)
    html = render_template(template, assigns)
    File.write!(Path.join(dir, file), html)
  end

  defp render_template(:index, assigns), do: index_template(assigns)
  defp render_template(:radar, assigns), do: radar_template(assigns)
  defp render_template(:digest, assigns), do: digest_template(assigns)
  defp render_template(:gallery, assigns), do: gallery_template(assigns)
  defp render_template(:not_found, assigns), do: not_found_template(assigns)

  defp page_assigns(assigns, page, overrides \\ %{}) do
    assigns = Map.merge(assigns, overrides)
    Map.put(assigns, :page, page_metadata(assigns, page))
  end

  defp page_metadata(assigns, :index) do
    site = assigns.site

    build_page_metadata(assigns, %{
      path: "",
      title: "#{site.handle} - #{site.headline}",
      description: site_description(site)
    })
  end

  defp page_metadata(assigns, :radar) do
    build_page_metadata(assigns, %{
      path: "radar/",
      title: "Technical radar - #{assigns.site.handle}",
      description: radar_description(assigns.site)
    })
  end

  defp page_metadata(assigns, :popular) do
    build_page_metadata(assigns, %{
      path: "popular/",
      title: "Popular on GitHub - #{assigns.site.handle}",
      description: "GitHub links surfaced on #{assigns.site.handle}'s technical radar."
    })
  end

  defp page_metadata(assigns, :digest) do
    build_page_metadata(assigns, %{
      path: "digest/",
      title: "Weekly digest - #{assigns.site.handle}",
      description:
        "Top recent radar items ranked by score multiplied by feed weight for #{assigns.site.handle}."
    })
  end

  defp page_metadata(assigns, :friends) do
    build_page_metadata(assigns, %{
      path: "friends/",
      title: "friends - #{assigns.site.handle}",
      description:
        "Meet Kofun-kun and Dochicken-san, the pixel mascots of #{assigns.site.handle}."
    })
  end

  defp page_metadata(assigns, :not_found) do
    build_page_metadata(assigns, %{
      path: "404.html",
      title: "404 - #{assigns.site.handle}",
      description: "Page not found on #{assigns.site.handle}."
    })
  end

  defp build_page_metadata(assigns, metadata) do
    metadata
    |> Map.put(:url, absolute_url(assigns.base_url, metadata.path))
    |> Map.put(:image_url, absolute_url(assigns.base_url, @og_image_path))
    |> Map.put(:image_alt, "#{Map.get(assigns.site, :display_name, assigns.site.handle)} mascot")
    |> Map.put(:feed_title, radar_feed_title(assigns.site))
    |> Map.put(:atom_feed_url, public_href(assigns, "radar.xml"))
    |> Map.put(:json_feed_url, public_href(assigns, "feed.json"))
  end

  defp site_description(site) do
    site
    |> Map.get(:about, Map.get(site, :headline, ""))
    |> Util.summarize(220)
  end

  defp radar_description(site),
    do: "Search collected technical reading items from #{site.handle}."

  defp absolute_url("", _path), do: ""

  defp absolute_url(base_url, path) do
    path = String.trim_leading(path, "/")

    if path == "" do
      base_url <> "/"
    else
      base_url <> "/" <> path
    end
  end

  defp public_href(%{base_url: base_url}, path) when base_url != "",
    do: absolute_url(base_url, path)

  defp public_href(assigns, path) do
    Map.get(assigns, :root, "") <> path
  end

  defp social_meta_tags(page) do
    [
      meta_property("og:title", page.title),
      meta_property("og:description", page.description),
      meta_property("og:type", "website"),
      meta_property("og:url", page.url),
      meta_property("og:image", page.image_url),
      meta_property("og:image:type", if(page.image_url == "", do: "", else: "image/svg+xml")),
      meta_property("og:image:width", if(page.image_url == "", do: "", else: "1200")),
      meta_property("og:image:height", if(page.image_url == "", do: "", else: "630")),
      meta_property("og:image:alt", if(page.image_url == "", do: "", else: page.image_alt)),
      meta_name("twitter:card", "summary"),
      meta_name("twitter:title", page.title),
      meta_name("twitter:description", page.description),
      meta_name("twitter:image", page.image_url),
      meta_name("twitter:image:alt", if(page.image_url == "", do: "", else: page.image_alt))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n  ")
  end

  defp feed_discovery_tags(page) do
    [
      link_tag(
        "alternate",
        "application/atom+xml",
        "#{page.feed_title} Atom feed",
        page.atom_feed_url
      ),
      link_tag(
        "alternate",
        "application/feed+json",
        "#{page.feed_title} JSON feed",
        page.json_feed_url
      )
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n  ")
  end

  defp canonical_link_tag(%{url: ""}), do: ""
  defp canonical_link_tag(page), do: ~s(<link rel="canonical" href="#{HTML.escape(page.url)}">)

  defp meta_property(_property, nil), do: ""
  defp meta_property(_property, ""), do: ""

  defp meta_property(property, content) do
    ~s(<meta property="#{HTML.escape(property)}" content="#{HTML.escape(content)}">)
  end

  defp meta_name(_name, nil), do: ""
  defp meta_name(_name, ""), do: ""

  defp meta_name(name, content) do
    ~s(<meta name="#{HTML.escape(name)}" content="#{HTML.escape(content)}">)
  end

  defp link_tag(_rel, _type, _title, nil), do: ""
  defp link_tag(_rel, _type, _title, ""), do: ""

  defp link_tag(rel, type, title, href) do
    ~s(<link rel="#{HTML.escape(rel)}" type="#{HTML.escape(type)}" title="#{HTML.escape(title)}" href="#{HTML.escape(href)}">)
  end

  defp not_found_root(""), do: "./"

  defp not_found_root(base_url) do
    path =
      base_url
      |> URI.parse()
      |> Map.get(:path)
      |> to_string()
      |> String.trim_trailing("/")

    if path == "", do: "/", else: path <> "/"
  end

  defp copy_assets(out_dir, version) do
    target = Path.join(out_dir, "static")
    File.mkdir_p!(target)

    @asset_dir
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      dest = Path.join(target, Path.basename(path))

      if String.ends_with?(path, ".js") do
        File.write!(dest, version_imports(File.read!(path), version))
      else
        File.cp!(path, dest)
      end
    end)
  end

  # Cache-busting version derived from the static bundle's content. It changes
  # only when an asset changes (data-only refreshes keep it stable), so a deploy
  # is guaranteed to be reflected without re-downloading unchanged assets.
  defp asset_version do
    @asset_dir
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map_join("\n", &File.read!/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  # ES module imports resolve by URL, so relative `import ... from "./x.js"`
  # specifiers need the same version query as the HTML <script> tags; otherwise
  # a changed sub-module could still be served from cache.
  @import_re ~r/(\bfrom\s*["']|\bimport\(\s*["'])(\.{1,2}\/[^"']+\.js)(["'])/
  defp version_imports(js, version) do
    Regex.replace(@import_re, js, fn _full, prefix, spec, quote ->
      prefix <> spec <> "?v=" <> version <> quote
    end)
  end

  defp enabled_public_feeds(feeds) do
    feeds
    |> Enum.filter(&(Map.get(&1, :enabled, true) && Map.get(&1, :public, true)))
    |> Enum.sort_by(&Map.get(&1, :name, ""))
  end

  defp public_feeds_json(feeds) do
    feeds
    |> Enum.map(&Map.take(&1, [:id, :name, :kind, :enabled, :tags]))
  end

  defp feeds_opml(site, feeds) do
    outlines = Enum.map_join(feeds, "\n", &feed_outline/1)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>#{xml_attr(Map.get(site, :handle, "hjosugi-hub"))} feeds</title>
      </head>
      <body>
    #{outlines}
      </body>
    </opml>
    """
    |> String.trim_leading()
  end

  defp atom_feed(assigns, public_items) do
    items = feed_items(public_items)
    updated_at = feed_updated_at(assigns, items)
    entries = Enum.map_join(items, "\n", &atom_entry/1)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>#{xml_text(radar_feed_title(assigns.site))}</title>
      <subtitle>#{xml_text(radar_description(assigns.site))}</subtitle>
      <id>#{xml_text(feed_id(assigns))}</id>
      #{atom_feed_links(assigns)}
      <updated>#{datetime_iso8601(updated_at)}</updated>
      <author><name>#{xml_text(author_name(assigns.site))}</name></author>
    #{entries}
    </feed>
    """
    |> String.trim_leading()
  end

  defp atom_feed_links(%{base_url: ""}), do: ""

  defp atom_feed_links(assigns) do
    [
      atom_link("alternate", "text/html", absolute_url(assigns.base_url, "radar/")),
      atom_link("self", "application/atom+xml", absolute_url(assigns.base_url, "radar.xml"))
    ]
    |> Enum.join("\n  ")
  end

  defp atom_link(_rel, _type, ""), do: ""

  defp atom_link(rel, type, href) do
    ~s(<link rel="#{xml_attr(rel)}" type="#{xml_attr(type)}" href="#{xml_attr(href)}"/>)
  end

  defp atom_entry(item) do
    title = item_title(item)
    url = item_url(item)
    summary = item_summary(item)
    updated_at = item_datetime(item)

    """
      <entry>
        <title>#{xml_text(title)}</title>
        <id>#{xml_text(item_feed_id(item))}</id>
        <updated>#{datetime_iso8601(updated_at)}</updated>
    #{atom_published(item)}
    #{atom_item_link(url)}
        <summary type="text">#{xml_text(summary)}</summary>
    #{atom_item_author(item)}
    #{atom_categories(item)}
      </entry>
    """
    |> String.trim_trailing()
  end

  defp atom_published(%{published_at: %DateTime{} = published_at}) do
    "    <published>#{datetime_iso8601(published_at)}</published>"
  end

  defp atom_published(_item), do: ""

  defp atom_item_link(""), do: ""

  defp atom_item_link(url) do
    ~s(    <link rel="alternate" type="text/html" href="#{xml_attr(url)}"/>)
  end

  defp atom_item_author(item) do
    case non_empty_string(Map.get(item, :author)) do
      "" -> ""
      author -> "    <author><name>#{xml_text(author)}</name></author>"
    end
  end

  defp atom_categories(item) do
    item
    |> item_tags()
    |> Enum.map_join("\n", fn tag -> ~s(    <category term="#{xml_attr(tag)}"/>) end)
  end

  defp json_feed(assigns, public_items) do
    %{
      version: "https://jsonfeed.org/version/1.1",
      title: radar_feed_title(assigns.site),
      description: radar_description(assigns.site),
      language: "en",
      authors: [%{name: author_name(assigns.site)}],
      items: Enum.map(feed_items(public_items), &json_feed_item/1)
    }
    |> put_non_empty(:home_page_url, absolute_url(assigns.base_url, "radar/"))
    |> put_non_empty(:feed_url, absolute_url(assigns.base_url, "feed.json"))
    |> put_non_empty(:icon, absolute_url(assigns.base_url, @og_image_path))
    |> put_non_empty(:favicon, absolute_url(assigns.base_url, "static/favicon.svg"))
  end

  defp json_feed_item(item) do
    summary = item_summary(item)

    %{
      id: item_feed_id(item),
      title: item_title(item),
      content_text: summary,
      summary: summary,
      date_modified: datetime_iso8601(item_datetime(item)),
      tags: item_tags(item)
    }
    |> put_non_empty(:url, item_url(item))
    |> put_non_empty(:date_published, datetime_iso8601(Map.get(item, :published_at)))
    |> put_non_empty(:authors, json_item_authors(item))
  end

  defp json_item_authors(item) do
    case non_empty_string(Map.get(item, :author)) do
      "" -> nil
      author -> [%{name: author}]
    end
  end

  defp digest_sections(public_items, generated_at) do
    0..(@digest_week_count - 1)
    |> Enum.map(&digest_section(public_items, generated_at, &1))
    |> Enum.reject(&(Map.get(&1, :items) == []))
  end

  defp digest_section(public_items, generated_at, index) do
    end_at = DateTime.add(generated_at, -index * @digest_window_seconds, :second)
    start_at = DateTime.add(end_at, -@digest_window_seconds, :second)

    items =
      public_items
      |> Enum.filter(&scored_digest_item?/1)
      |> Enum.filter(&(digest_window_index(&1, generated_at) == index))
      |> rank_digest_items()
      |> Enum.take(@digest_items_per_week)
      |> Enum.with_index(1)
      |> Enum.map(fn {item, rank} -> digest_entry(item, rank) end)

    %{
      index: index,
      label: digest_section_label(index),
      period: "#{digest_date(start_at)} - #{digest_date(end_at)} UTC",
      items: items
    }
  end

  defp scored_digest_item?(item), do: is_number(Map.get(item, :score))

  defp digest_window_index(item, generated_at) do
    diff = DateTime.diff(generated_at, item_datetime(item), :second)

    cond do
      diff < 0 -> nil
      diff >= @digest_week_count * @digest_window_seconds -> nil
      true -> div(diff, @digest_window_seconds)
    end
  end

  defp rank_digest_items(items) do
    Enum.sort_by(items, fn item ->
      {
        -digest_rank_score(item),
        -Map.get(item, :score),
        -DateTime.to_unix(item_datetime(item)),
        String.downcase(item_title(item)),
        non_empty_string(Map.get(item, :source_id)),
        non_empty_string(Map.get(item, :id)),
        item_url(item)
      }
    end)
  end

  defp digest_entry(item, rank) do
    %{
      rank: rank,
      title: item_title(item),
      url: item_url(item),
      summary: item_summary(item),
      source_name: digest_source_name(item),
      tags: item_tags(item),
      item_date: digest_date(item_datetime(item)),
      score: Map.get(item, :score),
      weight: digest_weight(item),
      rank_score: digest_rank_score(item)
    }
  end

  defp digest_source_name(item) do
    case non_empty_string(Map.get(item, :source_name)) do
      "" -> non_empty_string(Map.get(item, :source_id))
      source_name -> source_name
    end
  end

  defp digest_section_label(0), do: "Last 7 days"

  defp digest_section_label(index) do
    "#{index * 7 + 1}-#{(index + 1) * 7} days ago"
  end

  defp digest_rank_score(item), do: Map.get(item, :score) * digest_weight(item)

  defp digest_weight(item) do
    case Map.get(item, :weight) do
      weight when is_number(weight) -> weight
      _ -> 1.0
    end
  end

  defp digest_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")
  defp digest_date(_datetime), do: ""

  defp format_digest_number(number) when is_integer(number), do: Integer.to_string(number)

  defp format_digest_number(number) when is_float(number) do
    number
    |> :erlang.float_to_binary(decimals: 1)
    |> String.replace_suffix(".0", "")
  end

  defp format_digest_number(number), do: to_string(number)

  defp feed_items(public_items) do
    public_items
    |> Enum.sort_by(&DateTime.to_unix(item_datetime(&1)), :desc)
    |> Enum.take(@feed_item_limit)
  end

  defp feed_updated_at(assigns, []), do: assigns.generated_at
  defp feed_updated_at(_assigns, [item | _items]), do: item_datetime(item)

  defp feed_id(%{base_url: ""} = assigns) do
    stable_urn("feed", Map.get(assigns.site, :handle, "hjosugi-hub"))
  end

  defp feed_id(assigns), do: absolute_url(assigns.base_url, "radar/")

  defp item_feed_id(item) do
    seed =
      [
        Map.get(item, :source_id),
        Map.get(item, :id),
        Map.get(item, :normalized_url),
        Map.get(item, :url),
        Map.get(item, :title)
      ]
      |> Enum.map(&non_empty_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(<<0>>)

    stable_urn("item", seed)
  end

  defp stable_urn(type, seed) do
    digest =
      :crypto.hash(:sha256, non_empty_string(seed))
      |> binary_part(0, 16)
      |> Base.encode16(case: :lower)

    "urn:hjosugi-hub:#{type}:#{digest}"
  end

  defp item_datetime(%{published_at: %DateTime{} = published_at}), do: published_at
  defp item_datetime(%{collected_at: %DateTime{} = collected_at}), do: collected_at
  defp item_datetime(_item), do: DateTime.from_unix!(0)

  defp datetime_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp datetime_iso8601(_datetime), do: nil

  defp item_title(item) do
    item
    |> Map.get(:title)
    |> non_empty_string()
    |> case do
      "" -> "Untitled radar item"
      title -> title
    end
  end

  defp item_url(item) do
    item
    |> Map.get(:url)
    |> non_empty_string()
  end

  defp item_summary(item) do
    summary = Map.get(item, :summary) || Map.get(item, :content) || ""

    Util.summarize(summary, 500)
  end

  defp item_tags(item) do
    item
    |> Map.get(:tags, [])
    |> Enum.map(&Util.normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp radar_feed_title(site) do
    case non_empty_string(Map.get(site, :handle)) do
      "" -> "hjosugi-hub radar"
      handle -> "#{handle} radar"
    end
  end

  defp author_name(site) do
    case non_empty_string(Map.get(site, :display_name)) do
      "" ->
        case non_empty_string(Map.get(site, :handle)) do
          "" -> "hjosugi"
          handle -> handle
        end

      name ->
        name
    end
  end

  defp og_image_svg(site) do
    mascot =
      Kofun.favicon_svg()
      |> String.replace("<svg ", ~s(<svg x="92" y="135" width="360" height="360" ))
      |> String.trim()

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" role="img" aria-label="#{xml_attr(radar_feed_title(site))}">
      <rect width="1200" height="630" fill="#08110f"/>
      <rect x="64" y="64" width="1072" height="502" rx="40" fill="#10231d" stroke="#62d39c" stroke-width="6"/>
      <circle cx="988" cy="152" r="50" fill="#62d39c" opacity="0.16"/>
      <circle cx="1048" cy="222" r="32" fill="#f8c86a" opacity="0.22"/>
      #{mascot}
      <text x="500" y="270" fill="#f5fff9" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="82" font-weight="700">#{xml_text(Map.get(site, :handle, "hjosugi-hub"))}</text>
      <text x="504" y="342" fill="#62d39c" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="34">~/radar</text>
      <text x="504" y="414" fill="#d9f8e8" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="36">#{xml_text(Util.truncate(Map.get(site, :headline, "Technical radar"), 64))}</text>
    </svg>
    """
    |> String.trim_leading()
  end

  defp feed_outline(feed) do
    name = xml_attr(Map.get(feed, :name, Map.get(feed, :id, "")))
    kind = xml_attr(Map.get(feed, :kind, "rss"))
    url = xml_attr(Map.get(feed, :url, ""))

    ~s(    <outline text="#{name}" title="#{name}" type="rss" xmlUrl="#{url}" category="#{kind}" kind="#{kind}"/>)
  end

  defp xml_attr(value), do: HTML.escape(value)
  defp xml_text(value), do: HTML.escape(value)

  defp non_empty_string(nil), do: ""

  defp non_empty_string(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp put_non_empty(map, _key, nil), do: map
  defp put_non_empty(map, _key, ""), do: map
  defp put_non_empty(map, _key, []), do: map
  defp put_non_empty(map, key, value), do: Map.put(map, key, value)

  defp robots(""), do: "User-agent: *\nAllow: /\n"
  defp robots(base_url), do: "User-agent: *\nAllow: /\nSitemap: #{base_url}/sitemap.xml\n"

  defp health(assigns, public_items, collection_report, feed_state, feeds) do
    collection = collection_health(collection_report, feed_state, feeds)

    %{
      status: collection.status,
      service: "hjosugi-hub",
      generated_at: DateTime.to_iso8601(assigns.generated_at),
      generated_text: assigns.generated_text,
      enabled_feeds: assigns.enabled_feeds,
      item_count: length(public_items),
      asset_version: assigns.asset_version,
      collection_status: collection.collection_status,
      collection_started_at: collection.started_at,
      collection_finished_at: collection.finished_at,
      fresh_items: collection.fresh_items,
      successful_sources: collection.successful_sources,
      failed_sources: collection.failed_sources,
      failing_sources: collection.failing_sources,
      stale_sources: collection.stale_sources,
      warnings: collection.warnings
    }
  end

  defp collection_health(report, feed_state, feeds) do
    enabled_feed_ids = MapSet.new(feeds, & &1.id)
    state_sources = enabled_feed_state(feed_state, enabled_feed_ids)
    report_sources = list_value(report, :sources)

    failed_from_state = Enum.count(state_sources, &(string_value(&1, :last_status) == "error"))
    stale_from_state = Enum.count(state_sources, &stale_feed_state?/1)

    failed_from_report =
      integer_value(report, :failed_sources) || count_status(report_sources, "error")

    stale_from_report = integer_value(report, :stale_sources) || count_stale(report_sources)
    failed_sources = failed_from_report || failed_from_state
    stale_sources = stale_from_report || stale_from_state
    failing_sources = max(failed_sources, failed_from_state)

    collection_status =
      string_value(report, :status) ||
        derived_collection_status(report, failed_sources, stale_sources)

    warnings = public_warnings(report) ++ derived_warnings(report, failed_sources, stale_sources)

    %{
      status: health_status(collection_status, failing_sources, stale_sources),
      collection_status: collection_status,
      started_at: isoish_value(report, :started_at),
      finished_at: isoish_value(report, :finished_at),
      fresh_items: integer_value(report, :fresh_items),
      successful_sources: integer_value(report, :successful_sources),
      failed_sources: failed_sources,
      failing_sources: failing_sources,
      stale_sources: stale_sources,
      warnings: warnings
    }
  end

  defp enabled_feed_state(feed_state, enabled_feed_ids) when is_map(feed_state) do
    feed_state
    |> Enum.filter(fn {feed_id, _state} ->
      MapSet.member?(enabled_feed_ids, to_string(feed_id))
    end)
    |> Enum.map(fn {_feed_id, state} -> state end)
    |> Enum.filter(&is_map/1)
  end

  defp enabled_feed_state(_feed_state, _enabled_feed_ids), do: []

  defp stale_feed_state?(state) do
    string_value(state, :last_status) == "error" and
      (integer_value(state, :consecutive_failures) || 0) >= @stale_failure_threshold
  end

  defp count_status(sources, status) do
    case Enum.count(sources, &(string_value(&1, :status) == status)) do
      0 -> nil
      count -> count
    end
  end

  defp count_stale(sources) do
    case Enum.count(sources, &truthy_value?(&1, :stale)) do
      0 -> nil
      count -> count
    end
  end

  defp derived_collection_status(report, failed_sources, stale_sources) do
    cond do
      report == %{} and failed_sources == 0 and stale_sources == 0 -> nil
      failed_sources > 0 or stale_sources > 0 -> "warning"
      true -> "ok"
    end
  end

  defp health_status("critical", _failing_sources, _stale_sources), do: "critical"

  defp health_status(_collection_status, failing_sources, stale_sources)
       when failing_sources > 0 or stale_sources > 0,
       do: "warning"

  defp health_status(collection_status, _failing_sources, _stale_sources),
    do: collection_status || "ok"

  defp public_warnings(report) do
    report
    |> list_value(:warnings)
    |> Enum.map(fn warning ->
      %{
        code: string_value(warning, :code),
        count: integer_value(warning, :count),
        message: string_value(warning, :message)
      }
    end)
  end

  defp derived_warnings(report, failed_sources, stale_sources) do
    if list_value(report, :warnings) == [] do
      []
      |> maybe_warning(failed_sources > 0, %{
        code: "feed_failures",
        count: failed_sources,
        message: "#{failed_sources} feed(s) failed during collection."
      })
      |> maybe_warning(stale_sources > 0, %{
        code: "stale_feeds",
        count: stale_sources,
        message: "#{stale_sources} feed(s) reached the consecutive failure threshold."
      })
      |> Enum.reverse()
    else
      []
    end
  end

  defp maybe_warning(warnings, true, warning), do: [warning | warnings]
  defp maybe_warning(warnings, false, _warning), do: warnings

  defp list_value(map, key) do
    case value(map, key) do
      value when is_list(value) -> value
      _ -> []
    end
  end

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      _ -> nil
    end
  end

  defp isoish_value(map, key) do
    case value(map, key) do
      %DateTime{} = value -> DateTime.to_iso8601(value)
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp integer_value(map, key) do
    case value(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp truthy_value?(map, key), do: value(map, key) in [true, "true"]

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp value(_map, _key), do: nil

  defp sitemap(base_url) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url><loc>#{base_url}/</loc></url>
      <url><loc>#{base_url}/radar/</loc></url>
      <url><loc>#{base_url}/popular/</loc></url>
      <url><loc>#{base_url}/digest/</loc></url>
      <url><loc>#{base_url}/friends/</loc></url>
    </urlset>
    """
    |> String.trim_leading()
  end
end
