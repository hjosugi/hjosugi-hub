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
end
