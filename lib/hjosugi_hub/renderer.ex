defmodule HjosugiHub.Renderer do
  @moduledoc """
  Static site exporter for the hub.

  It renders the EEx page templates and writes them to the output directory
  together with the public radar data, feeds, health metadata, and static
  assets. Everything is derived from validated site/feed config plus cached
  radar items.
  """

  require EEx

  alias HjosugiHub.{Config, Digest, Health, HTML, Kofun, Store, Syndication, Util}

  @template_dir Path.expand("../../priv/static_site/templates", __DIR__)
  @asset_dir Path.expand("../../priv/static_site/assets", __DIR__)
  @recent_days 30
  @favicon_path "static/favicon.svg"
  @og_image_path "static/og-image.svg"
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

  # Pages listed in the primary navigation and the sitemap, as {page id, path}.
  @nav_pages [radar: "radar/", popular: "popular/", digest: "digest/", friends: "friends/"]
  @radar_footer "RSS data is refreshed by GitHub Actions"

  # `layout` is the shared document chrome (head, site header, footer); every
  # other template renders only its page's <main> and is wrapped by it.
  for {name, file} <- [
        layout: "layout",
        index: "index",
        radar: "radar",
        digest: "digest",
        friends: "friends",
        not_found: "404"
      ] do
    EEx.function_from_file(
      :defp,
      :"#{name}_template",
      Path.join(@template_dir, "#{file}.html.eex"),
      [:assigns]
    )
  end

  def export(site, feeds, items, out_dir, base_url \\ "", opts \\ []) do
    public_feeds = enabled_public_feeds(feeds)
    public_items = public_items(items, public_feeds)
    assigns = build_assigns(site, public_feeds, public_items, base_url)

    write_pages(out_dir, assigns)
    write_radar_data(out_dir, assigns)
    write_feeds(out_dir, assigns)
    write_health(out_dir, assigns, opts)
    write_static_files(out_dir, assigns)
    :ok
  end

  defp enabled_public_feeds(feeds) do
    feeds
    |> Enum.filter(&(Map.get(&1, :enabled, true) && Map.get(&1, :public, true)))
    |> Enum.sort_by(&Map.get(&1, :name, ""))
  end

  defp public_items(items, feeds) do
    weights = Map.new(feeds, fn feed -> {feed.id, Config.feed_weight(feed)} end)

    items
    |> Enum.filter(&Map.has_key?(weights, &1.source_id))
    |> Store.public_items()
    |> Enum.map(fn item -> Map.put(item, :weight, Map.fetch!(weights, item.source_id)) end)
  end

  defp build_assigns(site, feeds, public_items, base_url) do
    now = DateTime.utc_now()

    %{
      site: site,
      feeds: feeds,
      enabled_feeds: length(feeds),
      projects: featured_first(Map.get(site, :projects, [])),
      avatar_url: Config.avatar_url(site),
      kofun: Kofun.pet_html(),
      items: public_items,
      digest_sections: Digest.sections(public_items, now),
      generated_at: now,
      generated_text: Calendar.strftime(now, "%Y-%m-%d %H:%M UTC"),
      year: now.year,
      base_url: String.trim_trailing(base_url || "", "/"),
      asset_version: asset_version(),
      content_security_policy: @content_security_policy
    }
  end

  defp featured_first(projects) do
    {featured, others} = Enum.split_with(projects, &Map.get(&1, :featured, false))
    featured ++ others
  end

  # Pages

  defp write_pages(out_dir, assigns) do
    write_page(out_dir, assigns, :index, &index_template/1)

    # The radar template backs two pages: /radar/ lists everything and
    # /popular/ is scoped to github.com links.
    write_page(out_dir, assigns, :radar, &radar_template/1, radar_scope(assigns, "all"))
    write_page(out_dir, assigns, :popular, &radar_template/1, radar_scope(assigns, "github"))

    write_page(out_dir, assigns, :digest, &digest_template/1)
    write_page(out_dir, assigns, :friends, &friends_template/1)

    # GitHub Pages serves 404.html for any missing path at any depth, so its
    # links are rooted at the site path instead of being relative.
    not_found_root = %{root: not_found_root(assigns.base_url)}
    write_page(out_dir, assigns, :not_found, &not_found_template/1, not_found_root)
  end

  defp write_page(out_dir, assigns, page, template, overrides \\ %{}) do
    assigns = page_assigns(assigns, page, overrides)
    file = Path.join(out_dir, page_file(assigns.page.path))
    content = assigns |> template.() |> String.trim()

    File.mkdir_p!(Path.dirname(file))
    File.write!(file, layout_template(Map.put(assigns, :content, content)))
  end

  # Directory-style paths ("radar/") are written as that directory's index.html.
  defp page_file(path) do
    if path == "" or String.ends_with?(path, "/"), do: path <> "index.html", else: path
  end

  # `root` is the relative path from a page back to the site root. Pages live
  # at the root or one directory below it.
  defp page_root(path), do: if(String.ends_with?(path, "/"), do: "../", else: "")

  defp page_assigns(assigns, page, overrides) do
    metadata = page_metadata(assigns, page)

    assigns =
      assigns
      |> Map.put(:root, page_root(metadata.path))
      |> Map.merge(overrides)

    page =
      metadata
      |> Map.put_new(:modules, [])
      |> Map.merge(%{
        id: page,
        url: Util.absolute_url(assigns.base_url, metadata.path),
        image_url: Util.absolute_url(assigns.base_url, @og_image_path),
        image_alt: "#{Map.get(assigns.site, :display_name, assigns.site.handle)} mascot",
        feed_title: Syndication.title(assigns.site),
        atom_feed_url: public_href(assigns, "radar.xml"),
        json_feed_url: public_href(assigns, "feed.json")
      })

    Map.put(assigns, :page, page)
  end

  # Absolute when the public base URL is known, otherwise relative to the page.
  defp public_href(%{base_url: ""} = assigns, path), do: assigns.root <> path
  defp public_href(assigns, path), do: Util.absolute_url(assigns.base_url, path)

  defp radar_scope(assigns, category) do
    %{category: category, total_items: radar_total_items(assigns.items, category)}
  end

  defp radar_total_items(items, "github"), do: Enum.count(items, &github_item?/1)
  defp radar_total_items(items, _category), do: length(items)

  defp github_item?(item) do
    case URI.parse(Map.get(item, :url, "")) do
      %URI{host: host} when is_binary(host) ->
        host = String.downcase(host)
        host == "github.com" or String.ends_with?(host, ".github.com")

      _ ->
        false
    end
  end

  defp nav_pages, do: @nav_pages

  # Each page's own metadata: where it lives, its <title> and description, the
  # footer note, and any extra script modules (`modules`) it loads.
  defp page_metadata(%{site: site}, :index) do
    %{
      path: "",
      title: "#{site.handle} - #{site.headline}",
      description: site_description(site),
      footer: "static export from Elixir config and RSS data"
    }
  end

  defp page_metadata(%{site: site}, :radar) do
    %{
      path: "radar/",
      title: "Technical radar - #{site.handle}",
      description: Syndication.description(site),
      footer: @radar_footer,
      modules: ["radar.js"]
    }
  end

  defp page_metadata(%{site: site}, :popular) do
    %{
      path: "popular/",
      title: "Popular on GitHub - #{site.handle}",
      description: "GitHub links surfaced on #{site.handle}'s technical radar.",
      footer: @radar_footer,
      modules: ["radar.js"]
    }
  end

  defp page_metadata(%{site: site}, :digest) do
    %{
      path: "digest/",
      title: "Weekly digest - #{site.handle}",
      description:
        "Top recent radar items ranked by score multiplied by feed weight for #{site.handle}.",
      footer: "weekly static digest from public radar data"
    }
  end

  defp page_metadata(%{site: site}, :friends) do
    %{
      path: "friends/",
      title: "friends - #{site.handle}",
      description: "Meet Kofun-kun and Dochicken-san, the pixel mascots of #{site.handle}.",
      footer: "pixel mascots, hand-placed one dot at a time"
    }
  end

  defp page_metadata(%{site: site}, :not_found) do
    %{
      path: "404.html",
      title: "404 - #{site.handle}",
      description: "Page not found on #{site.handle}.",
      footer: "GitHub Pages 404"
    }
  end

  defp site_description(site) do
    site
    |> Map.get(:about, Map.get(site, :headline, ""))
    |> Util.summarize(220)
  end

  # Path of the site on its host ("/hub/"), taken from the public base URL.
  defp not_found_root(""), do: "./"

  defp not_found_root(base_url) do
    path =
      base_url
      |> URI.parse()
      |> Map.get(:path)
      |> to_string()
      |> String.trim_trailing("/")

    path <> "/"
  end

  # <head> tags (called from the layout template)

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

  defp meta_property(_property, ""), do: ""

  defp meta_property(property, content),
    do: ~s(<meta property="#{property}" content="#{HTML.escape(content)}">)

  defp meta_name(_name, ""), do: ""
  defp meta_name(name, content), do: ~s(<meta name="#{name}" content="#{HTML.escape(content)}">)

  defp feed_discovery_tags(page) do
    [
      {"application/atom+xml", "Atom", page.atom_feed_url},
      {"application/feed+json", "JSON", page.json_feed_url}
    ]
    |> Enum.map_join("\n  ", fn {type, format, href} ->
      title = HTML.escape("#{page.feed_title} #{format} feed")
      ~s(<link rel="alternate" type="#{type}" title="#{title}" href="#{HTML.escape(href)}">)
    end)
  end

  defp canonical_link_tag(%{url: ""}), do: ""
  defp canonical_link_tag(page), do: ~s(<link rel="canonical" href="#{HTML.escape(page.url)}">)

  # Radar data, feeds, and health

  defp write_radar_data(out_dir, assigns) do
    # Radar data used to be exported under data/; drop it from reused output dirs.
    File.rm_rf!(Path.join(out_dir, "data"))

    data_dir = Path.join(out_dir, "radar-data")
    recent_items = recent_public_items(assigns.items, assigns.generated_at)
    public_feeds = Enum.map(assigns.feeds, &Map.take(&1, [:id, :name, :kind, :enabled, :tags]))

    Store.write_json(Path.join(data_dir, "items.json"), recent_items)
    Store.write_json(Path.join(data_dir, "items-recent.json"), recent_items)
    Store.write_json(Path.join(data_dir, "items-archive.json"), assigns.items)
    Store.write_json(Path.join(data_dir, "site.json"), assigns.site)
    Store.write_json(Path.join(data_dir, "feeds.json"), public_feeds)
  end

  # The page loads this slimmer list first: recent items without their full
  # content. The archive is only fetched when a search needs it.
  defp recent_public_items(public_items, generated_at) do
    cutoff = DateTime.add(generated_at, -@recent_days * 86_400, :second)

    public_items
    |> Enum.filter(&(DateTime.compare(Util.item_time(&1), cutoff) != :lt))
    |> Enum.map(&Map.delete(&1, :content))
  end

  defp write_feeds(out_dir, %{site: site, base_url: base_url, items: items} = assigns) do
    atom = Syndication.atom(site, base_url, items, assigns.generated_at)
    images = [icon: @og_image_path, favicon: @favicon_path]

    File.write!(Path.join(out_dir, "feeds.opml"), Syndication.opml(site, assigns.feeds))
    File.write!(Path.join(out_dir, "radar.xml"), atom)

    Store.write_json(
      Path.join(out_dir, "feed.json"),
      Syndication.json(site, base_url, items, images)
    )
  end

  defp write_health(out_dir, assigns, opts) do
    export =
      assigns
      |> Map.take([:generated_at, :generated_text, :enabled_feeds, :asset_version])
      |> Map.put(:item_count, length(assigns.items))

    report =
      Health.report(
        export,
        Keyword.get(opts, :collection_report, %{}),
        Keyword.get(opts, :feed_state, %{}),
        assigns.feeds
      )

    Store.write_json(Path.join(out_dir, "health.json"), report)
  end

  # Static files

  defp write_static_files(out_dir, %{site: site, base_url: base_url} = assigns) do
    copy_assets(out_dir, assigns.asset_version)
    File.write!(Path.join(out_dir, @favicon_path), Kofun.favicon_svg())
    File.write!(Path.join(out_dir, @og_image_path), og_image_svg(site))
    File.write!(Path.join(out_dir, ".nojekyll"), "")
    File.write!(Path.join(out_dir, "robots.txt"), robots(base_url))

    if base_url != "" do
      File.write!(Path.join(out_dir, "sitemap.xml"), sitemap(base_url))
    end
  end

  defp copy_assets(out_dir, version) do
    target = Path.join(out_dir, "static")
    File.mkdir_p!(target)

    Enum.each(asset_paths(), fn path ->
      dest = Path.join(target, Path.basename(path))

      if String.ends_with?(path, ".js") do
        File.write!(dest, version_imports(File.read!(path), version))
      else
        File.cp!(path, dest)
      end
    end)
  end

  defp asset_paths, do: @asset_dir |> Path.join("*") |> Path.wildcard() |> Enum.sort()

  # Cache-busting version derived from the static bundle's content. It changes
  # only when an asset changes (data-only refreshes keep it stable), so a deploy
  # is guaranteed to be reflected without re-downloading unchanged assets.
  defp asset_version do
    asset_paths()
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

  # Social preview card: the mascot next to the handle and headline, in the
  # site's dark theme colors.
  defp og_image_svg(site) do
    font = ~s(font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace")

    mascot =
      Kofun.favicon_svg()
      |> String.replace("<svg ", ~s(<svg x="92" y="135" width="360" height="360" ))
      |> String.trim()

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" role="img" aria-label="#{HTML.escape(Syndication.title(site))}">
      <rect width="1200" height="630" fill="#08110f"/>
      #{mascot}
      <text x="500" y="280" fill="#d9f7ea" #{font} font-size="80" font-weight="700">#{HTML.escape(Map.get(site, :handle, "hjosugi-hub"))}</text>
      <text x="504" y="348" fill="#71f6bd" #{font} font-size="36">~/radar</text>
      <text x="504" y="412" fill="#86a99c" #{font} font-size="36">#{HTML.escape(Util.truncate(Map.get(site, :headline, "Technical radar"), 64))}</text>
    </svg>
    """
  end

  defp robots(""), do: "User-agent: *\nAllow: /\n"
  defp robots(base_url), do: "User-agent: *\nAllow: /\nSitemap: #{base_url}/sitemap.xml\n"

  defp sitemap(base_url) do
    urls =
      ["" | Keyword.values(@nav_pages)]
      |> Enum.map_join("\n", &"  <url><loc>#{base_url}/#{&1}</loc></url>")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """
  end
end
