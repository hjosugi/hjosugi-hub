defmodule HjosugiHub.StoreTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.{Item, Store}

  test "write_items and read_items round-trip a normal cache" do
    path =
      Path.join(System.tmp_dir!(), "hjosugi-hub-store-#{System.unique_integer([:positive])}.term")

    item = %Item{
      id: "round-trip-1",
      source_id: "source",
      source_name: "Source",
      source_kind: "rss",
      title: "Round trip",
      url: "https://example.com/round-trip",
      image: "https://i.ytimg.com/vi/round-trip/hqdefault.jpg",
      summary: "summary",
      content: "content",
      published_at: ~U[2026-06-20 12:00:00Z],
      collected_at: ~U[2026-06-20 12:30:00Z],
      tags: ["cache"]
    }

    Store.write_items(path, [item])

    assert [%Item{id: "round-trip-1", tags: ["cache"], image: image}] = Store.read_items(path)
    assert image == "https://i.ytimg.com/vi/round-trip/hqdefault.jpg"

    File.rm(path)
  end

  test "read_items returns an empty list for corrupt cache bytes" do
    path =
      Path.join(System.tmp_dir!(), "hjosugi-hub-store-#{System.unique_integer([:positive])}.term")

    File.write!(path, "not an external term")

    assert Store.read_items(path) == []

    File.rm(path)
  end

  test "feed state round-trips validators and ignores corrupt bytes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "hjosugi-hub-feed-state-#{System.unique_integer([:positive])}.term"
      )

    state = %{
      "feed-a" => %{etag: ~s("abc"), last_modified: "Sat, 20 Jun 2026 10:00:00 GMT"},
      feed_b: %{"etag" => ~s("def"), "last_modified" => ""}
    }

    Store.write_feed_state(path, state)

    assert Store.read_feed_state(path) == %{
             "feed-a" => %{etag: ~s("abc"), last_modified: "Sat, 20 Jun 2026 10:00:00 GMT"},
             "feed_b" => %{etag: ~s("def")}
           }

    File.write!(path, "not an external term")

    assert Store.read_feed_state(path) == %{}

    File.rm(path)
  end

  test "feed state preserves collection health fields" do
    path =
      Path.join(
        System.tmp_dir!(),
        "hjosugi-hub-feed-state-#{System.unique_integer([:positive])}.term"
      )

    state = %{
      "feed-a" => %{
        "etag" => ~s("abc"),
        "consecutive_failures" => "3",
        "first_failure_at" => "2026-06-18T00:00:00Z",
        "last_failure_at" => "2026-06-20T00:00:00Z",
        "last_success_at" => "2026-06-17T00:00:00Z",
        "last_checked_at" => "2026-06-20T00:00:00Z",
        "last_status" => "error",
        "last_error" => "timeout",
        "last_response_code" => "0"
      }
    }

    Store.write_feed_state(path, state)

    assert Store.read_feed_state(path) == %{
             "feed-a" => %{
               etag: ~s("abc"),
               consecutive_failures: 3,
               first_failure_at: "2026-06-18T00:00:00Z",
               last_failure_at: "2026-06-20T00:00:00Z",
               last_success_at: "2026-06-17T00:00:00Z",
               last_checked_at: "2026-06-20T00:00:00Z",
               last_status: "error",
               last_error: "timeout",
               last_response_code: 0
             }
           }

    File.rm(path)
  end

  test "read_json returns decoded maps and tolerates missing or corrupt files" do
    path =
      Path.join(System.tmp_dir!(), "hjosugi-hub-json-#{System.unique_integer([:positive])}.json")

    assert Store.read_json(path) == %{}

    Store.write_json(path, %{status: "warning", failed_sources: 2})

    assert Store.read_json(path) == %{"failed_sources" => 2, "status" => "warning"}

    File.write!(path, "not json")

    assert Store.read_json(path) == %{}

    File.rm(path)
  end

  test "normalizes cached items from the previous app name" do
    path =
      Path.join(System.tmp_dir!(), "hjosugi-hub-store-#{System.unique_integer([:positive])}.term")

    previous_struct = String.to_atom("Elixir.Legacy.Item")

    legacy_items = [
      %{
        __struct__: previous_struct,
        id: "legacy-1",
        source_id: "source",
        source_name: "Source",
        source_kind: "rss",
        title: "Cached item",
        url: "https://example.com/item",
        author: "",
        summary: "summary",
        content: "content",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-21 00:00:00Z],
        tags: ["cache"]
      }
    ]

    File.write!(path, :erlang.term_to_binary(legacy_items))

    assert [%Item{} = item] = Store.read_items(path)
    assert item.id == "legacy-1"
    assert item.tags == ["cache"]

    File.rm(path)
  end

  test "reads cached items serialized before :score existed without crashing" do
    path =
      Path.join(System.tmp_dir!(), "hjosugi-hub-store-#{System.unique_integer([:positive])}.term")

    # A HjosugiHub.Item struct as serialized before the :score field was added.
    legacy_item =
      %{
        __struct__: Item,
        id: "old-1",
        source_id: "hacker-news",
        source_name: "Hacker News",
        source_kind: "aggregator",
        title: "Cached HN item",
        url: "https://example.com/item",
        author: "someone",
        summary: "summary",
        content: "content",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-21 00:00:00Z],
        tags: ["aggregator"]
      }

    File.write!(path, :erlang.term_to_binary([legacy_item]))

    items = Store.read_items(path)
    assert [%Item{score: nil}] = items
    assert [%{score: nil}] = Store.public_items(items)

    File.rm(path)
  end

  test "public_items/1 tolerates a struct missing :score without crashing" do
    # Reproduces the hub.collect crash: public_items is called directly on
    # merged items (not via read_items), so a struct deserialized from the
    # cache before :score existed reaches it without normalization.
    stale =
      %{
        __struct__: Item,
        id: "stale-1",
        source_id: "hacker-news",
        source_name: "Hacker News Front Page",
        source_kind: "aggregator",
        title: "stale item",
        url: "https://github.com/owner/repo",
        author: "someone",
        summary: "summary",
        content: "content",
        published_at: ~U[2026-06-21 00:00:00Z],
        collected_at: ~U[2026-06-21 01:31:00Z],
        tags: ["aggregator"]
      }

    refute Map.has_key?(stale, :score)
    assert [%{id: "stale-1", score: nil}] = Store.public_items([stale])
  end

  test "public_items/1 groups normalized urls across sources and merges tags" do
    items = [
      %Item{
        id: "origin-1",
        source_id: "origin",
        source_name: "Origin Blog",
        source_kind: "official",
        title: "Original post",
        url: "HTTP://www.Example.com/posts/elixir/?b=2&utm_source=feed&a=1#comments",
        image: "",
        summary: "Origin summary",
        published_at: ~U[2026-06-20 12:00:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: ["official", "elixir"]
      },
      %Item{
        id: "hn-1",
        source_id: "hacker-news",
        source_name: "Hacker News",
        source_kind: "aggregator",
        title: "HN discussion",
        url: "https://example.com/posts/elixir?a=1&b=2&utm_medium=social",
        image: "https://i.ytimg.com/vi/grouped/hqdefault.jpg",
        summary: "HN summary",
        published_at: ~U[2026-06-20 12:30:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        score: 42,
        tags: ["aggregator", "elixir"]
      },
      %Item{
        id: "different-query",
        source_id: "newsletter",
        source_name: "Newsletter",
        source_kind: "newsletter",
        title: "Different query",
        url: "https://example.com/posts/elixir?a=1&b=3",
        summary: "Different summary",
        published_at: ~U[2026-06-20 12:45:00Z],
        collected_at: ~U[2026-06-20 13:00:00Z],
        tags: ["newsletter"]
      }
    ]

    public_items = Store.public_items(items)

    assert length(public_items) == 2

    grouped =
      Enum.find(public_items, &(&1.normalized_url == "https://example.com/posts/elixir?a=1&b=2"))

    assert grouped.id == "origin-1"
    assert grouped.image == "https://i.ytimg.com/vi/grouped/hqdefault.jpg"
    assert grouped.tags == ["aggregator", "elixir", "official"]
    assert Enum.map(grouped.sources, & &1.source_id) == ["origin", "hacker-news"]
    assert Enum.find(grouped.sources, &(&1.source_id == "hacker-news")).score == 42

    assert Enum.any?(
             public_items,
             &(&1.normalized_url == "https://example.com/posts/elixir?a=1&b=3")
           )
  end

  test "normalizes cached future published_at beyond tolerance" do
    path =
      Path.join(System.tmp_dir!(), "hjosugi-hub-store-#{System.unique_integer([:positive])}.term")

    cached = %{
      __struct__: Item,
      id: "future-1",
      source_id: "source",
      source_name: "Source",
      source_kind: "rss",
      title: "future item",
      url: "https://example.com/future",
      author: "",
      summary: "summary",
      content: "content",
      published_at: ~U[2026-06-22 00:00:00Z],
      collected_at: ~U[2026-06-20 12:00:00Z],
      tags: []
    }

    File.write!(path, :erlang.term_to_binary([cached]))

    assert [%Item{published_at: ~U[2026-06-20 12:00:00Z]}] = Store.read_items(path)

    File.rm(path)
  end

  test "keeps cached published_at within tolerance" do
    collected_at = ~U[2026-06-20 12:00:00Z]
    published_at = ~U[2026-06-20 17:59:00Z]

    assert Store.clamp_published_at(published_at, collected_at) == published_at
  end
end
