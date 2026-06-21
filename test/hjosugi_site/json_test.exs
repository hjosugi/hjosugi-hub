defmodule HjosugiSite.JSONTest do
  use ExUnit.Case, async: true

  alias HjosugiSite.JSON

  test "encodes nested values" do
    assert JSON.encode!(%{name: "a&b", tags: ["x", "y"], ok: true}) ==
             "{\"name\":\"a&b\",\"ok\":true,\"tags\":[\"x\",\"y\"]}"
  end
end
