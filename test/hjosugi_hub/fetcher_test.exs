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
               {:ok, _request} <- :gen_tcp.recv(socket, 0, 5_000) do
            responder.(socket)
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
