defmodule HjosugiSite.UtilTest do
  use ExUnit.Case, async: true

  alias HjosugiSite.Util

  test "cleans html and decodes common entities" do
    assert Util.clean_text("<p>A &amp; B</p>") == "A & B"
  end

  test "builds stable ids" do
    assert byte_size(Util.stable_id("source", "raw")) == 32
  end
end
