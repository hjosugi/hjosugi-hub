defmodule HjosugiHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :hjosugi_hub,
      version: "0.3.0",
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
