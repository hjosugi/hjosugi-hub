defmodule HjosugiHub.RendererTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.{Item, Renderer}

  test "export writes radar pages, OPML, and weighted public data" do
    out_dir =
      Path.join(System.tmp_dir!(), "hjosugi-hub-renderer-#{System.unique_integer([:positive])}")

    site = %{
      handle: "test-hub",
      display_name: "Test Hub",
      headline: "A test site",
      location: "Tokyo, Japan",
      about: "Testing the static export.",
      links: [],
      projects: [],
      skills: []
    }

    feeds = [
      %{
        id: "hacker-news",
        name: "Hacker & News",
        url: "https://example.com/hn.xml",
        kind: "aggregator",
        enabled: true,
        tags: []
      },
      %{
        id: "private-feed",
        name: "Private Feed",
        url: "https://example.com/private.xml",
        kind: "newsletter",
        enabled: true,
        public: false,
        tags: []
      },
      %{
        id: "disabled",
        name: "Disabled Feed",
        url: "https://example.com/disabled.xml",
        kind: "official",
        enabled: false,
        tags: []
      }
    ]

    items = [
      %Item{
        id: "item-1",
        source_id: "hacker-news",
        source_name: "Hacker News",
        source_kind: "aggregator",
        title: "An interesting link",
        url: "https://example.com/item",
        summary: "A summary",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: ["elixir"]
      },
      %Item{
        id: "item-private",
        source_id: "private-feed",
        source_name: "Private Feed",
        source_kind: "newsletter",
        title: "Private source link",
        url: "https://example.com/private",
        summary: "Should not be exported",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: []
      },
      %Item{
        id: "item-disabled",
        source_id: "disabled",
        source_name: "Disabled Feed",
        source_kind: "official",
        title: "Disabled source link",
        url: "https://example.com/disabled",
        summary: "Should not be exported",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: []
      },
      %Item{
        id: "item-deleted",
        source_id: "deleted-feed",
        source_name: "Deleted Feed",
        source_kind: "official",
        title: "Deleted source link",
        url: "https://example.com/deleted",
        summary: "Should not be exported",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: []
      }
    ]

    try do
      legacy_data_dir = Path.join(out_dir, "data")
      File.mkdir_p!(legacy_data_dir)
      File.write!(Path.join(legacy_data_dir, "items.json"), "[]")

      collection_report = %{
        status: "warning",
        started_at: ~U[2026-06-20 13:00:00Z],
        finished_at: ~U[2026-06-20 13:01:00Z],
        fresh_items: 0,
        successful_sources: 1,
        failed_sources: 1,
        stale_sources: 1,
        warnings: [
          %{
            code: "feed_failures",
            count: 1,
            source_ids: ["hacker-news"],
            message: "1 feed(s) failed during collection."
          }
        ]
      }

      assert :ok =
               Renderer.export(site, feeds, items, out_dir, "https://example.com/hub/",
                 collection_report: collection_report,
                 feed_state: %{
                   "hacker-news" => %{
                     last_status: "error",
                     consecutive_failures: 7
                   }
                 }
               )

      assert File.exists?(Path.join(out_dir, "index.html"))
      assert File.exists?(Path.join(out_dir, "radar/index.html"))
      assert File.exists?(Path.join(out_dir, "popular/index.html"))
      assert File.exists?(Path.join(out_dir, "friends/index.html"))
      assert File.exists?(Path.join(out_dir, "404.html"))
      assert File.exists?(Path.join(out_dir, "feeds.opml"))
      assert File.exists?(Path.join(out_dir, "radar.xml"))
      assert File.exists?(Path.join(out_dir, "feed.json"))
      assert File.exists?(Path.join(out_dir, "static/og-image.svg"))
      refute File.exists?(legacy_data_dir)

      index = File.read!(Path.join(out_dir, "index.html"))
      not_found = File.read!(Path.join(out_dir, "404.html"))
      radar = File.read!(Path.join(out_dir, "radar/index.html"))
      popular = File.read!(Path.join(out_dir, "popular/index.html"))
      friends = File.read!(Path.join(out_dir, "friends/index.html"))
      items_json = File.read!(Path.join(out_dir, "radar-data/items.json"))
      feeds_json = File.read!(Path.join(out_dir, "radar-data/feeds.json"))
      health_json = File.read!(Path.join(out_dir, "health.json"))
      opml = File.read!(Path.join(out_dir, "feeds.opml"))
      atom = File.read!(Path.join(out_dir, "radar.xml"))
      json_feed = File.read!(Path.join(out_dir, "feed.json"))
      og_image = File.read!(Path.join(out_dir, "static/og-image.svg"))
      sitemap = File.read!(Path.join(out_dir, "sitemap.xml"))
      pages = [index, radar, popular, friends, not_found]

      assert radar =~ ~s(data-category="all")
      assert popular =~ ~s(data-category="github")
      assert not_found =~ "<title>404 - test-hub</title>"
      assert not_found =~ "No such file or directory."
      assert not_found =~ ~s(href="/hub/static/app.css?v=)
      assert not_found =~ ~s(href="/hub/">go home</a>)
      assert not_found =~ ~s(href="/hub/radar/">open radar</a>)
      assert radar =~ ~s(href="../feeds.opml")
      assert popular =~ ~s(href="../feeds.opml")
      assert radar =~ ~s(<span>1 feeds</span>)
      assert Enum.all?(pages, &(&1 =~ ~s(<meta http-equiv="Content-Security-Policy")))
      assert Enum.all?(pages, &(&1 =~ "default-src &#39;self&#39;"))

      assert Enum.all?(
               pages,
               &(&1 =~
                   "img-src &#39;self&#39; https://github.com https://avatars.githubusercontent.com")
             )

      assert Enum.all?(
               pages,
               &(&1 =~ ~s(<meta name="referrer" content="strict-origin-when-cross-origin">))
             )

      assert Enum.all?(pages, &(&1 =~ ~s(<meta property="og:title" content=")))
      assert Enum.all?(pages, &(&1 =~ ~s(<meta property="og:description" content=")))
      assert Enum.all?(pages, &(&1 =~ ~s(<meta property="og:type" content="website">)))

      assert Enum.all?(
               pages,
               &(&1 =~
                   ~s(<meta property="og:image" content="https://example.com/hub/static/og-image.svg">))
             )

      assert Enum.all?(pages, &(&1 =~ ~s(<meta name="twitter:card" content="summary">)))

      assert Enum.all?(
               pages,
               &(&1 =~
                   ~s(<link rel="alternate" type="application/atom+xml" title="test-hub radar Atom feed" href="https://example.com/hub/radar.xml">))
             )

      assert Enum.all?(
               pages,
               &(&1 =~
                   ~s(<link rel="alternate" type="application/feed+json" title="test-hub radar JSON feed" href="https://example.com/hub/feed.json">))
             )

      assert index =~ ~s(<meta property="og:url" content="https://example.com/hub/">)
      assert radar =~ ~s(<meta property="og:url" content="https://example.com/hub/radar/">)
      assert popular =~ ~s(<meta property="og:url" content="https://example.com/hub/popular/">)
      assert friends =~ ~s(<meta property="og:url" content="https://example.com/hub/friends/">)
      assert not_found =~ ~s(<meta property="og:url" content="https://example.com/hub/404.html">)

      assert items_json =~ ~s("weight":1.3)
      assert items_json =~ "An interesting link"
      refute items_json =~ "Private source link"
      refute items_json =~ "Disabled source link"
      refute items_json =~ "Deleted source link"
      assert feeds_json =~ "Hacker & News"
      refute feeds_json =~ "Private Feed"
      refute feeds_json =~ "Disabled Feed"
      health = JSON.decode!(health_json)
      assert health["status"] == "warning"
      assert health["collection_status"] == "warning"
      assert health["generated_at"] =~ ~r/T.*Z$/
      assert health["generated_text"] =~ "UTC"
      assert health["fresh_items"] == 0
      assert health["failed_sources"] == 1
      assert health["failing_sources"] == 1
      assert health["stale_sources"] == 1
      assert health["successful_sources"] == 1
      assert health["collection_started_at"] == "2026-06-20T13:00:00Z"
      assert health["collection_finished_at"] == "2026-06-20T13:01:00Z"
      assert [%{"code" => "feed_failures", "count" => 1} = warning] = health["warnings"]
      refute Map.has_key?(warning, "source_ids")
      assert opml =~ ~s(<opml version="2.0">)
      assert opml =~ ~s(<title>test-hub feeds</title>)
      assert opml =~ ~s(text="Hacker &amp; News")
      assert opml =~ ~s(title="Hacker &amp; News")
      assert opml =~ ~s(type="rss")
      assert opml =~ ~s(xmlUrl="https://example.com/hn.xml")
      assert opml =~ ~s(category="aggregator")
      assert opml =~ ~s(kind="aggregator")
      refute opml =~ "Private Feed"
      refute opml =~ "private.xml"
      refute opml =~ "Disabled Feed"
      refute opml =~ "disabled.xml"
      assert {_xml, []} = :xmerl_scan.string(String.to_charlist(atom))
      assert atom =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
      assert atom =~ ~s(<title>test-hub radar</title>)

      assert atom =~
               ~s(<subtitle>Search collected technical reading items from test-hub.</subtitle>)

      assert atom =~ ~s(<id>https://example.com/hub/radar/</id>)

      assert atom =~
               ~s(<link rel="self" type="application/atom+xml" href="https://example.com/hub/radar.xml"/>)

      assert atom =~ ~s(<title>An interesting link</title>)
      assert atom =~ ~s(<link rel="alternate" type="text/html" href="https://example.com/item"/>)
      assert atom =~ ~s(<summary type="text">A summary</summary>)
      assert atom =~ ~s(<category term="elixir"/>)
      refute atom =~ "Private source link"
      refute atom =~ "Disabled source link"

      decoded_feed = JSON.decode!(json_feed)
      assert decoded_feed["version"] == "https://jsonfeed.org/version/1.1"
      assert decoded_feed["title"] == "test-hub radar"
      assert decoded_feed["home_page_url"] == "https://example.com/hub/radar/"
      assert decoded_feed["feed_url"] == "https://example.com/hub/feed.json"
      assert decoded_feed["icon"] == "https://example.com/hub/static/og-image.svg"
      assert [feed_item] = decoded_feed["items"]
      assert feed_item["title"] == "An interesting link"
      assert feed_item["url"] == "https://example.com/item"
      assert feed_item["summary"] == "A summary"
      assert feed_item["content_text"] == "A summary"
      assert feed_item["date_published"] == "2026-06-20T12:00:00Z"
      assert feed_item["tags"] == ["elixir"]
      refute json_feed =~ "Private source link"
      refute json_feed =~ "Disabled source link"
      assert og_image =~ ~s(width="1200" height="630")
      assert og_image =~ "test-hub"
      assert sitemap =~ "https://example.com/hub/radar/"
      assert sitemap =~ "https://example.com/hub/popular/"
      assert sitemap =~ "https://example.com/hub/friends/"
    after
      File.rm_rf(out_dir)
    end
  end

  test "export without base URL keeps feed discovery relative and omits absolute social URLs" do
    out_dir =
      Path.join(System.tmp_dir!(), "hjosugi-hub-renderer-#{System.unique_integer([:positive])}")

    site = %{
      handle: "test-hub",
      display_name: "Test Hub",
      headline: "A test site",
      location: "Tokyo, Japan",
      about: "Testing the static export.",
      links: [],
      projects: [],
      skills: []
    }

    try do
      assert :ok = Renderer.export(site, [], [], out_dir, "")

      index = File.read!(Path.join(out_dir, "index.html"))
      radar = File.read!(Path.join(out_dir, "radar/index.html"))
      atom = File.read!(Path.join(out_dir, "radar.xml"))
      decoded_feed = JSON.decode!(File.read!(Path.join(out_dir, "feed.json")))

      assert index =~
               ~s(<link rel="alternate" type="application/atom+xml" title="test-hub radar Atom feed" href="radar.xml">)

      assert radar =~
               ~s(<link rel="alternate" type="application/atom+xml" title="test-hub radar Atom feed" href="../radar.xml">)

      assert index =~ ~s(<meta property="og:title" content="test-hub - A test site">)
      refute index =~ ~s(property="og:url")
      refute index =~ ~s(property="og:image")
      refute index =~ ~s(name="twitter:image")
      refute index =~ ~s(rel="canonical")
      assert atom =~ ~s(<id>urn:hjosugi-hub:feed:)
      refute atom =~ ~s(rel="self")
      assert decoded_feed["items"] == []
      refute Map.has_key?(decoded_feed, "feed_url")
      refute Map.has_key?(decoded_feed, "home_page_url")
      refute Map.has_key?(decoded_feed, "icon")
    after
      File.rm_rf(out_dir)
    end
  end
end
