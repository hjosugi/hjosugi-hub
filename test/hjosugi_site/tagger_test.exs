defmodule HjosugiSite.TaggerTest do
  use ExUnit.Case, async: true

  alias HjosugiSite.Tagger

  test "adds deterministic tags from title and content" do
    tags = Tagger.apply("Vector database platform", "RAG embeddings with PostgreSQL", ["seed"])
    assert "ai-ml" in tags
    assert "database" in tags
    assert "seed" in tags
  end
end
