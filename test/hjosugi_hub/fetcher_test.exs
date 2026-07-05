defmodule HjosugiHub.FetcherTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Fetcher

  @max_feed_bytes 5 * 1024 * 1024

  test "http options configure TLS certificate verification for httpc" do
    options = Fetcher.http_options(1_000)

    assert options[:timeout] == 1_000
    assert options[:connect_timeout] == 1_000
    assert options[:autoredirect] == true

    assert ssl_options = options[:ssl]
    assert ssl_options[:verify] == :verify_peer
    assert ssl_options[:cacerts] == :public_key.cacerts_get()

    assert ssl_options[:customize_hostname_check][:match_fun] ==
             :public_key.pkix_verify_hostname_match_fun(:https)
  end

  test "fetch parses a normal streamed feed response" do
    body = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Streamed feed item</title>
          <link>/items/1</link>
          <guid>streamed-1</guid>
          <description>Small body</description>
        </item>
      </channel>
    </rss>
    """

    {url, ref} =
      start_http_server(fn socket ->
        send_response(socket, [{"Content-Length", byte_size(body)}], body)
      end)

    feed = %{id: "streamed", name: "Streamed Feed", url: url, kind: "rss", tags: []}

    assert {:ok, [item], 200} = Fetcher.fetch(feed, 5_000)
    assert item.title == "Streamed feed item"
    assert item.url == url |> URI.parse() |> URI.merge("/items/1") |> URI.to_string()
    assert_receive {:http_stub_done, ^ref, {:sent, bytes}}, 1_000
    assert bytes == byte_size(body)
  end

  test "fetch/3 stores response validators from a successful response" do
    body = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Validator item</title>
          <link>https://example.com/validator</link>
          <guid>validator-1</guid>
          <description>Small body</description>
        </item>
      </channel>
    </rss>
    """

    last_modified = "Sat, 20 Jun 2026 10:00:00 GMT"

    {url, ref} =
      start_http_server(fn socket ->
        send_response(
          socket,
          [
            {"ETag", ~s("feed-v1")},
            {"Last-Modified", last_modified},
            {"Content-Length", byte_size(body)}
          ],
          body
        )
      end)

    feed = %{id: "validator", name: "Validator Feed", url: url, kind: "rss", tags: []}

    assert {:ok, [_item], 200, metadata} = Fetcher.fetch(feed, 5_000, %{})
    assert metadata == %{etag: ~s("feed-v1"), last_modified: last_modified}
    assert_receive {:http_stub_done, ^ref, {:sent, _bytes}}, 1_000
  end

  test "fetch/3 sends validators and reports not-modified responses" do
    last_modified = "Sat, 20 Jun 2026 10:00:00 GMT"

    {url, ref} =
      start_http_server(fn socket, request ->
        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 304 Not Modified\r\n",
            "ETag: \"feed-v1\"\r\n",
            "Last-Modified: ",
            last_modified,
            "\r\n\r\n"
          ])

        :gen_tcp.close(socket)
        {:request, request}
      end)

    feed = %{id: "cached", name: "Cached Feed", url: url, kind: "rss", tags: []}

    assert {:not_modified, 304, metadata} =
             Fetcher.fetch(feed, 5_000, %{etag: ~s("feed-v1"), last_modified: last_modified})

    assert metadata == %{etag: ~s("feed-v1"), last_modified: last_modified}
    assert_receive {:http_stub_done, ^ref, {:request, request}}, 1_000

    request = String.downcase(request)
    assert request =~ "if-none-match: \"feed-v1\""
    assert request =~ "if-modified-since: #{String.downcase(last_modified)}"
  end

  test "fetch reports httpd 404 responses as HTTP errors" do
    base_url = start_httpd(%{})

    feed = %{
      id: "missing",
      name: "Missing Feed",
      url: "#{base_url}/missing.xml",
      kind: "rss",
      tags: []
    }

    assert {:error, "unexpected HTTP status 404", 404} = Fetcher.fetch(feed, 5_000)
  end

  test "fetch follows httpd redirects and parses the final feed" do
    body = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Redirected feed item</title>
          <link>/redirected/1</link>
          <guid>redirected-1</guid>
          <description>Arrived after redirect</description>
        </item>
      </channel>
    </rss>
    """

    base_url = start_httpd(%{"redirected/index.xml" => body})

    feed = %{
      id: "redirected",
      name: "Redirected Feed",
      url: "#{base_url}/redirected",
      kind: "rss",
      tags: []
    }

    assert {:ok, [item], 200} = Fetcher.fetch(feed, 5_000)
    assert item.title == "Redirected feed item"
    assert item.url == "#{base_url}/redirected/1"
  end

  test "fetch times out when a server accepts the request but delays the response" do
    {url, ref} =
      start_http_server(fn socket ->
        Process.sleep(250)

        result =
          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\n",
            "Content-Type: application/rss+xml\r\n",
            "Content-Length: 0\r\n\r\n"
          ])

        :gen_tcp.close(socket)
        {:delayed, result}
      end)

    feed = %{id: "slow", name: "Slow Feed", url: url, kind: "rss", tags: []}

    assert {:error, "request timed out", 0} = Fetcher.fetch(feed, 50)
    assert_receive {:http_stub_done, ^ref, {:delayed, _result}}, 1_000
  end

  test "rejects oversized content-length before downloading the body" do
    {url, ref} =
      start_http_server(fn socket ->
        headers = [{"Content-Length", @max_feed_bytes + 1}]
        :ok = send_headers(socket, headers)
        Process.sleep(250)
        :gen_tcp.close(socket)
        {:sent, 0}
      end)

    feed = %{id: "huge", name: "Huge Feed", url: url, kind: "rss", tags: []}
    error = "feed exceeds #{@max_feed_bytes} bytes"

    assert {:error, ^error, 200} = Fetcher.fetch(feed, 5_000)
    assert_receive {:http_stub_done, ^ref, {:sent, 0}}, 1_000
  end

  test "cancels a response while streaming once the feed byte limit is exceeded" do
    total_bytes = @max_feed_bytes + 1_000_000

    {url, ref} =
      start_http_server(fn socket ->
        :ok = send_headers(socket, [])
        stream_body(socket, total_bytes, 64 * 1024)
      end)

    feed = %{id: "huge-stream", name: "Huge Stream", url: url, kind: "rss", tags: []}
    error = "feed exceeds #{@max_feed_bytes} bytes"

    assert {:error, ^error, 200} = Fetcher.fetch(feed, 10_000)
    assert_receive {:http_stub_done, ^ref, result}, 5_000

    assert {:closed, _reason, sent_bytes} = result
    assert sent_bytes < total_bytes
  end

  defp start_httpd(files) do
    :ok = ensure_started(:inets)

    root =
      Path.join(System.tmp_dir!(), "hjosugi-hub-httpd-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    Enum.each(files, fn {relative_path, body} ->
      path = Path.join(root, relative_path)
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, body)
    end)

    {:ok, pid} =
      :inets.start(:httpd,
        port: 0,
        bind_address: {127, 0, 0, 1},
        server_name: ~c"hjosugi-hub-fetcher-test",
        server_root: String.to_charlist(root),
        document_root: String.to_charlist(root),
        directory_index: [~c"index.xml"],
        modules: [:mod_alias, :mod_get],
        mime_types: [{~c"xml", ~c"application/rss+xml"}]
      )

    port = Keyword.fetch!(:httpd.info(pid), :port)

    on_exit(fn ->
      :inets.stop(:httpd, pid)
      File.rm_rf(root)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp ensure_started(application) do
    case Application.ensure_all_started(application) do
      {:ok, _started} -> :ok
      {:error, {:already_started, ^application}} -> :ok
    end
  end

  defp start_http_server(responder) do
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
        result =
          with {:ok, socket} <- :gen_tcp.accept(listen_socket),
               {:ok, request} <- :gen_tcp.recv(socket, 0, 5_000) do
            call_responder(responder, socket, request)
          end

        send(parent, {:http_stub_done, ref, result})
        :gen_tcp.close(listen_socket)
      end)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
      :gen_tcp.close(listen_socket)
    end)

    {"http://127.0.0.1:#{port}/feed.xml", ref}
  end

  defp call_responder(responder, socket, request) do
    case :erlang.fun_info(responder, :arity) do
      {:arity, 1} -> responder.(socket)
      {:arity, 2} -> responder.(socket, request)
    end
  end

  defp send_response(socket, headers, body) do
    :ok = send_headers(socket, headers)
    :ok = :gen_tcp.send(socket, body)
    :gen_tcp.close(socket)
    {:sent, byte_size(body)}
  end

  defp send_headers(socket, headers) do
    header_lines =
      [{"Content-Type", "application/rss+xml"} | headers]
      |> Enum.map(fn {name, value} -> "#{name}: #{value}\r\n" end)

    :gen_tcp.send(socket, ["HTTP/1.1 200 OK\r\n", header_lines, "\r\n"])
  end

  defp stream_body(socket, total_bytes, chunk_size),
    do: stream_body(socket, total_bytes, chunk_size, 0)

  defp stream_body(_socket, total_bytes, _chunk_size, sent_bytes) when sent_bytes >= total_bytes,
    do: {:sent, sent_bytes}

  defp stream_body(socket, total_bytes, chunk_size, sent_bytes) do
    bytes = min(chunk_size, total_bytes - sent_bytes)
    chunk = :binary.copy("x", bytes)

    case :gen_tcp.send(socket, chunk) do
      :ok ->
        Process.sleep(2)
        stream_body(socket, total_bytes, chunk_size, sent_bytes + bytes)

      {:error, reason} ->
        {:closed, reason, sent_bytes}
    end
  end
end
