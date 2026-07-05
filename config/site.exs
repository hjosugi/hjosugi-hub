%{
  handle: "hjosugi",
  display_name: "hjosugi",
  headline: "A software engineer in Japan",
  location: "Tokyo, Japan",
  availability: "Just tinkering — a small corner of the internet",
  about:
    "I mess around with little tools, prototypes, and half-finished ideas in my spare time. Backend, a bit of frontend, whatever I feel like that week. Nothing too serious — I just like building things and seeing if they work.",
  email: "",
  links: [
    %{label: "GitHub", url: "https://github.com/hjosugi"}
  ],
  projects: [
    %{
      name: "Irodori Table",
      url: "https://github.com/hjosugi/irodori-table",
      docs_url: "https://hjosugi.github.io/irodori-docs/",
      summary:
        "A Tauri desktop database client I am building around Rust, React, and TypeScript. The main repo keeps the app, shared crates, extension SDK work, sample database tooling, and release automation together.",
      stack: ["Rust", "Tauri", "React", "TypeScript", "Vite", "SQL"],
      highlights: [
        "Desktop UX stays in one repo: query editor, result grid, BI panels, ERD layout, and connection flows.",
        "Generated Rust-to-TypeScript bindings keep the Tauri boundary checked instead of hand-waved.",
        "The docs site is a separate mdBook so architecture, privacy, support, and database coverage notes are easy to browse."
      ],
      featured: true
    },
    %{
      name: "Daimon",
      url: "https://github.com/hjosugi/daimon",
      demo_url: "https://daimon-sandy.vercel.app/",
      summary:
        "A little social-discovery prototype I built to play with multilingual embeddings and vector search. It tries to surface both nearby posts and 'bridge' posts, so the feed is not just a wall of near-duplicates.",
      stack: ["React", "PostgreSQL", "Qdrant", "Python", "Redis"],
      highlights: [
        "Postgres holds the real data; Qdrant is a rebuildable search index.",
        "ML inference lives in a small Python service, away from the API and schema.",
        "Bridge scoring + MMR keeps the timeline a bit more varied."
      ],
      featured: true
    },
    %{
      name: "Mail Lookout",
      url: "https://github.com/hjosugi/mail-lookout",
      demo_url: "https://mail-lookout.netlify.app/",
      summary:
        "A small Outlook add-in that double-checks recipients, attachments, and the subject and body before you hit send — so you do not fire off the wrong email to the wrong person.",
      stack: ["TypeScript", "Office.js", "Bun", "Vite", "Vitest"],
      highlights: [
        "Core review rules stay independent from Office, the DOM, and the clock.",
        "Bilingual UI, tests, and tagged releases.",
        "Handles scheduled-send quirks out loud instead of hiding them."
      ],
      featured: true
    },
    %{
      name: "Smart YouTube Comment",
      url: "https://github.com/hjosugi/smart-youtube-comment",
      summary:
        "A Chrome extension prototype that overlays YouTube live chat niconico-style (danmaku). It scores each comment locally in JavaScript, so useful messages drift by slowly while emoji floods and spam zip past.",
      stack: ["JavaScript", "Chrome MV3", "Canvas", "danmaku"],
      highlights: [
        "Local scoring only — no remote code, no WASM.",
        "Extracts chat from every frame and renders over the player on a canvas.",
        "Just a fun experiment in keeping the good comments readable."
      ],
      featured: true
    },
    %{
      name: "Ayame Editor",
      url: "https://github.com/hjosugi/ayame-editor",
      docs_url: "https://hjosugi.github.io/ayame-editor/",
      summary:
        "A fast desktop text editor for very large files. It pairs a Rust core with a local web UI and optional native window so huge text files can open, search, and edit without pretending they are small.",
      stack: ["Rust", "Axum", "TypeScript", "Wry", "WebView", "CLI"],
      highlights: [
        "Memory-mapped and sparsely indexed internals keep large-file scans practical.",
        "Runs as a CLI/local web editor, with a native desktop window available for app-style use.",
        "Release builds target macOS, Windows, and Linux, with docs and install scripts alongside the source."
      ],
      featured: true
    },
    %{
      name: "sql-dialect-fmt",
      url: "https://github.com/hjosugi/sql-dialect-fmt",
      summary:
        "An opinionated formatter and syntax toolchain for Snowflake SQL and Databricks SQL. It is built in Rust and aims for gofmt-style low-config formatting without changing meaningful SQL tokens or comments.",
      stack: ["Rust", "SQL", "rowan", "Tree-sitter", "WASM", "LSP"],
      highlights: [
        "The formatter is designed to be idempotent and lossless for meaningful tokens and comments.",
        "Ships as a CLI, language-server pieces, Tree-sitter grammar, and editor/browser extension packages.",
        "Includes a Snowsight Chrome extension path powered by the formatter compiled to WebAssembly."
      ],
      featured: false
    },
    %{
      name: "Form Panic Bureau",
      url: "https://github.com/hjosugi/form-panic-bureau",
      demo_url: "https://hjosugi.github.io/form-panic-bureau/",
      summary:
        "A single-screen browser game written entirely in Elm: fix every defect in a deliberately user-hostile form and catch the fleeing \"Accept\" button within 60 seconds — a playable parody of dark-pattern forms.",
      stack: ["Elm", "Nix", "HTML", "CSS"],
      highlights: [],
      featured: false
    }
  ],
  skills: [
    %{
      name: "Backend and systems",
      items: [
        "Java",
        "Python",
        "TypeScript",
        "REST APIs",
        "Elixir",
        "concurrency",
        "system design"
      ]
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
  interests: [
    "distributed systems",
    "developer tools",
    "search",
    "data platforms",
    "local-first AI"
  ]
}
