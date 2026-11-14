defmodule HjosugiHub.StylesheetTest do
  use ExUnit.Case, async: true

  @stylesheet Path.expand("../../priv/static_site/assets/app.css", __DIR__)

  # Raw sizes drift apart quickly (the stylesheet once had 20+ distinct font
  # sizes and six radii), so both must go through the tokens defined on :root.
  test "font sizes use the --text-* scale" do
    assert stray_values("font-size", ~r/\A(var\(--text-(sm|md|lg|xl|2xl)\)|inherit)\z/) == []
  end

  test "corner radii use the --radius tokens" do
    assert stray_values("border-radius", ~r/\A(var\(--radius(-sm|-pill)?\)|50%)\z/) == []
  end

  defp stray_values(property, allowed) do
    ~r/(?<![\w-])#{property}:\s*([^;}]+)/
    |> Regex.scan(File.read!(@stylesheet), capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&Regex.match?(allowed, &1))
  end
end
