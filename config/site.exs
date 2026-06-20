%{
  handle: "hjosugi",
  display_name: "hjosugi",
  headline: "Backend, data, and distributed systems engineer",
  location: "Tokyo, Japan",
  availability: "Open to software engineering opportunities in Japan",
  about:
    "I build practical software around data, search, developer tools, and reliable backend systems. I care about explicit tradeoffs, recoverable architecture, and small vertical slices that can be tested and shipped.",
  email: "",
  links: [
    %{label: "GitHub", url: "https://github.com/hjosugi"}
  ],
  projects: [
    %{
      name: "Daimon",
      url: "https://github.com/hjosugi/daimon",
      demo_url: "https://daimon-sandy.vercel.app/",
      summary:
        "A social discovery prototype that combines multilingual embeddings, POV tags, vector retrieval, and a Sense-Distance ranking strategy to surface both nearby and bridge posts.",
      stack: ["React", "PostgreSQL", "Qdrant", "Python", "Redis"],
      highlights: [
        "Separates PostgreSQL as the system of record from Qdrant as a rebuildable search index.",
        "Keeps ML inference in a focused Python service while the API, schema, and seed paths stay in a typed backend service.",
        "Uses bridge scoring and MMR to avoid a timeline made only of near-duplicates."
      ],
      featured: true
    },
    %{
      name: "Mail Lookout",
      url: "https://github.com/hjosugi/mail-lookout",
      demo_url: "https://mail-lookout.netlify.app/",
      summary:
        "An Outlook Smart Alerts add-in that reviews recipients, attachments, subject, and body before a message is sent.",
      stack: ["TypeScript", "Office.js", "Bun", "Vite", "Vitest"],
      highlights: [
        "Keeps the core review rules independent from Office, the DOM, and wall-clock time.",
        "Ships bilingual UI, automated validation, tests, and tagged release manifests.",
        "Handles scheduled-send limitations explicitly instead of hiding unsafe behavior."
      ],
      featured: true
    },
    %{
      name: "open-wiki",
      url: "https://github.com/hjosugi/open-wiki",
      summary:
        "A small, complete wiki vertical slice with a pure functional core, typed HTTP boundaries, and transactional render, revision, and search updates.",
      stack: ["Bun", "Elysia", "Vue 3", "Drizzle", "SQLite FTS5"],
      highlights: [
        "Uses explicit dependency injection and Result values rather than a global mutable singleton.",
        "Commits render output, revision history, and FTS updates atomically.",
        "Provides weighted BM25 search and end-to-end types without code generation."
      ],
      featured: true
    },
    %{
      name: "YouTube Tools",
      url: "https://github.com/hjosugi/youtube-tools",
      summary:
        "A maintained collection of subtitle, batch fetch, CLI, and downloader utilities for YouTube workflows.",
      stack: ["Python", "FastAPI", "uv", "yt-dlp", "ffmpeg"],
      highlights: [],
      featured: false
    }
  ],
  skills: [
    %{
      name: "Backend and systems",
      items: ["Elixir", "Java", "Python", "TypeScript", "REST APIs", "concurrency", "system design"]
    },
    %{
      name: "Data and search",
      items: ["PostgreSQL", "SQLite", "Qdrant", "FTS5", "BM25", "embeddings", "retrieval"]
    },
    %{
      name: "Cloud and operations",
      items: ["containers", "CI/CD", "observability", "AWS", "Azure", "Google Cloud"]
    }
  ],
  interests: ["distributed systems", "developer tools", "search", "data platforms", "local-first AI"]
}
