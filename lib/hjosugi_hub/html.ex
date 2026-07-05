defmodule HjosugiHub.HTML do
  @moduledoc """
  Minimal escaping helper for generated HTML and XML fragments.

  It escapes dynamic text for attributes and text nodes assembled outside the
  static EEx templates.
  """

  def escape(nil), do: ""

  def escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
