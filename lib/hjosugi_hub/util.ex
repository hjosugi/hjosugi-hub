defmodule HjosugiHub.Util do
  @moduledoc false

  @tag_trim ~r/[-\/#]+$/u

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

  defp html_decode(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
  end
end
