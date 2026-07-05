defmodule HjosugiHub.Item do
  @moduledoc """
  Struct for normalized collected feed entries.

  Items carry source metadata, cleaned text, timestamps, score hints, and tags
  before `HjosugiHub.Store` projects them into public JSON-friendly maps.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          source_id: String.t() | nil,
          source_name: String.t() | nil,
          source_kind: String.t() | nil,
          title: String.t() | nil,
          url: String.t() | nil,
          author: String.t() | nil,
          summary: String.t() | nil,
          content: String.t() | nil,
          published_at: DateTime.t() | nil,
          collected_at: DateTime.t() | nil,
          score: non_neg_integer() | nil,
          tags: [String.t()]
        }

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
