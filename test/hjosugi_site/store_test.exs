defmodule HjosugiSite.StoreTest do
  use ExUnit.Case, async: true

  alias HjosugiSite.{Item, Store}

  test "normalizes cached items from the previous app name" do
    path = Path.join(System.tmp_dir!(), "hjosugi-site-store-#{System.unique_integer([:positive])}.term")

    previous_struct = String.to_atom("Elixir." <> "Signal" <> "Garden.Item")

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
end
