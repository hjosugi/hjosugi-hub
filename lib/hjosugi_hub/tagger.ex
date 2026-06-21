defmodule HjosugiHub.Tagger do
  @moduledoc false

  alias HjosugiHub.Util

  @rules [
    {"google-cloud", ["google cloud", "gcp", "bigquery", "cloud run", "spanner", "vertex ai"]},
    {"aws", ["amazon web services", "aws", "lambda", "dynamodb", "s3", "eks", "bedrock"]},
    {"azure", ["microsoft azure", "azure", "cosmos db", "aks"]},
    {"cloud",
     ["cloud infrastructure", "cloud computing", "serverless", "kubernetes", "container"]},
    {"distributed-systems",
     [
       "distributed system",
       "consensus",
       "replication",
       "partition",
       "raft",
       "paxos",
       "fault tolerance",
       "eventual consistency"
     ]},
    {"database",
     [
       "database",
       "postgresql",
       "mysql",
       "sqlite",
       "spanner",
       "dynamodb",
       "snowflake",
       "databricks",
       "vector database",
       "query engine"
     ]},
    {"data-engineering",
     [
       "data pipeline",
       "data engineering",
       "stream processing",
       "batch processing",
       "apache kafka",
       "apache flink",
       "spark",
       "warehouse",
       "lakehouse"
     ]},
    {"ai-ml",
     [
       "machine learning",
       "artificial intelligence",
       "llm",
       "large language model",
       "embedding",
       "inference",
       "transformer",
       "rag",
       "agent"
     ]},
    {"security",
     [
       "security",
       "vulnerability",
       "cve",
       "zero trust",
       "authentication",
       "authorization",
       "encryption"
     ]},
    {"observability", ["observability", "opentelemetry", "tracing", "metrics", "logging", "sre"]},
    {"developer-tools",
     [
       "developer tools",
       "build system",
       "compiler",
       "runtime",
       "sdk",
       "api design",
       "devex",
       "developer experience"
     ]},
    {"frontend",
     ["frontend", "browser", "javascript", "typescript", "react", "vue", "svelte", "css"]},
    {"career",
     ["engineering career", "interview", "staff engineer", "leadership", "engineering management"]},
    {"日本語", ["日本語", "国内", "開発者向け"]}
  ]

  def apply(title, content, seed_tags) do
    text = String.downcase("#{title}\n#{content}")

    detected =
      @rules
      |> Enum.filter(fn {_tag, keywords} ->
        Enum.any?(keywords, &String.contains?(text, String.downcase(&1)))
      end)
      |> Enum.map(fn {tag, _keywords} -> tag end)

    [seed_tags, detected]
    |> Util.merge_tags()
    |> Enum.take(10)
  end
end
