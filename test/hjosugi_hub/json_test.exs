defmodule HjosugiHub.JSONTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.JSON

  defmodule Example do
    defstruct [:name, :hidden, count: 2]
  end

  test "encodes nested values" do
    assert JSON.encode!(%{name: "a&b", tags: ["x", "y"], ok: true}) ==
             "{\"name\":\"a&b\",\"ok\":true,\"tags\":[\"x\",\"y\"]}"
  end

  test "omits nil map values but preserves nil list values" do
    assert JSON.encode!(%{present: "yes", missing: nil, items: [nil, "x"]}) ==
             "{\"items\":[null,\"x\"],\"present\":\"yes\"}"
  end

  test "encodes DateTime values as ISO8601 strings" do
    encoded = JSON.encode!(%{published_at: ~U[2024-01-02 03:04:05Z]})

    assert encoded == "{\"published_at\":\"2024-01-02T03:04:05Z\"}"
  end

  test "encodes structs as maps" do
    assert JSON.encode!(%Example{name: "sample", hidden: nil}) ==
             "{\"count\":2,\"name\":\"sample\"}"
  end
end
