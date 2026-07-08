(() => {
  const THEME_KEY = "hjosugi-hub-theme";
  const CRT_KEY = "hjosugi-hub-crt";
  const root = document.documentElement;
  const body = document.body;
  const themeToggle = document.getElementById("theme-toggle");
  const crtToggle = document.getElementById("crt-toggle");

  function getStored(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function setStored(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch {
      // Theme switching should still work even when storage is unavailable.
    }
  }

  function applyTheme(value) {
    const theme = value === "light" ? "light" : "dark";
    root.dataset.theme = theme;

    if (themeToggle) {
      themeToggle.textContent = theme === "light" ? "☀" : "☾";
      themeToggle.setAttribute("aria-pressed", String(theme === "light"));
      themeToggle.setAttribute("aria-label", `Switch to ${theme === "light" ? "dark" : "light"} theme`);
      themeToggle.setAttribute("title", `theme:${theme}`);
    }
  }

  function applyCrt(value) {
    const off = value === "off";
    body.classList.toggle("crt-off", off);

    if (crtToggle) {
      crtToggle.textContent = off ? "crt:off" : "crt:on";
      crtToggle.setAttribute("aria-pressed", String(!off));
    }
  }

  applyTheme(getStored(THEME_KEY));
  applyCrt(getStored(CRT_KEY));

  themeToggle?.addEventListener("click", () => {
    const next = root.dataset.theme === "light" ? "dark" : "light";
    applyTheme(next);
    setStored(THEME_KEY, next);
  });

  crtToggle?.addEventListener("click", () => {
    const next = body.classList.contains("crt-off") ? "on" : "off";
    applyCrt(next);
    setStored(CRT_KEY, next);
  });

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    const typing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement;
    if (event.key === "/" && !typing) {
      const search = document.getElementById("radar-search");
      if (search) {
        event.preventDefault();
        search.focus();
      }
    }
  });

  // Fade sections in as they scroll into view (skipped for reduced motion).
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (!reduceMotion && "IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries, obs) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("in-view");
          obs.unobserve(entry.target);
        }
      },
      // Reveal a bit before the section scrolls into view so content appears
      // with less scrolling instead of popping in late.
      { threshold: 0, rootMargin: "0px 0px 20% 0px" }
    );
    for (const section of document.querySelectorAll(".section")) {
      section.classList.add("reveal");
      observer.observe(section);
    }
  }
})();
