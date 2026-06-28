defmodule Mix.Tasks.Hub.Export do
  use Mix.Task

  @shortdoc "Export the static GitHub Pages site"

  alias HjosugiHub.{Config, Renderer, Store}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          site: :string,
          feeds: :string,
          cache: :string,
          data: :string,
          out: :string,
          base_url: :string
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    site = Config.site(Keyword.get(opts, :site, "config/site.exs"))
    feeds = Config.feeds(Keyword.get(opts, :feeds, "config/feeds.exs"))
    cache_path = Keyword.get(opts, :cache, Keyword.get(opts, :data, "radar-cache/items.term"))
    items = Store.read_items(cache_path)
    out_dir = Keyword.get(opts, :out, "public")
    base_url = Keyword.get(opts, :base_url, System.get_env("PUBLIC_BASE_URL", ""))

    Renderer.export(site, feeds, items, out_dir, base_url)
    Mix.shell().info("exported static site: out=#{out_dir} items=#{length(items)}")
  end
end
