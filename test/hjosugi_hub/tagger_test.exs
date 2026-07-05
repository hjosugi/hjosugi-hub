defmodule HjosugiHub.TaggerTest do
  use ExUnit.Case, async: true

  alias HjosugiHub.Tagger

  test "adds deterministic tags from title and content" do
    tags = Tagger.apply("Vector database platform", "RAG embeddings with PostgreSQL", ["seed"])
    assert "ai-ml" in tags
    assert "database" in tags
    assert "seed" in tags
  end

  test "does not match ascii keywords inside larger words" do
    tags = Tagger.apply("Storage layer", "Pragmatic notes about durable storage", [])

    refute "ai-ml" in tags
  end

  test "matches ascii multi-word phrases with flexible whitespace" do
    tags = Tagger.apply("Model serving", "A large   language\nmodel inference pipeline", [])

    assert "ai-ml" in tags
  end

  test "matches Japanese keywords without word separators" do
    tags = Tagger.apply("新しい日本語記事", "国内の開発者向け情報", [])

    assert "日本語" in tags
  end
end
