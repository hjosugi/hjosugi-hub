defmodule HjosugiHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :hjosugi_hub,
      version: "0.3.3",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :inets, :logger, :ssl, :xmerl]
    ]
  end
end
