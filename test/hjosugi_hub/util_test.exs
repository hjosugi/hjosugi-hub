defmodule HjosugiHub.UtilTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Util

  test "cleans html and decodes common entities" do
    assert Util.clean_text("<p>A &amp; B</p>") == "A & B"
  end

  test "decodes decimal numeric character references" do
    assert Util.clean_text("AT&#38;T &#8217;26") == "AT&T " <> <<0x2019::utf8>> <> "26"
  end

  test "decodes hex numeric character references" do
    assert Util.clean_text("A &#x2014; B &#X27;quote&#x27;") ==
             "A " <> <<0x2014::utf8>> <> " B 'quote'"
  end

  test "decodes additional common named entities" do
    assert Util.clean_text("&ldquo;Hello&nbsp;world&rdquo;&mdash;ok&hellip;") ==
             <<0x201C::utf8>> <>
               "Hello world" <> <<0x201D::utf8>> <> <<0x2014::utf8>> <> "ok" <> <<0x2026::utf8>>
  end

  test "strips entity-escaped html (e.g. Lobsters descriptions)" do
    escaped = "&lt;p&gt;&lt;a href=\"https://lobste.rs/s/x\"&gt;Comments&lt;/a&gt;&lt;/p&gt;"
    assert Util.clean_text(escaped) == "Comments"
  end

  test "builds stable ids" do
    assert byte_size(Util.stable_id("source", "raw")) == 32
  end

  test "normalizes urls for grouping" do
    assert Util.normalize_url(
             "HTTP://www.Example.com/post/?b=2&utm_source=newsletter&a=1#comments"
           ) == "https://example.com/post?a=1&b=2"

    assert Util.normalize_url("http://example.com:80/post/") == "https://example.com/post"
    assert Util.normalize_url("https://www.example.com/") == "https://example.com"
  end

  test "keeps and sorts meaningful query params while removing tracking params" do
    assert Util.normalize_url(
             "https://example.com/search?utm_medium=social&sort=new&q=elixir&fbclid=abc"
           ) == "https://example.com/search?q=elixir&sort=new"
  end

  test "parses RFC 822 dates in UTC" do
    assert Util.parse_date("Fri, 13 Nov 2026 12:58:00 GMT") == ~U[2026-11-13 12:58:00Z]
    assert Util.parse_date("Fri, 13 Nov 2026 12:58:00 +0000") == ~U[2026-11-13 12:58:00Z]
    assert Util.parse_date("Fri, 13 Nov 2026 12:58:00") == ~U[2026-11-13 12:58:00Z]
  end

  test "applies the zone of RFC 822 dates" do
    assert Util.parse_date("Fri, 13 Nov 2026 12:58:00 -0800") == ~U[2026-11-13 20:58:00Z]
    assert Util.parse_date("Sat, 14 Nov 2026 10:08:27 -06:00") == ~U[2026-11-14 16:08:27Z]
    assert Util.parse_date("Sun, 15 Nov 2026 09:30:00 +0930") == ~U[2026-11-15 00:00:00Z]
    assert Util.parse_date("Fri, 13 Nov 2026 12:58:00 PST") == ~U[2026-11-13 20:58:00Z]
    assert Util.parse_date("Fri, 13 Nov 2026 23:00:00 EDT") == ~U[2026-11-14 03:00:00Z]
  end

  test "accepts the optional parts of RFC 822 dates" do
    assert Util.parse_date("Wed, 4 Nov 2026 10:08:27 +0000") == ~U[2026-11-04 10:08:27Z]
    assert Util.parse_date("4 Nov 2026 10:08:27 +0000") == ~U[2026-11-04 10:08:27Z]
    assert Util.parse_date("Wed, 04 Nov 2026 10:08 +0000") == ~U[2026-11-04 10:08:00Z]
    assert Util.parse_date("Wednesday, 4 November 2026 10:08:27 GMT") == ~U[2026-11-04 10:08:27Z]
  end

  test "still parses ISO dates and rejects nonsense" do
    assert Util.parse_date("2026-11-13T12:58:00-08:00") == ~U[2026-11-13 20:58:00Z]
    assert Util.parse_date("2026-11-13") == ~U[2026-11-13 00:00:00Z]
    assert Util.parse_date("Fri, 31 Feb 2026 12:58:00 GMT") == nil
    assert Util.parse_date("Fri, 13 Foo 2026 12:58:00 GMT") == nil
    assert Util.parse_date("yesterday") == nil
    assert Util.parse_date(nil) == nil
  end
end
