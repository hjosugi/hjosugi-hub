defmodule HjosugiHub.FetcherTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Fetcher

  test "http options configure TLS certificate verification for httpc" do
    options = Fetcher.http_options(1_000)

    assert options[:timeout] == 1_000
    assert options[:connect_timeout] == 1_000
    assert options[:autoredirect] == true

    assert ssl_options = options[:ssl]
    assert ssl_options[:verify] == :verify_peer
    assert ssl_options[:cacerts] == :public_key.cacerts_get()

    assert ssl_options[:customize_hostname_check][:match_fun] ==
             :public_key.pkix_verify_hostname_match_fun(:https)
  end
end
