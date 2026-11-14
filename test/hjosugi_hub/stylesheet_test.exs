defmodule HjosugiHub.StylesheetTest do
  use ExUnit.Case, async: true

  @stylesheet Path.expand("../../priv/static_site/assets/app.css", __DIR__)

  # Raw sizes drift apart quickly (the stylesheet once had 20+ distinct font
  # sizes, as many spacing values, and six radii), so they must all go through
  # the tokens defined on :root.
  test "font sizes use the --text-* scale" do
    assert stray_values("font-size", ~r/\A(var\(--text-(sm|md|lg|xl|2xl)\)|inherit)\z/) == []
  end

  test "corner radii use the --radius tokens" do
    assert stray_values("border-radius", ~r/\A(var\(--radius(-sm|-pill)?\)|50%)\z/) == []
  end

  test "padding, margin, and gap use the --space-* scale" do
    step = ~r/\A(0|auto|var\(--space-[a-z0-9]+\))\z/

    stray =
      for property <- ["padding(?:-[a-z]+)?", "margin(?:-[a-z]+)?", "(?:row-|column-)?gap"],
          value <- stray_values(property, ~r/\A\z/),
          not Enum.all?(String.split(value), &Regex.match?(step, &1)),
          do: value

    assert stray == []
  end

  defp stray_values(property, allowed) do
    ~r/(?<![\w-])#{property}:\s*([^;}]+)/
    |> Regex.scan(File.read!(@stylesheet), capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&Regex.match?(allowed, &1))
  end
end
