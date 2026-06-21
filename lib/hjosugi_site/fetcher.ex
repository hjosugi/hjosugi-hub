defmodule HjosugiSite.Fetcher do
  @moduledoc false

  alias HjosugiSite.FeedParser

  @max_feed_bytes 5 * 1024 * 1024

  def fetch(feed, timeout_ms) do
    with :ok <- validate_url(feed.url) do
      _ = Application.ensure_all_started(:ssl)
      _ = Application.ensure_all_started(:inets)

      request = {String.to_charlist(feed.url), headers()}
      http_options = [timeout: timeout_ms, connect_timeout: timeout_ms, autoredirect: true]
      options = [body_format: :binary]

      case :httpc.request(:get, request, http_options, options) do
        {:ok, {{_version, status, _reason}, _headers, body}} when status in 200..299 ->
          parse_body(body, feed, status)

        {:ok, {{_version, status, _reason}, _headers, _body}} ->
          {:error, "unexpected HTTP status #{status}", status}

        {:error, reason} ->
          {:error, inspect(reason), 0}
      end
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
      {~c"user-agent", ~c"hjosugi-site/0.2 (+https://github.com/hjosugi/hjosugi-site)"},
      {~c"accept", ~c"application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.1"}
    ]
  end
end
