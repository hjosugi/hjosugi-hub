defmodule HjosugiHub.JSON do
  @moduledoc """
  JSON encoder wrapper for deterministic public data output.

  Map values with `nil` are omitted, object keys are sorted, structs are encoded
  through maps, and scalar values are delegated to `Elixir.JSON`.
  """

  def encode!(value), do: JSON.encode!(value, &encode_value/2)

  defp encode_value(%DateTime{} = value, encoder), do: JSON.protocol_encode(value, encoder)

  defp encode_value(%_{} = value, encoder),
    do: value |> Map.from_struct() |> encode_value(encoder)

  defp encode_value(value, encoder) when is_map(value) do
    entries =
      value
      |> Map.to_list()
      |> Enum.reject(fn {_key, val} -> is_nil(val) end)
      |> Enum.sort_by(fn {key, _val} -> to_string(key) end)
      |> Enum.map(fn {key, val} ->
        [encoder.(to_string(key), encoder), ?:, encoder.(val, encoder)]
      end)

    ["{", Enum.intersperse(entries, ","), "}"]
  end

  defp encode_value(value, encoder), do: JSON.protocol_encode(value, encoder)
end
