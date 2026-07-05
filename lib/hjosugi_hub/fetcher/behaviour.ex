defmodule HjosugiHub.Fetcher.Behaviour do
  @moduledoc false

  @callback fetch(map(), non_neg_integer()) ::
              {:ok, [HjosugiHub.Item.t()], non_neg_integer()}
              | {:error, String.t(), non_neg_integer()}
end
