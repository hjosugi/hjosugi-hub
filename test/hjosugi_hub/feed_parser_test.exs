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
  end
end
