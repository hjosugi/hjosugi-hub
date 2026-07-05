defmodule HjosugiHub.Renderer do
  @moduledoc false

  require EEx

  alias HjosugiHub.{Config, HTML, Kofun, Store}

  @template_dir Path.expand("../../priv/static_site/templates", __DIR__)
  @index_template Path.join(@template_dir, "index.html.eex")
  @radar_template Path.join(@template_dir, "radar.html.eex")
  @gallery_template Path.join(@template_dir, "gallery.html.eex")
  @not_found_template Path.join(@template_dir, "404.html.eex")

  @external_resource @index_template
  @external_resource @radar_template
  @external_resource @gallery_template
  @external_resource @not_found_template

  @asset_dir Path.expand("../../priv/static_site/assets", __DIR__)
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "base-uri 'none'",
                               "object-src 'none'",
                               "img-src 'self' https://github.com https://avatars.githubusercontent.com",
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
  EEx.function_from_file(:defp, :gallery_template, @gallery_template, [:assigns], [])
  EEx.function_from_file(:defp, :not_found_template, @not_found_template, [:assigns], [])

  def export(site, feeds, items, out_dir, base_url \\ "") do
    asset_version = asset_version()
    public_feeds = enabled_public_feeds(feeds)
    public_items = public_items(items, public_feeds)
    assigns = build_assigns(site, public_feeds, public_items, base_url, asset_version)

    write_rendered(out_dir, "index.html", :index, assigns)
    write_radar_pages(out_dir, assigns)

    write_rendered(
      Path.join(out_dir, "friends"),
      "index.html",
      :gallery,
      Map.put(assigns, :root, "../")
    )

    write_rendered(
      out_dir,
      "404.html",
      :not_found,
      Map.put(assigns, :root, not_found_root(assigns.base_url))
    )

    remove_legacy_public_data(out_dir)
    Store.write_json(Path.join(out_dir, "radar-data/items.json"), public_items)
    Store.write_json(Path.join(out_dir, "radar-data/site.json"), site)
    Store.write_json(Path.join(out_dir, "radar-data/feeds.json"), public_feeds_json(public_feeds))
    File.write!(Path.join(out_dir, "feeds.opml"), feeds_opml(site, public_feeds))
    Store.write_json(Path.join(out_dir, "health.json"), health(assigns, public_items))
    copy_assets(out_dir, asset_version)
    File.write!(Path.join(out_dir, "static/favicon.svg"), Kofun.favicon_svg())
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
      scoped = Map.merge(assigns, %{category: category, root: root})
      write_rendered(Path.join(out_dir, path), "index.html", :radar, scoped)
    end)
  end

  defp write_rendered(dir, file, template, assigns) do
    File.mkdir_p!(dir)
    html = render_template(template, assigns)
    File.write!(Path.join(dir, file), html)
  end

  defp render_template(:index, assigns), do: index_template(assigns)
  defp render_template(:radar, assigns), do: radar_template(assigns)
  defp render_template(:gallery, assigns), do: gallery_template(assigns)
  defp render_template(:not_found, assigns), do: not_found_template(assigns)

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

  defp feed_outline(feed) do
    name = xml_attr(Map.get(feed, :name, Map.get(feed, :id, "")))
    kind = xml_attr(Map.get(feed, :kind, "rss"))
    url = xml_attr(Map.get(feed, :url, ""))

    ~s(    <outline text="#{name}" title="#{name}" type="rss" xmlUrl="#{url}" category="#{kind}" kind="#{kind}"/>)
  end

  defp xml_attr(value), do: HTML.escape(value)

  defp robots(""), do: "User-agent: *\nAllow: /\n"
  defp robots(base_url), do: "User-agent: *\nAllow: /\nSitemap: #{base_url}/sitemap.xml\n"

  defp health(assigns, public_items) do
    %{
      status: "ok",
      service: "hjosugi-hub",
      generated_at: assigns.generated_text,
      enabled_feeds: assigns.enabled_feeds,
      item_count: length(public_items),
      asset_version: assigns.asset_version
    }
  end

  defp sitemap(base_url) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url><loc>#{base_url}/</loc></url>
      <url><loc>#{base_url}/radar/</loc></url>
      <url><loc>#{base_url}/popular/</loc></url>
      <url><loc>#{base_url}/friends/</loc></url>
    </urlset>
    """
    |> String.trim_leading()
  end
end
