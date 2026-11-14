defmodule HjosugiHub.DigestTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Digest

  @now ~U[2026-06-20 12:00:00Z]

  test "groups scored items into weekly windows ranked by score times weight" do
    items = [
      item("plain", 50, 1),
      item("boosted", 40, 2) |> Map.put(:weight, 2.0),
      item("last-week", 10, 8),
      item("unscored", nil, 1),
      item("future", 99, -1),
      item("too-old", 99, 28)
    ]

    assert [this_week, last_week] = Digest.sections(items, @now)

    assert this_week.label == "Last 7 days"
    assert this_week.period == "2026-06-13 - 2026-06-20 UTC"

    assert Enum.map(this_week.items, &{&1.rank, &1.title, &1.rank_score}) ==
             [{1, "boosted", 80.0}, {2, "plain", 50.0}]

    assert last_week.index == 1
    assert last_week.label == "8-14 days ago"
    assert Enum.map(last_week.items, & &1.title) == ["last-week"]
  end

  test "formats scores and weights without a trailing .0" do
    assert Digest.format_number(40) == "40"
    assert Digest.format_number(80.0) == "80"
    assert Digest.format_number(1.3) == "1.3"
  end

  defp item(title, score, days_ago) do
    at = DateTime.add(@now, -days_ago * 86_400, :second)

    %{
      id: title,
      source_id: "feed",
      source_name: "Feed",
      title: title,
      url: "https://example.com/#{title}",
      summary: "summary",
      published_at: at,
      collected_at: at,
      score: score,
      tags: []
    }
  end
end
