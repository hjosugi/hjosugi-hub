defmodule HjosugiHub.Util do
  @moduledoc """
  Normalization helpers shared across collection, storage, and rendering.

  This module handles stable IDs, URL/text/date/tag normalization, summary
  trimming, and item time fallback. It does not perform file or network I/O.
  """

  @tag_trim ~r/[-\/#]+$/u
  @html_decode_passes 2
  @html_entity_ref ~r/&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);/u
  @tracking_query_params ~w(dclid fbclid gbraid gclid igshid mc_cid mc_eid mkt_tok msclkid wbraid)
  @html_named_entities %{
    "amp" => "&",
    "apos" => "'",
    "bull" => <<0x2022::utf8>>,
    "copy" => <<0x00A9::utf8>>,
    "euro" => <<0x20AC::utf8>>,
    "gt" => ">",
    "hellip" => <<0x2026::utf8>>,
    "laquo" => <<0x00AB::utf8>>,
    "ldquo" => <<0x201C::utf8>>,
    "lsquo" => <<0x2018::utf8>>,
    "lt" => "<",
    "mdash" => <<0x2014::utf8>>,
    "middot" => <<0x00B7::utf8>>,
    "nbsp" => " ",
    "ndash" => <<0x2013::utf8>>,
    "quot" => "\"",
    "raquo" => <<0x00BB::utf8>>,
    "rdquo" => <<0x201D::utf8>>,
    "reg" => <<0x00AE::utf8>>,
    "rsquo" => <<0x2019::utf8>>,
    "trade" => <<0x2122::utf8>>
  }

  # RSS dates follow RFC 822, e.g. "Fri, 13 Nov 2026 12:58:00 -0800". The
  # weekday, seconds, and zone are optional and the day may be one digit.
  @rfc822_date ~r/\A(?:[a-z]+,?\s*)?(?<day>\d{1,2})\s+(?<month>[a-z]{3})[a-z]*\.?\s+(?<year>\d{4})\s+(?<hour>\d{1,2}):(?<minute>\d{2})(?::(?<second>\d{2}))?(?:\s*(?<zone>[+-]\d{2}:?\d{2}|[a-z]+))?\s*\z/i
  @rfc822_offset ~r/\A(?<sign>[+-])(?<hours>\d{2}):?(?<minutes>\d{2})\z/
  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)
  # Offsets in minutes for the zone names RFC 822 defines. Unknown names are
  # read as UTC, which is what the old parser did for every zone.
  @rfc822_zones %{
    "EST" => -300,
    "EDT" => -240,
    "CST" => -360,
    "CDT" => -300,
    "MST" => -420,
    "MDT" => -360,
    "PST" => -480,
    "PDT" => -420
  }

  def stable_id(source_id, raw_id) do
    :crypto.hash(:sha256, source_id <> <<0>> <> raw_id)
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end

  def normalize_url(nil), do: ""

  def normalize_url(value) do
    value = value |> to_string() |> String.trim()

    case URI.parse(value) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        uri
        |> Map.merge(%{
          authority: nil,
          fragment: nil,
          host: normalize_host(host),
          path: normalize_path(uri.path),
          port: normalize_port(scheme, uri.port),
          query: normalize_query(uri.query),
          scheme: normalize_scheme(scheme),
          userinfo: nil
        })
        |> URI.to_string()

      _ ->
        value
    end
  end

  def clean_text(value) do
    value
    |> to_string()
    |> strip_tags()
    |> html_decode()
    # Some feeds (e.g. Lobsters) entity-escape their HTML, so decoding reveals
    # a second layer of tags that needs stripping too.
    |> strip_tags()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp strip_tags(value), do: String.replace(value, ~r/<[^>]*>/u, " ")

  def summarize(value, max \\ 360) do
    value = String.trim(value || "")

    cond do
      value == "" -> "No summary provided by the source."
      String.length(value) <= max -> value
      true -> String.slice(value, 0, max) |> String.trim() |> Kernel.<>("...")
    end
  end

  def truncate(value, max) do
    value = String.trim(value || "")

    if String.length(value) <= max do
      value
    else
      value |> String.slice(0, max) |> String.trim() |> Kernel.<>("...")
    end
  end

  def merge_tags(groups) do
    groups
    |> List.flatten()
    |> Enum.map(&normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def normalize_tag(tag) do
    tag
    |> to_string()
    |> String.downcase()
    |> String.replace("_", "-")
    |> String.split()
    |> Enum.join("-")
    |> String.trim("-/#")
    |> String.replace(@tag_trim, "")
  end

  def parse_date(value) do
    value = String.trim(value || "")

    parse_iso_datetime(value) ||
      parse_iso_date(value) ||
      parse_rfc822_date(value)
  end

  def item_time(item) do
    item.published_at || item.collected_at || DateTime.from_unix!(0)
  end

  @doc "Stringifies and trims a value; `nil` becomes an empty string."
  def trim(nil), do: ""
  def trim(value), do: value |> to_string() |> String.trim()

  @doc """
  Joins a site-relative path onto the public base URL.

  Returns an empty string when no base URL is configured, so callers can drop
  absolute links from exports that do not know where they will be hosted.
  """
  def absolute_url("", _path), do: ""
  def absolute_url(base_url, path), do: base_url <> "/" <> String.trim_leading(path, "/")

  defp parse_iso_datetime(""), do: nil

  defp parse_iso_datetime(value) do
    normalized = String.replace_suffix(value, "Z", "+00:00")

    case DateTime.from_iso8601(normalized) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_iso_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_rfc822_date(value) do
    with %{} = parts <- Regex.named_captures(@rfc822_date, value),
         month when month > 0 <- month_number(parts["month"]),
         {:ok, date} <- Date.new(int(parts["year"]), month, int(parts["day"])),
         {:ok, time} <- Time.new(int(parts["hour"]), int(parts["minute"]), int(parts["second"])),
         {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
      DateTime.add(datetime, -zone_offset_minutes(parts["zone"]), :minute)
    else
      _ -> nil
    end
  end

  defp month_number(name) do
    case Enum.find_index(@months, &(&1 == String.downcase(name))) do
      nil -> 0
      index -> index + 1
    end
  end

  defp zone_offset_minutes(zone) do
    case Regex.named_captures(@rfc822_offset, zone) do
      %{"sign" => sign, "hours" => hours, "minutes" => minutes} ->
        total = int(hours) * 60 + int(minutes)
        if sign == "-", do: -total, else: total

      nil ->
        Map.get(@rfc822_zones, String.upcase(zone), 0)
    end
  end

  defp int(""), do: 0
  defp int(digits), do: String.to_integer(digits)

  defp html_decode(value), do: html_decode(value, @html_decode_passes)
  defp html_decode(value, 0), do: value

  defp html_decode(value, passes_left) do
    decoded =
      Regex.replace(@html_entity_ref, value, fn match, entity ->
        decode_html_entity(entity) || match
      end)

    if decoded == value do
      decoded
    else
      html_decode(decoded, passes_left - 1)
    end
  end

  defp decode_html_entity("#x" <> hex), do: decode_numeric_reference(hex, 16)
  defp decode_html_entity("#X" <> hex), do: decode_numeric_reference(hex, 16)
  defp decode_html_entity("#" <> decimal), do: decode_numeric_reference(decimal, 10)
  defp decode_html_entity(name), do: Map.get(@html_named_entities, name)

  defp decode_numeric_reference(value, base) do
    case Integer.parse(value, base) do
      {codepoint, ""} -> encode_codepoint(codepoint)
      _ -> nil
    end
  end

  defp encode_codepoint(codepoint)
       when codepoint in [0x09, 0x0A, 0x0D] or
              (codepoint >= 0x20 and codepoint <= 0xD7FF) or
              (codepoint >= 0xE000 and codepoint <= 0x10FFFF) do
    <<codepoint::utf8>>
  end

  defp encode_codepoint(_codepoint), do: nil

  defp normalize_scheme(scheme) do
    case String.downcase(scheme) do
      "http" -> "https"
      "https" -> "https"
      normalized -> normalized
    end
  end

  defp normalize_host(host) do
    host
    |> String.downcase()
    |> String.replace_prefix("www.", "")
  end

  defp normalize_port(scheme, port) do
    case {String.downcase(scheme), port} do
      {"http", 80} -> nil
      {"https", 443} -> nil
      _ -> port
    end
  end

  defp normalize_path(nil), do: ""

  defp normalize_path(path) do
    String.trim_trailing(path, "/")
  end

  defp normalize_query(nil), do: nil
  defp normalize_query(""), do: nil

  defp normalize_query(query) do
    params =
      query
      |> URI.query_decoder()
      |> Enum.reject(fn {key, _value} -> tracking_query_param?(key) end)
      |> Enum.sort_by(fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value || "")}
      end)

    case params do
      [] -> nil
      params -> URI.encode_query(params)
    end
  rescue
    _ -> query
  end

  defp tracking_query_param?(key) do
    normalized = key |> to_string() |> String.downcase()

    String.starts_with?(normalized, "utm_") or normalized in @tracking_query_params
  end
end
