defmodule HjosugiHub.CLI do
  @moduledoc false

  @data_deprecation "warning: --data is deprecated; use --cache instead"

  def parse_options!(args, strict) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: strict)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts
  end

  def cache_path(opts, default) do
    if Keyword.has_key?(opts, :data) do
      Mix.shell().error(@data_deprecation)
    end

    Keyword.get(opts, :cache, Keyword.get(opts, :data, default))
  end

  def env_int(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _ -> default
        end
    end
  end
end
