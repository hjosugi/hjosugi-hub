defmodule SignalGarden.MixProject do
  use Mix.Project

  def project do
    [
      app: :signal_garden,
      version: "0.2.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :inets, :logger, :ssl]
    ]
  end
end
