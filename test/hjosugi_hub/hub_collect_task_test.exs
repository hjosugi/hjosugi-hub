defmodule Mix.Tasks.Hub.CollectTest do
  use ExUnit.Case, async: false

  alias HjosugiHub.Store
  alias Mix.Tasks.Hub.Collect

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(shell)
      Mix.Task.reenable("app.start")
    end)

    :ok
  end

  test "--only with --dry-run collects selected feeds without writing outputs" do
    body = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Dry-run item</title>
          <link>https://example.com/dry-run</link>
          <guid>dry-run-1</guid>
          <description>Collected without writing cache.</description>
        </item>
      </channel>
    </rss>
    """

    {url, ref} = start_http_server(body)
    tmp_dir = tmp_dir()
    feeds_path = Path.join(tmp_dir, "feeds.exs")
    cache_path = Path.join(tmp_dir, "items.term")
    json_path = Path.join(tmp_dir, "items.json")
    report_path = Path.join(tmp_dir, "report.json")

    write_feeds!(feeds_path, [
      %{id: "selected", name: "Selected Feed", url: url, kind: "official", tags: []},
      %{
        id: "skipped",
        name: "Skipped Feed",
        url: "http://127.0.0.1:1/skipped.xml",
        kind: "official",
        tags: []
      }
    ])

    try do
      Collect.run([
        "--feeds",
        feeds_path,
        "--cache",
        cache_path,
        "--json",
        json_path,
        "--report",
        report_path,
        "--only",
        "selected",
        "--dry-run",
        "--timeout",
        "5000",
        "--workers",
        "1"
      ])

      assert_receive {:http_stub_done, ^ref}, 1_000
      refute File.exists?(cache_path)
      refute File.exists?(json_path)
      refute File.exists?(report_path)

      assert_received {:mix_shell, :info, ["dry-run: not writing cache, JSON, or report files"]}
      assert_received {:mix_shell, :info, ["collected feeds: fresh=1 failed=0 total=1"]}
      assert_received {:mix_shell, :info, ["source selected: code=200 items=1"]}

      assert_received {:mix_shell, :info,
                       ["sample selected: Dry-run item <https://example.com/dry-run>"]}
    after
      File.rm_rf(tmp_dir)
    end
  end

  test "--only reports unknown feed ids clearly" do
    tmp_dir = tmp_dir()
    feeds_path = Path.join(tmp_dir, "feeds.exs")
    write_feeds!(feeds_path, [%{id: "known", name: "Known", url: "https://example.com/feed.xml"}])

    try do
      assert_raise Mix.Error, ~r/--only references unknown feed id\(s\): missing/, fn ->
        Collect.run(["--feeds", feeds_path, "--only", "missing", "--dry-run"])
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  test "writes failure report and raises when min-success is not met" do
    tmp_dir = tmp_dir()
    feeds_path = Path.join(tmp_dir, "feeds.exs")
    cache_path = Path.join(tmp_dir, "items.term")
    json_path = Path.join(tmp_dir, "items.json")
    report_path = Path.join(tmp_dir, "report.json")

    write_feeds!(feeds_path, [
      %{
        id: "down",
        name: "Down Feed",
        url: "http://127.0.0.1:1/down.xml",
        kind: "official",
        tags: []
      }
    ])

    try do
      assert_raise Mix.Error, ~r/successful_sources=0 is below --min-success=1/, fn ->
        Collect.run([
          "--feeds",
          feeds_path,
          "--cache",
          cache_path,
          "--json",
          json_path,
          "--report",
          report_path,
          "--timeout",
          "100",
          "--workers",
          "1",
          "--min-success",
          "1"
        ])
      end

      assert File.exists?(cache_path)
      assert File.exists?(json_path)
      assert File.exists?(report_path)

      report = JSON.decode!(File.read!(report_path))
      assert report["status"] == "critical"
      assert report["enabled_sources"] == 1
      assert report["successful_sources"] == 0
      assert report["failed_sources"] == 1
      assert [%{"status" => "error", "consecutive_failures" => 1}] = report["sources"]

      feed_state = Store.read_feed_state(Store.feed_state_path(cache_path))

      assert Map.take(feed_state["down"], [:consecutive_failures, :last_status]) == %{
               consecutive_failures: 1,
               last_status: "error"
             }
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp tmp_dir do
    Path.join(System.tmp_dir!(), "hjosugi-hub-collect-test-#{System.unique_integer([:positive])}")
  end

  defp write_feeds!(path, feeds) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, inspect(feeds, pretty: true, limit: :infinity))
  end

  defp start_http_server(body) do
    parent = self()
    ref = make_ref()

    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listen_socket)

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\n",
            "Content-Type: application/rss+xml\r\n",
            "Content-Length: ",
            Integer.to_string(byte_size(body)),
            "\r\n\r\n",
            body
          ])

        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
        send(parent, {:http_stub_done, ref})
      end)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
      :gen_tcp.close(listen_socket)
    end)

    {"http://127.0.0.1:#{port}/feed.xml", ref}
  end
end
