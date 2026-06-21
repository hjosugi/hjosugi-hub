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
