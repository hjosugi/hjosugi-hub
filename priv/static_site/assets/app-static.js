(() => {
  const body = document.body;
  const toggle = document.getElementById("crt-toggle");
  const stored = localStorage.getItem("hjosugi-hub-crt");
  if (stored === "off") {
    body.classList.add("crt-off");
    if (toggle) {
      toggle.textContent = "crt:off";
      toggle.setAttribute("aria-pressed", "false");
    }
  }

  toggle?.addEventListener("click", () => {
    const off = body.classList.toggle("crt-off");
    localStorage.setItem("hjosugi-hub-crt", off ? "off" : "on");
    toggle.textContent = off ? "crt:off" : "crt:on";
    toggle.setAttribute("aria-pressed", String(!off));
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
