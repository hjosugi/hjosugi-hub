defmodule HjosugiHub.Util do
  @moduledoc false

  @tag_trim ~r/[-\/#]+$/u
  @html_decode_passes 2
  @html_entity_ref ~r/&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);/u
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

  def stable_id(source_id, raw_id) do
    :crypto.hash(:sha256, source_id <> <<0>> <> raw_id)
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
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
      parse_http_date(value)
  end

  def item_time(item) do
    item.published_at || item.collected_at || DateTime.from_unix!(0)
  end

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

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, {hour, minute, second}} ->
        DateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, second), "Etc/UTC")

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

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
end
