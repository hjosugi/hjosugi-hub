defmodule HjosugiHub.Item do
  @moduledoc false

  defstruct [
    :id,
    :source_id,
    :source_name,
    :source_kind,
    :title,
    :url,
    :author,
    :summary,
    :content,
    :published_at,
    :collected_at,
    :score,
    tags: []
  ]
end
