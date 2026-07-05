defmodule HjosugiHub.Dochicken do
  @moduledoc """
  Pixel-art asset generator for the Dochicken gallery mascot.

  The layered 16x16 sprite definition lives in Elixir and is exposed as SVG for
  named gallery poses.
  """

  # ドチキンさん: a chicken-shaped 埴輪 (haniwa, terracotta figure). Like Kofun,
  # the artwork is a 16x16 pixel grid defined once here; CSS scales and animates
  # it. Unlike Kofun it has several colour layers (terracotta body, red comb and
  # wattle, yellow beak, orange legs).

  @comb [{6, 0, 1, 1}, {8, 0, 1, 1}, {10, 0, 1, 1}, {6, 1, 5, 1}]

  # Rounded haniwa head over a widening cylindrical body, as {x, y, w, h} rows.
  @body [
    {6, 2, 4, 1},
    {5, 3, 6, 1},
    {5, 4, 6, 1},
    {5, 5, 6, 1},
    {4, 6, 8, 1},
    {3, 7, 10, 1},
    {3, 8, 10, 1},
    {3, 9, 10, 1},
    {3, 10, 10, 1},
    {3, 11, 10, 1},
    {4, 12, 8, 1},
    {4, 13, 8, 1}
  ]

  @wing [{4, 9, 3, 1}, {4, 10, 2, 1}]
  @wattle [{7, 7, 2, 1}]
  @legs [{6, 14, 1, 1}, {9, 14, 1, 1}, {5, 15, 2, 1}, {9, 15, 2, 1}]

  # Pose deltas ("ドットの差分"): blink closes the eyes, peck lowers the beak.
  @eyes %{
    idle: [{6, 3, 1, 2}, {9, 3, 1, 2}],
    blink: [{6, 4, 1, 1}, {9, 4, 1, 1}],
    peck: [{6, 3, 1, 2}, {9, 3, 1, 2}]
  }
  @beak %{
    idle: [{7, 5, 2, 2}],
    blink: [{7, 5, 2, 2}],
    peck: [{7, 6, 2, 2}]
  }

  # Neon palette: a warm orange body (roughly the complement of the site's green
  # accent) with a hot coral comb/wattle, so the haniwa glows against the dark
  # teal background.
  @body_fill "#ff9d42"
  @body_shade "#ef6f1f"
  @comb_fill "#ff5470"
  @beak_fill "#ffd24a"
  @leg_fill "#ff8a1f"
  @eye_fill "#2a1008"

  @doc "Pose names available for the gallery."
  def poses, do: [:idle, :blink, :peck]

  @doc "A single gallery pose sprite (16x16, scaled up by CSS)."
  def pose_svg(pose) do
    eyes = Map.get(@eyes, pose, @eyes.idle)
    beak = Map.get(@beak, pose, @beak.idle)

    svg(
      group(@comb_fill, rects(@comb)) <>
        group(@body_fill, rects(@body)) <>
        group(@body_shade, rects(@wing)) <>
        group(@leg_fill, rects(@legs)) <>
        group(@beak_fill, rects(beak)) <>
        group(@comb_fill, rects(@wattle)) <>
        group(@eye_fill, rects(eyes))
    )
  end

  defp svg(inner) do
    ~s(<svg viewBox="0 0 16 16" class="px-svg dochicken-svg" shape-rendering="crispEdges" ) <>
      ~s(aria-hidden="true" focusable="false">#{inner}</svg>)
  end

  defp group(fill, rects), do: ~s(<g fill="#{fill}">#{rects}</g>)
  defp rects(list), do: Enum.map_join(list, fn {x, y, w, h} -> rect(x, y, w, h) end)
  defp rect(x, y, w, h), do: ~s(<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}"/>)
end
