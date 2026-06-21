defmodule HjosugiHub.UtilTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Util

  test "cleans html and decodes common entities" do
    assert Util.clean_text("<p>A &amp; B</p>") == "A & B"
  end

  test "strips entity-escaped html (e.g. Lobsters descriptions)" do
    escaped = "&lt;p&gt;&lt;a href=\"https://lobste.rs/s/x\"&gt;Comments&lt;/a&gt;&lt;/p&gt;"
    assert Util.clean_text(escaped) == "Comments"
  end

  test "builds stable ids" do
    assert byte_size(Util.stable_id("source", "raw")) == 32
  end
end
