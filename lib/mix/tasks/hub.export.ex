defmodule Mix.Tasks.Hub.Export do
  use Mix.Task

  @shortdoc "Export the static GitHub Pages site"

  alias HjosugiHub.{CLI, Config, Renderer, Store}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts =
      CLI.parse_options!(args,
        site: :string,
        feeds: :string,
        cache: :string,
        data: :string,
        out: :string,
        base_url: :string
      )

    site = Config.site(Keyword.get(opts, :site, "config/site.exs"))
    feeds = Config.feeds(Keyword.get(opts, :feeds, "config/feeds.exs"))
    cache_path = CLI.cache_path(opts, "radar-cache/items.term")
    items = Store.read_items(cache_path)
    out_dir = Keyword.get(opts, :out, "public")
    base_url = Keyword.get(opts, :base_url, System.get_env("PUBLIC_BASE_URL", ""))

    Renderer.export(site, feeds, items, out_dir, base_url)
    Mix.shell().info("exported static site: out=#{out_dir} items=#{length(items)}")
  end
end
