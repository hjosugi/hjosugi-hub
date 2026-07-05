defmodule HjosugiHub.CLITest do
  use ExUnit.Case, async: false

  alias HjosugiHub.CLI

  describe "parse_options!/2" do
    test "returns parsed strict options" do
      assert CLI.parse_options!(["--cache", "items.term", "--workers", "3"],
               cache: :string,
               workers: :integer
             ) == [cache: "items.term", workers: 3]
    end

    test "raises on invalid options" do
      assert_raise Mix.Error, ~r/invalid options:/, fn ->
        CLI.parse_options!(["--unknown"], cache: :string)
      end
    end
  end

  describe "cache_path/2" do
    setup do
      shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      on_exit(fn ->
        Mix.shell(shell)
      end)
    end

    test "returns the default when no cache option is present" do
      assert CLI.cache_path([], "default.term") == "default.term"
      refute_received {:mix_shell, :error, [_message]}
    end

    test "returns --cache without warning" do
      assert CLI.cache_path([cache: "cache.term"], "default.term") == "cache.term"
      refute_received {:mix_shell, :error, [_message]}
    end

    test "keeps --data as a deprecated alias" do
      assert CLI.cache_path([data: "data.term"], "default.term") == "data.term"

      assert_received {:mix_shell, :error, ["warning: --data is deprecated; use --cache instead"]}
    end

    test "prefers --cache over --data and still warns" do
      assert CLI.cache_path([cache: "cache.term", data: "data.term"], "default.term") ==
               "cache.term"

      assert_received {:mix_shell, :error, ["warning: --data is deprecated; use --cache instead"]}
    end
  end

  describe "env_int/2" do
    setup do
      name = "HJOSUGI_HUB_CLI_TEST_INT"
      previous = System.get_env(name)

      on_exit(fn ->
        if is_nil(previous) do
          System.delete_env(name)
        else
          System.put_env(name, previous)
        end
      end)

      System.delete_env(name)
      {:ok, env_name: name}
    end

    test "returns the default when the env var is unset", %{env_name: name} do
      assert CLI.env_int(name, 17) == 17
    end

    test "parses integer env vars", %{env_name: name} do
      System.put_env(name, "42")

      assert CLI.env_int(name, 17) == 42
    end

    test "returns the default for non-integer env vars", %{env_name: name} do
      System.put_env(name, "42ms")

      assert CLI.env_int(name, 17) == 17
    end
  end
end
