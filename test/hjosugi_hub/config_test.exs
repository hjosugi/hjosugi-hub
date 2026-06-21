defmodule HjosugiHub.ConfigTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Config

  test "feed_weight falls back to a default for the kind" do
    assert Config.feed_weight(%{kind: "aggregator"}) == 1.3
    assert Config.feed_weight(%{kind: "official"}) == 1.0
    assert Config.feed_weight(%{kind: "unknown"}) == 1.0
    assert Config.feed_weight(%{}) == 1.0
  end

  test "an explicit weight overrides the kind default" do
    assert Config.feed_weight(%{kind: "official", weight: 1.4}) == 1.4
  end
end
