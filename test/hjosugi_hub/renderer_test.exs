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

      assert :ok = Renderer.export(site, feeds, items, out_dir, "https://example.com/hub/")

      assert File.exists?(Path.join(out_dir, "index.html"))
      assert File.exists?(Path.join(out_dir, "radar/index.html"))
      assert File.exists?(Path.join(out_dir, "popular/index.html"))
      assert File.exists?(Path.join(out_dir, "friends/index.html"))
      assert File.exists?(Path.join(out_dir, "404.html"))
      assert File.exists?(Path.join(out_dir, "feeds.opml"))
      refute File.exists?(legacy_data_dir)

      index = File.read!(Path.join(out_dir, "index.html"))
      not_found = File.read!(Path.join(out_dir, "404.html"))
      radar = File.read!(Path.join(out_dir, "radar/index.html"))
      popular = File.read!(Path.join(out_dir, "popular/index.html"))
      friends = File.read!(Path.join(out_dir, "friends/index.html"))
      items_json = File.read!(Path.join(out_dir, "radar-data/items.json"))
      feeds_json = File.read!(Path.join(out_dir, "radar-data/feeds.json"))
      opml = File.read!(Path.join(out_dir, "feeds.opml"))
      sitemap = File.read!(Path.join(out_dir, "sitemap.xml"))
      pages = [index, radar, popular, friends]

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

      assert items_json =~ ~s("weight":1.3)
      assert items_json =~ "An interesting link"
      refute items_json =~ "Private source link"
      refute items_json =~ "Disabled source link"
      refute items_json =~ "Deleted source link"
      assert feeds_json =~ "Hacker & News"
      refute feeds_json =~ "Private Feed"
      refute feeds_json =~ "Disabled Feed"
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
      assert sitemap =~ "https://example.com/hub/radar/"
      assert sitemap =~ "https://example.com/hub/popular/"
      assert sitemap =~ "https://example.com/hub/friends/"
    after
      File.rm_rf(out_dir)
    end
  end
end
