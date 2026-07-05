defmodule HjosugiHub.Fetcher.Behaviour do
  @moduledoc false

  @callback fetch(map(), non_neg_integer()) ::
              {:ok, [HjosugiHub.Item.t()], non_neg_integer()}
              | {:error, String.t(), non_neg_integer()}

  @callback fetch(map(), non_neg_integer(), map()) ::
              {:ok, [HjosugiHub.Item.t()], non_neg_integer(), map()}
              | {:not_modified, non_neg_integer(), map()}
              | {:error, String.t(), non_neg_integer()}

  @optional_callbacks fetch: 3
end
