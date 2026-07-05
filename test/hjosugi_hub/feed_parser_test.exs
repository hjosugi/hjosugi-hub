defmodule HjosugiHub.FeedParserTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.FeedParser

  test "parses RSS items into normalized items" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss",
      tags: ["sample"]
    }

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Distributed database note</title>
          <link>/posts/db</link>
          <guid>db-1</guid>
          <description><![CDATA[Spanner and PostgreSQL notes.]]></description>
          <pubDate>Sat, 20 Jun 2026 12:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed)
    assert item.source_name == "Sample Feed"
    assert item.url == "https://example.com/posts/db"
    assert "database" in item.tags
    assert item.score == nil
  end

  test "captures a crowd-vote score when the feed exposes it" do
    feed = %{
      id: "hn",
      name: "Hacker News",
      url: "https://hnrss.org/frontpage",
      kind: "aggregator"
    }

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>A popular post</title>
          <link>https://example.com/post</link>
          <guid>hn-1</guid>
          <description><![CDATA[<p>Points: 248</p><p># Comments: 73</p>]]></description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed)
    assert item.score == 248
  end

  test "clamps feed published_at far in the future to collection time" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    now = ~U[2026-06-20 12:00:00Z]

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Bad clock</title>
          <link>https://example.com/future</link>
          <guid>future-1</guid>
          <description>Clock skew</description>
          <pubDate>Sun, 21 Jun 2026 12:01:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed, now)
    assert item.published_at == now
    assert item.collected_at == now
  end

  test "keeps normal feed dates unchanged" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    now = ~U[2026-06-20 12:00:00Z]
    published = "Sat, 20 Jun 2026 10:00:00 GMT"

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Normal clock</title>
          <link>https://example.com/normal</link>
          <guid>normal-1</guid>
          <description>Normal date</description>
          <pubDate>#{published}</pubDate>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed, now)
    assert item.published_at == ~U[2026-06-20 10:00:00Z]
  end
end
