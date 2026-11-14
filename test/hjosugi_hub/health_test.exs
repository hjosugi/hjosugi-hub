defmodule HjosugiHub.HealthTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Health

  @export %{
    generated_at: ~U[2026-06-20 13:00:00Z],
    generated_text: "2026-06-20 13:00 UTC",
    enabled_feeds: 2,
    item_count: 5,
    asset_version: "abc12345"
  }
  @feeds [%{id: "a"}, %{id: "b"}]

  test "is ok when there is no collection report and no failing feed" do
    report = Health.report(@export, %{}, %{}, @feeds)

    assert report.status == "ok"
    assert report.collection_status == nil
    assert report.failed_sources == 0
    assert report.stale_sources == 0
    assert report.warnings == []
    assert report.generated_at == "2026-06-20T13:00:00Z"
    assert report.item_count == 5
  end

  test "falls back to the cached state of enabled feeds when the report has no counts" do
    feed_state = %{
      "a" => %{last_status: "error", consecutive_failures: 7},
      "b" => %{last_status: "ok"},
      "disabled" => %{last_status: "error", consecutive_failures: 9}
    }

    report = Health.report(@export, %{}, feed_state, @feeds)

    assert report.status == "warning"
    assert report.collection_status == "warning"
    assert report.failed_sources == 1
    assert report.failing_sources == 1
    assert report.stale_sources == 1
    assert Enum.map(report.warnings, & &1.code) == ["feed_failures", "stale_feeds"]
  end

  test "reads a JSON-decoded report and publishes only warning summaries" do
    collection_report = %{
      "status" => "ok",
      "started_at" => "2026-06-20T12:59:00Z",
      "fresh_items" => 3,
      "failed_sources" => 0,
      "stale_sources" => 0,
      "warnings" => [
        %{"code" => "slow_feeds", "count" => 2, "message" => "slow", "source_ids" => ["a"]}
      ]
    }

    report = Health.report(@export, collection_report, %{}, @feeds)

    assert report.status == "ok"
    assert report.fresh_items == 3
    assert report.collection_started_at == "2026-06-20T12:59:00Z"
    assert report.warnings == [%{code: "slow_feeds", count: 2, message: "slow"}]
  end
end
