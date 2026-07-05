defmodule HjosugiHub.ConfigTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Config

  setup do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("hjosugi_hub_config_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  @valid_feed %{
    id: "example",
    name: "Example Feed",
    url: "https://example.com/feed.xml",
    kind: "official",
    enabled: true,
    tags: ["example"]
  }
  @second_valid_feed %{
    id: "engineering",
    name: "Engineering Feed",
    url: "http://engineering.example.com/rss",
    kind: "engineering",
    weight: 1.1,
    tags: ["engineering"]
  }
  @valid_feeds [@valid_feed, @second_valid_feed]

  @valid_site %{
    handle: "hjosugi",
    display_name: "hjosugi",
    headline: "A software engineer in Japan",
    location: "Tokyo, Japan",
    about: "A small personal site.",
    links: [
      %{label: "GitHub", url: "https://github.com/hjosugi"}
    ],
    projects: [
      %{
        name: "Example Project",
        url: "https://github.com/hjosugi/example",
        docs_url: "https://example.com/docs",
        demo_url: "",
        summary: "An example project.",
        stack: ["Elixir"],
        highlights: ["Static export"],
        featured: true
      }
    ]
  }

  test "feed_weight falls back to a default for the kind" do
    assert Config.feed_weight(%{kind: "aggregator"}) == 1.3
    assert Config.feed_weight(%{kind: "official"}) == 1.0
    assert Config.feed_weight(%{kind: "unknown"}) == 1.0
    assert Config.feed_weight(%{}) == 1.0
  end

  test "an explicit weight overrides the kind default" do
    assert Config.feed_weight(%{kind: "official", weight: 1.4}) == 1.4
  end

  test "loads a valid feeds config unchanged", %{tmp_dir: tmp_dir} do
    path = write_config!(tmp_dir, "feeds.exs", @valid_feeds)

    assert Config.feeds(path) == @valid_feeds
  end

  test "feeds config reports entry index and id for missing required values", %{tmp_dir: tmp_dir} do
    path =
      write_config!(tmp_dir, "feeds.exs", [
        @valid_feed,
        @second_valid_feed,
        %{id: "foo", name: "Foo", kind: "official"}
      ])

    assert_raise ArgumentError, ~r/feeds\.exs entry 3 \(id: foo\) missing :url\./, fn ->
      Config.feeds(path)
    end
  end

  test "feeds config rejects duplicate ids", %{tmp_dir: tmp_dir} do
    path =
      write_config!(tmp_dir, "feeds.exs", [
        Map.merge(@valid_feed, %{id: "foo"}),
        Map.merge(@second_valid_feed, %{id: "foo"})
      ])

    assert_raise ArgumentError,
                 ~r/feeds\.exs entry 2 \(id: foo\) duplicates :id from entry 1\./,
                 fn ->
                   Config.feeds(path)
                 end
  end

  test "feeds config validates url kind and weight", %{tmp_dir: tmp_dir} do
    path =
      write_config!(tmp_dir, "feeds.exs", [
        Map.merge(@valid_feed, %{
          id: "foo",
          url: "ftp://example.com/feed.xml",
          kind: "personal",
          weight: "high"
        })
      ])

    error = assert_raise ArgumentError, fn -> Config.feeds(path) end

    assert error.message =~ "feeds.exs entry 1 (id: foo) :url must be an http(s) URL."
    assert error.message =~ "feeds.exs entry 1 (id: foo) has unknown :kind \"personal\""
    assert error.message =~ "feeds.exs entry 1 (id: foo) :weight must be numeric."
  end

  test "loads a valid site config unchanged", %{tmp_dir: tmp_dir} do
    path = write_config!(tmp_dir, "site.exs", @valid_site)

    assert Config.site(path) == @valid_site
  end

  test "site config validates handle links and projects", %{tmp_dir: tmp_dir} do
    path =
      write_config!(
        tmp_dir,
        "site.exs",
        Map.merge(@valid_site, %{
          handle: "bad handle",
          links: [%{label: "GitHub"}],
          projects: [
            %{
              name: "Bad Project",
              url: "not-a-url",
              summary: "Malformed project.",
              stack: "Elixir",
              highlights: ["ok", 1],
              featured: "yes"
            }
          ]
        })
      )

    error = assert_raise ArgumentError, fn -> Config.site(path) end

    assert error.message =~
             "site.exs :handle must contain only letters, numbers, underscores, dots, or hyphens."

    assert error.message =~ "site.exs :links entry 1 missing :url."

    assert error.message =~
             "site.exs :projects entry 1 (name: Bad Project) :url must be an http(s) URL."

    assert error.message =~
             "site.exs :projects entry 1 (name: Bad Project) :stack must be a list of strings."

    assert error.message =~
             "site.exs :projects entry 1 (name: Bad Project) :highlights must be a list of strings."

    assert error.message =~
             "site.exs :projects entry 1 (name: Bad Project) :featured must be a boolean."
  end

  defp write_config!(tmp_dir, filename, value) do
    path = Path.join(tmp_dir, filename)
    File.write!(path, inspect(value, pretty: true, limit: :infinity, printable_limit: :infinity))
    path
  end
end
