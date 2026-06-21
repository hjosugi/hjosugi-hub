defmodule HjosugiHub.JSON do
  @moduledoc false

  def encode!(value), do: value |> encode_value() |> IO.iodata_to_binary()

  defp encode_value(%DateTime{} = value), do: encode_string(DateTime.to_iso8601(value))
  defp encode_value(%_{} = value), do: value |> Map.from_struct() |> encode_value()
  defp encode_value(nil), do: "null"
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)

  defp encode_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, decimals: 12])

  defp encode_value(value) when is_binary(value), do: encode_string(value)

  defp encode_value(value) when is_list(value) do
    ["[", value |> Enum.map(&encode_value/1) |> Enum.intersperse(","), "]"]
  end

  defp encode_value(value) when is_map(value) do
    entries =
      value
      |> Map.to_list()
      |> Enum.reject(fn {_key, val} -> is_nil(val) end)
      |> Enum.sort_by(fn {key, _val} -> to_string(key) end)
      |> Enum.map(fn {key, val} -> [encode_string(to_string(key)), ":", encode_value(val)] end)

    ["{", Enum.intersperse(entries, ","), "}"]
  end

  defp encode_string(value) do
    escaped =
      for <<char::utf8 <- value>>, into: "" do
        case char do
          ?" ->
            "\\\""

          ?\\ ->
            "\\\\"

          ?\b ->
            "\\b"

          ?\f ->
            "\\f"

          ?\n ->
            "\\n"

          ?\r ->
            "\\r"

          ?\t ->
            "\\t"

          char when char < 0x20 ->
            "\\u" <> (char |> Integer.to_string(16) |> String.pad_leading(4, "0"))

          char ->
            <<char::utf8>>
        end
      end

    ["\"", escaped, "\""]
  end
end
