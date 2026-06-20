(() => {
  const body = document.body;
  const toggle = document.getElementById("crt-toggle");
  const stored = localStorage.getItem("signal-garden-crt");
  if (stored === "off") {
    body.classList.add("crt-off");
    if (toggle) {
      toggle.textContent = "crt:off";
      toggle.setAttribute("aria-pressed", "false");
    }
  }

  toggle?.addEventListener("click", () => {
    const off = body.classList.toggle("crt-off");
    localStorage.setItem("signal-garden-crt", off ? "off" : "on");
    toggle.textContent = off ? "crt:off" : "crt:on";
    toggle.setAttribute("aria-pressed", String(!off));
  });

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    const typing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement;
    if (event.key === "/" && !typing) {
      const search = document.getElementById("signal-search");
      if (search) {
        event.preventDefault();
        search.focus();
      }
    }
  });
})();
