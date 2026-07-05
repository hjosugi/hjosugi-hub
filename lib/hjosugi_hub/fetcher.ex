defmodule HjosugiHub.Fetcher do
  @moduledoc false
  @behaviour HjosugiHub.Fetcher.Behaviour

  alias HjosugiHub.FeedParser

  @max_feed_bytes 5 * 1024 * 1024

  def fetch(feed, timeout_ms) do
    case fetch(feed, timeout_ms, %{}) do
      {:ok, items, status, _metadata} -> {:ok, items, status}
      {:not_modified, status, _metadata} -> {:error, "unexpected HTTP status #{status}", status}
      {:error, reason, status} -> {:error, reason, status}
    end
  end

  def fetch(feed, timeout_ms, validators) do
    with :ok <- validate_url(feed.url) do
      _ = Application.ensure_all_started(:ssl)
      _ = Application.ensure_all_started(:inets)

      request = {String.to_charlist(feed.url), headers(validators)}
      http_options = http_options(timeout_ms)
      options = [sync: false, stream: {:self, :once}]

      case :httpc.request(:get, request, http_options, options) do
        {:ok, request_id} ->
          receive_response(request_id, feed, timeout_ms, validators)

        {:error, reason} ->
          {:error, inspect(reason), 0}
      end
    end
  end

  defp receive_response(request_id, feed, timeout_ms, validators) do
    receive do
      {:http, {^request_id, :stream_start, headers, handler_pid}} ->
        if content_too_large?(headers) do
          cancel_request(request_id)
          {:error, "feed exceeds #{@max_feed_bytes} bytes", 200}
        else
          :httpc.stream_next(handler_pid)
          metadata = response_metadata(headers, validators)
          receive_stream(request_id, handler_pid, feed, timeout_ms, metadata, [], 0)
        end

      {:http, {^request_id, {{_version, 304, _reason}, headers, _body}}} ->
        {:not_modified, 304, response_metadata(headers, validators)}

      {:http, {^request_id, {{_version, status, _reason}, headers, body}}}
      when status in 200..299 ->
        parse_body(
          IO.iodata_to_binary(body),
          feed,
          status,
          response_metadata(headers, validators)
        )

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

  defp receive_stream(request_id, handler_pid, feed, timeout_ms, metadata, chunks, size) do
    receive do
      {:http, {^request_id, :stream, chunk}} ->
        chunk = IO.iodata_to_binary(chunk)
        new_size = size + byte_size(chunk)

        if new_size > @max_feed_bytes do
          cancel_request(request_id)
          {:error, "feed exceeds #{@max_feed_bytes} bytes", 200}
        else
          :httpc.stream_next(handler_pid)

          receive_stream(
            request_id,
            handler_pid,
            feed,
            timeout_ms,
            metadata,
            [chunk | chunks],
            new_size
          )
        end

      {:http, {^request_id, :stream_end, _headers}} ->
        chunks
        |> Enum.reverse()
        |> IO.iodata_to_binary()
        |> parse_body(feed, 200, metadata)

      {:http, {^request_id, {:error, reason}}} ->
        {:error, inspect(reason), 0}
    after
      timeout_ms ->
        cancel_request(request_id)
        {:error, "request timed out", 0}
    end
  end

  defp parse_body(body, feed, status, metadata) do
    if byte_size(body) > @max_feed_bytes do
      {:error, "feed exceeds #{@max_feed_bytes} bytes", status}
    else
      case FeedParser.parse(body, feed) do
        {:ok, items} -> {:ok, items, status, metadata}
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

  defp response_metadata(headers, previous) do
    %{}
    |> maybe_put(:etag, header_value(headers, "etag") || validator_value(previous, :etag))
    |> maybe_put(
      :last_modified,
      header_value(headers, "last-modified") || validator_value(previous, :last_modified)
    )
  end

  defp header_value(headers, header_name) do
    Enum.find_value(headers, fn
      {name, value} ->
        if name |> to_string() |> String.downcase() == header_name do
          value |> to_string() |> String.trim()
        end

      _other ->
        nil
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

  defp headers(validators) do
    base_headers = [
      {~c"user-agent", ~c"hjosugi-hub/0.3 (+https://github.com/hjosugi/hjosugi-hub)"},
      {~c"accept",
       ~c"application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.1"}
    ]

    base_headers ++ conditional_headers(validators)
  end

  defp conditional_headers(validators) do
    []
    |> maybe_header(~c"if-none-match", validator_value(validators, :etag))
    |> maybe_header(~c"if-modified-since", validator_value(validators, :last_modified))
  end

  defp validator_value(validators, key),
    do: Map.get(validators, key) || Map.get(validators, to_string(key))

  defp maybe_header(headers, _name, nil), do: headers
  defp maybe_header(headers, _name, ""), do: headers
  defp maybe_header(headers, name, value), do: headers ++ [{name, String.to_charlist(value)}]
end
