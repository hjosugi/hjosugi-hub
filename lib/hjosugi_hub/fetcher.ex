defmodule HjosugiHub.Fetcher do
  @moduledoc false
  @behaviour HjosugiHub.Fetcher.Behaviour

  alias HjosugiHub.FeedParser

  @max_feed_bytes 5 * 1024 * 1024

  def fetch(feed, timeout_ms) do
    with :ok <- validate_url(feed.url) do
      _ = Application.ensure_all_started(:ssl)
      _ = Application.ensure_all_started(:inets)

      request = {String.to_charlist(feed.url), headers()}
      http_options = http_options(timeout_ms)
      options = [sync: false, stream: {:self, :once}]

      case :httpc.request(:get, request, http_options, options) do
        {:ok, request_id} ->
          receive_response(request_id, feed, timeout_ms)

        {:error, reason} ->
          {:error, inspect(reason), 0}
      end
    end
  end

  defp receive_response(request_id, feed, timeout_ms) do
    receive do
      {:http, {^request_id, :stream_start, headers, handler_pid}} ->
        if content_too_large?(headers) do
          cancel_request(request_id)
          {:error, "feed exceeds #{@max_feed_bytes} bytes", 200}
        else
          :httpc.stream_next(handler_pid)
          receive_stream(request_id, handler_pid, feed, timeout_ms, [], 0)
        end

      {:http, {^request_id, {{_version, status, _reason}, _headers, body}}}
      when status in 200..299 ->
        parse_body(IO.iodata_to_binary(body), feed, status)

      {:http, {^request_id, {{_version, status, _reason}, _headers, _body}}} ->
        {:error, "unexpected HTTP status #{status}", status}

      {:http, {^request_id, {:error, reason}}} ->
        {:error, inspect(reason), 0}
    after
      timeout_ms ->
        cancel_request(request_id)
        {:error, "request timed out", 0}
    end
  end

  defp receive_stream(request_id, handler_pid, feed, timeout_ms, chunks, size) do
    receive do
      {:http, {^request_id, :stream, chunk}} ->
        chunk = IO.iodata_to_binary(chunk)
        new_size = size + byte_size(chunk)

        if new_size > @max_feed_bytes do
          cancel_request(request_id)
          {:error, "feed exceeds #{@max_feed_bytes} bytes", 200}
        else
          :httpc.stream_next(handler_pid)
          receive_stream(request_id, handler_pid, feed, timeout_ms, [chunk | chunks], new_size)
        end

      {:http, {^request_id, :stream_end, _headers}} ->
        chunks
        |> Enum.reverse()
        |> IO.iodata_to_binary()
        |> parse_body(feed, 200)

      {:http, {^request_id, {:error, reason}}} ->
        {:error, inspect(reason), 0}
    after
      timeout_ms ->
        cancel_request(request_id)
        {:error, "request timed out", 0}
    end
  end

  defp parse_body(body, feed, status) do
    if byte_size(body) > @max_feed_bytes do
      {:error, "feed exceeds #{@max_feed_bytes} bytes", status}
    else
      case FeedParser.parse(body, feed) do
        {:ok, items} -> {:ok, items, status}
        {:error, reason} -> {:error, reason, status}
      end
    end
  end

  defp content_too_large?(headers) do
    case content_length(headers) do
      bytes when is_integer(bytes) -> bytes > @max_feed_bytes
      nil -> false
    end
  end

  defp content_length(headers) do
    Enum.find_value(headers, fn
      {name, value} ->
        if name |> to_string() |> String.downcase() == "content-length" do
          parse_content_length(value)
        end

      _other ->
        nil
    end)
  end

  defp parse_content_length(value) do
    case value |> to_string() |> String.trim() |> Integer.parse() do
      {bytes, ""} when bytes >= 0 -> bytes
      _ -> nil
    end
  end

  defp cancel_request(request_id) do
    _ = :httpc.cancel_request(request_id)
    :ok
  end

  @doc false
  def http_options(timeout_ms) do
    [
      timeout: timeout_ms,
      connect_timeout: timeout_ms,
      autoredirect: true,
      ssl: ssl_options()
    ]
  end

  defp ssl_options do
    # :httpc does not verify server certificates unless TLS verification is configured.
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp validate_url(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) do
      :ok
    else
      {:error, "feed URL must use http or https and include a host", 0}
    end
  end

  defp headers do
    [
      {~c"user-agent", ~c"hjosugi-hub/0.3 (+https://github.com/hjosugi/hjosugi-hub)"},
      {~c"accept",
       ~c"application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.1"}
    ]
  end
end
