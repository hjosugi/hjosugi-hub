# Each feed: id, name, url, kind, enabled, tags.
# Optional :weight (float) biases radar ranking; without it a feed inherits a
# default for its :kind (aggregator 1.3, newsletter 1.2, engineering 1.15,
# official/youtube 1.0). Raise a source you trust, e.g. weight: 1.4.
[
  %{
    id: "google-cloud",
    name: "Google Cloud Blog",
    url: "https://cloudblog.withgoogle.com/rss/",
    kind: "official",
    enabled: true,
    tags: ["google-cloud", "cloud", "official"]
  },
  %{
    id: "google-research",
    name: "Google Research",
    url: "https://research.google/blog/rss/",
    kind: "official",
    enabled: true,
    tags: ["google", "research", "ai-ml", "official"]
  },
  %{
    id: "google-developers",
    name: "Google Developers Blog",
    url: "https://developers.googleblog.com/feeds/posts/default",
    kind: "official",
    enabled: true,
    tags: ["google", "developer-tools", "official"]
  },
  %{
    id: "aws-news",
    name: "AWS News Blog",
    url: "https://aws.amazon.com/blogs/aws/feed/",
    kind: "official",
    enabled: true,
    tags: ["aws", "cloud", "official"]
  },
  %{
    id: "aws-architecture",
    name: "AWS Architecture Blog",
    url: "https://aws.amazon.com/blogs/architecture/feed/",
    kind: "official",
    enabled: true,
    tags: ["aws", "architecture", "distributed-systems", "official"]
  },
  %{
    id: "aws-big-data",
    name: "AWS Big Data Blog",
    url: "https://aws.amazon.com/blogs/big-data/feed/",
    kind: "official",
    enabled: true,
    tags: ["aws", "data-engineering", "official"]
  },
  %{
    id: "cloudflare",
    name: "Cloudflare Blog",
    url: "https://blog.cloudflare.com/rss/",
    kind: "engineering",
    enabled: true,
    tags: ["cloudflare", "distributed-systems", "security"]
  },
  %{
    id: "meta-engineering",
    name: "Meta Engineering",
    url: "https://engineering.fb.com/feed/",
    kind: "engineering",
    enabled: true,
    tags: ["meta", "engineering"]
  },
  %{
    id: "netflix-tech",
    name: "Netflix TechBlog",
    url: "https://netflixtechblog.com/feed",
    kind: "engineering",
    enabled: true,
    tags: ["netflix", "distributed-systems"]
  },
  %{
    id: "uber-engineering",
    name: "Uber Engineering",
    url: "https://www.uber.com/blog/engineering/rss/",
    kind: "engineering",
    enabled: true,
    tags: ["uber", "engineering"]
  },
  %{
    id: "github-engineering",
    name: "GitHub Engineering",
    url: "https://github.blog/engineering/feed/",
    kind: "engineering",
    enabled: true,
    tags: ["github", "developer-tools"]
  },
  %{
    id: "stripe",
    name: "Stripe Blog",
    url: "https://stripe.com/blog/feed.rss",
    kind: "engineering",
    enabled: true,
    tags: ["stripe", "payments", "engineering"]
  },
  %{
    id: "nvidia-developer",
    name: "NVIDIA Technical Blog",
    url: "https://developer.nvidia.com/blog/feed/",
    kind: "official",
    enabled: true,
    tags: ["nvidia", "ai-ml", "official"]
  },
  %{
    id: "databricks",
    name: "Databricks Blog",
    url: "https://www.databricks.com/blog/feed",
    kind: "official",
    enabled: true,
    tags: ["databricks", "data-engineering", "official"]
  },
  %{
    id: "snowflake",
    name: "Snowflake Blog",
    url: "https://www.snowflake.com/en/blog/feed/",
    kind: "official",
    enabled: true,
    tags: ["snowflake", "data-engineering", "official"]
  },
  %{
    id: "pragmatic-engineer",
    name: "The Pragmatic Engineer",
    url: "https://newsletter.pragmaticengineer.com/feed",
    kind: "newsletter",
    enabled: true,
    tags: ["career", "engineering"]
  },
  %{
    id: "hacker-news",
    name: "Hacker News Front Page",
    url: "https://hnrss.org/frontpage",
    kind: "aggregator",
    enabled: true,
    tags: ["hacker-news", "aggregator"]
  },
  %{
    id: "lobsters",
    name: "Lobsters",
    url: "https://lobste.rs/rss",
    kind: "aggregator",
    enabled: true,
    tags: ["lobsters", "aggregator"]
  },
  %{
    id: "cloudflare",
    name: "The Cloudflare Blog",
    url: "https://blog.cloudflare.com/rss/",
    kind: "engineering",
    enabled: true,
    tags: ["cloudflare", "networking", "engineering"]
  },
  %{
    id: "netflix-tech",
    name: "Netflix Tech Blog",
    url: "https://netflixtechblog.com/feed",
    kind: "engineering",
    enabled: true,
    tags: ["netflix", "engineering", "distributed-systems"]
  },
  %{
    id: "meta-engineering",
    name: "Engineering at Meta",
    url: "https://engineering.fb.com/feed/",
    kind: "engineering",
    enabled: true,
    tags: ["meta", "engineering"]
  },
  %{
    id: "julia-evans",
    name: "Julia Evans",
    url: "https://jvns.ca/atom.xml",
    kind: "engineering",
    enabled: true,
    weight: 1.25,
    tags: ["engineering", "systems"]
  },
  %{
    id: "simon-willison",
    name: "Simon Willison",
    url: "https://simonwillison.net/atom/everything/",
    kind: "engineering",
    enabled: true,
    weight: 1.25,
    tags: ["engineering", "ai-ml", "developer-tools"]
  },
  %{
    id: "lwn",
    name: "LWN.net",
    url: "https://lwn.net/headlines/rss",
    kind: "engineering",
    enabled: true,
    tags: ["linux", "kernel", "engineering"]
  },
  %{
    id: "go-blog",
    name: "The Go Blog",
    url: "https://go.dev/blog/feed.atom",
    kind: "engineering",
    enabled: true,
    tags: ["golang", "engineering"]
  },
  %{
    id: "rust-blog",
    name: "Rust Blog",
    url: "https://blog.rust-lang.org/feed.xml",
    kind: "engineering",
    enabled: true,
    tags: ["rust", "engineering"]
  },
  %{
    id: "youtube-google-cloud",
    name: "Google Cloud Tech on YouTube",
    url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCJS9pqu9BzkAMNT5jguyJQ",
    kind: "youtube",
    enabled: false,
    tags: ["google-cloud", "youtube", "official"]
  }
]
