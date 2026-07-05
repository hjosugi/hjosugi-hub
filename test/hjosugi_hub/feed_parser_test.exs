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

  test "captures count-before-label aggregator metadata" do
    feed = %{
      id: "aggregator",
      name: "Aggregator",
      url: "https://example.com/feed.xml",
      kind: "aggregator"
    }

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Point-forward post</title>
          <link>https://example.com/points</link>
          <guid>agg-1</guid>
          <description><![CDATA[
            <p><a href="https://example.com/points">123 points</a>
            by ada | <a href="https://example.com/comments">42 comments</a></p>
          ]]></description>
        </item>
        <item>
          <title>Comment-only post</title>
          <link>https://example.com/comments-only</link>
          <guid>agg-2</guid>
          <description><![CDATA[
            <p><a href="https://example.com/comments-only">42 comments</a></p>
          ]]></description>
        </item>
        <item>
          <title>Unknown metadata post</title>
          <link>https://example.com/unknown</link>
          <guid>agg-3</guid>
          <description><![CDATA[<p>Discussion active; score not available.</p>]]></description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [points_item, comments_item, unknown_item]} = FeedParser.parse(xml, feed)
    assert points_item.score == 123
    assert comments_item.score == 42
    assert unknown_item.score == nil
  end

  test "captures Lobsters-style escaped metadata descriptions" do
    feed = %{
      id: "lobsters",
      name: "Lobsters",
      url: "https://lobste.rs/rss",
      kind: "aggregator"
    }

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Returning to Zig</title>
          <link>https://example.com/return-to-zig</link>
          <guid>https://lobste.rs/s/svm2dp</guid>
          <comments>https://lobste.rs/s/svm2dp/returning_zig</comments>
          <description>
            &lt;p&gt;&lt;a href=&quot;https://lobste.rs/s/svm2dp/returning_zig&quot;&gt;5 comments&lt;/a&gt;
            | 15 points&lt;/p&gt;
          </description>
        </item>
        <item>
          <title>Current comment link shape</title>
          <link>https://example.com/current-lobsters</link>
          <guid>https://lobste.rs/s/current</guid>
          <comments>https://lobste.rs/s/current/current_comment_link_shape</comments>
          <description>
            &lt;p&gt;&lt;a href=&quot;https://lobste.rs/s/current/current_comment_link_shape&quot;&gt;Comments&lt;/a&gt;&lt;/p&gt;
          </description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [scored_item, unknown_item]} = FeedParser.parse(xml, feed)
    assert scored_item.score == 15
    assert unknown_item.score == nil
  end

  test "parses RSS items containing nested same-name item tags" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Outer item</title>
          <link>https://example.com/outer</link>
          <guid>outer-1</guid>
          <description>
            Before
            <item>
              <title>Inner item</title>
            </item>
            after.
          </description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed)
    assert item.title == "Outer item"
    assert item.url == "https://example.com/outer"
    assert item.content == "Before Inner item after."
  end

  test "joins multiple CDATA sections in RSS text" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Split CDATA</title>
          <link>https://example.com/cdata</link>
          <guid>cdata-1</guid>
          <description><![CDATA[First ]]><![CDATA[Points: 42]]><![CDATA[ for PostgreSQL]]></description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed)
    assert item.content == "First Points: 42 for PostgreSQL"
    assert item.score == 42
  end

  test "parses namespaced RSS fields" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    now = ~U[2026-06-20 12:00:00Z]

    xml = """
    <rss version="2.0"
         xmlns:content="http://purl.org/rss/1.0/modules/content/"
         xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <item>
          <title>Namespaced item</title>
          <link>https://example.com/namespaced</link>
          <guid>namespaced-1</guid>
          <description>Short description</description>
          <content:encoded><![CDATA[Full database content]]></content:encoded>
          <dc:creator>Grace Hopper</dc:creator>
          <dc:date>2026-06-20T09:30:00Z</dc:date>
          <category>Cloud</category>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed, now)
    assert item.content == "Full database content"
    assert item.author == "Grace Hopper"
    assert item.published_at == ~U[2026-06-20 09:30:00Z]
    assert "cloud" in item.tags
  end

  test "parses Atom links with attributes containing greater-than characters" do
    feed = %{
      id: "atom",
      name: "Atom Feed",
      url: "https://example.com/feed.xml",
      kind: "atom"
    }

    xml = """
    <feed xmlns="http://www.w3.org/2005/Atom">
      <entry>
        <title>Attribute link</title>
        <id>tag:example.com,2026:attr</id>
        <updated>2026-06-20T10:00:00Z</updated>
        <author>
          <name>Ada</name>
        </author>
        <link rel="alternate" href="/posts?q=1>0"/>
        <summary>Frontend note</summary>
        <category term="frontend"/>
      </entry>
    </feed>
    """

    assert {:ok, [item]} = FeedParser.parse(xml, feed)
    assert item.url == "https://example.com/posts?q=1>0"
    assert item.author == "Ada"
    assert "frontend" in item.tags
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

  test "returns an error for unsupported XML" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    assert {:error, ":unsupported_feed"} = FeedParser.parse("<root />", feed)
  end

  test "returns an error for bad XML" do
    feed = %{
      id: "sample",
      name: "Sample Feed",
      url: "https://example.com/feed.xml",
      kind: "rss"
    }

    assert {:error, message} =
             FeedParser.parse("<rss><channel><item></channel></rss>", feed)

    assert is_binary(message)
  end
end
