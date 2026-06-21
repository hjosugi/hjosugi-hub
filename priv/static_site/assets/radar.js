(() => {
  const app = document.querySelector("[data-radar-app]");
  if (!app) return;

  const form = document.getElementById("static-search-form");
  const input = document.getElementById("radar-search");
  const resultsNode = app.querySelector("[data-results]");
  const summaryNode = app.querySelector("[data-result-summary]");
  const clearNode = app.querySelector("[data-clear-filters]");
  const tagFacetsNode = app.querySelector("[data-tag-facets]");
  const sourceFacetsNode = app.querySelector("[data-source-facets]");
  const savedFacetsNode = app.querySelector("[data-saved-facets]");
  const totalCountNode = app.querySelector("[data-total-count]");
  let items = [];

  const collator = new Intl.Collator(undefined, { sensitivity: "base" });

  // The landing view shows only the last N days; search opens the full archive.
  const RECENT_DAYS = 30;

  // --- DOM helpers -------------------------------------------------------

  // el("a", {class, href, text, "aria-pressed"}, child|[children]) -> element.
  // Known DOM properties are assigned directly; everything else via attribute.
  function el(tag, props = {}, children = []) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
      if (key === "class") node.className = value;
      else if (key === "text") node.textContent = value;
      else if (key in node) node[key] = value;
      else node.setAttribute(key, value);
    }
    for (const child of [].concat(children)) {
      if (child != null) node.append(child);
    }
    return node;
  }

  function withParam(base, key, value) {
    const params = new URLSearchParams(base);
    if (value) params.set(key, value);
    else params.delete(key);
    return params;
  }

  function onNavigate(params) {
    return (event) => {
      event.preventDefault();
      navigate(params);
    };
  }

  // --- saved (localStorage) ---------------------------------------------

  const SAVED_KEY = "hjosugi-hub-saved";
  const saved = loadSaved();

  function loadSaved() {
    try {
      const list = JSON.parse(window.localStorage.getItem(SAVED_KEY) || "[]");
      return new Set(Array.isArray(list) ? list.map(String) : []);
    } catch (_) {
      return new Set();
    }
  }

  function persistSaved() {
    try {
      window.localStorage.setItem(SAVED_KEY, JSON.stringify([...saved]));
    } catch (_) {
      /* private mode or full storage: keep the in-memory set only */
    }
  }

  const itemKey = (item) => String(item.id || item.url || item.title || "");
  const isSaved = (item) => saved.has(itemKey(item));

  function toggleSaved(item) {
    const key = itemKey(item);
    saved.has(key) ? saved.delete(key) : saved.add(key);
    persistSaved();
    render(currentParams());
  }

  // --- data + routing ----------------------------------------------------

  fetch(app.dataset.itemsUrl)
    .then((response) => {
      if (!response.ok) throw new Error("items request failed");
      return response.json();
    })
    .then((data) => {
      items = Array.isArray(data) ? data : [];
      if (totalCountNode) totalCountNode.textContent = String(items.length);
      updateFromLocation();
    })
    .catch(() => {
      summaryNode.textContent = "Could not load the static radar index.";
      resultsNode.replaceChildren(emptyState("!", "The static data file is missing or unavailable."));
    });

  form?.addEventListener("submit", (event) => {
    event.preventDefault();
    navigate(withParam(currentParams(), "q", input.value.trim()));
  });

  window.addEventListener("popstate", updateFromLocation);

  function updateFromLocation() {
    const params = currentParams();
    input.value = params.get("q") || "";
    render(params);
  }

  function navigate(params) {
    const query = params.toString();
    history.pushState(null, "", query ? "?" + query : location.pathname);
    updateFromLocation();
  }

  const currentParams = () => new URLSearchParams(location.search);

  // --- render ------------------------------------------------------------

  function render(params) {
    const query = params.get("q") || "";
    const tag = params.get("tag") || "";
    const source = params.get("source") || "";
    const onlySaved = params.get("saved") === "1";
    // The unfiltered landing view shows only recent items; searching or filtering
    // opens up the whole archive.
    const defaultView = !query && !tag && !source && !onlySaved;
    const cutoff = Date.now() - RECENT_DAYS * 86400000;
    const ranked = rank(items, query)
      .filter((item) => !onlySaved || isSaved(item))
      .filter((item) => !tag || item.tags?.some((value) => same(value, tag)))
      .filter((item) => !source || same(item.source_name, source) || same(item.source_id, source))
      .filter((item) => !defaultView || dateValue(item) >= cutoff);
    const visible = ranked.slice(0, 80);

    summaryNode.textContent = defaultView
      ? "top " + visible.length + " from the last " + RECENT_DAYS + " days · " + items.length + " indexed — search to see all"
      : summaryText(visible.length, ranked.length, query, tag, source, onlySaved);
    clearNode.hidden = !(query || tag || source || onlySaved);
    clearNode.onclick = onNavigate(new URLSearchParams());

    renderSavedFacet(savedFacetsNode, items.filter(isSaved).length, onlySaved, params);
    renderFacets(tagFacetsNode, facets(items, "tags"), "tag", tag, params);
    renderFacets(sourceFacetsNode, facets(items, "source_name"), "source", source, params);

    if (visible.length === 0) {
      const message = defaultView
        ? "No items in the last " + RECENT_DAYS + " days — try a search."
        : onlySaved && saved.size === 0
          ? "Nothing saved yet. Tap the star on any item to keep it here."
          : "Try a broader query or clear the active filters.";
      resultsNode.replaceChildren(emptyState("!", message));
      return;
    }
    resultsNode.replaceChildren(...visible.map(renderCard));
  }

  function rank(values, query) {
    const terms = tokens(query);
    return [...values]
      .map((item) => ({ item, score: score(item, terms, query) }))
      .sort((a, b) => b.score - a.score || dateValue(b.item) - dateValue(a.item))
      .map((entry) => entry.item);
  }

  // Field weights for a matched term and for the whole-query phrase.
  const TERM_WEIGHTS = { title: 7, tags: 5, source: 3, body: 1 };
  const PHRASE_WEIGHTS = { title: 6, tags: 4, source: 3, body: 2 };

  // Default ordering when nothing is searched: recency biased by source weight,
  // plus a popularity nudge from crowd-vote scores (e.g. Hacker News points).
  function baseScore(item) {
    const recency = Math.max(0, dateValue(item) / 1e13);
    const weight = Number(item.weight) || 1;
    const popularity = item.score > 0 ? Math.min(1.5, Math.log10(item.score + 1) / 2) : 0;
    return recency * weight + popularity;
  }

  function score(item, terms, query) {
    const base = baseScore(item);
    const phrase = norm(query);
    if (terms.length === 0 && !phrase) return base;

    const fields = {
      title: norm(item.title),
      tags: norm((item.tags || []).join(" ")),
      source: norm(item.source_name),
      body: norm([item.summary, item.content, item.author].filter(Boolean).join(" ")),
    };

    let value = 0;
    for (const term of terms) {
      if (fields.title === term) value += 12;
      for (const [field, weight] of Object.entries(TERM_WEIGHTS)) {
        if (fields[field].includes(term)) value += weight;
      }
    }
    if (phrase) {
      for (const [field, weight] of Object.entries(PHRASE_WEIGHTS)) {
        if (fields[field].includes(phrase)) value += weight;
      }
    }
    return value + base;
  }

  // --- facets ------------------------------------------------------------

  function renderSavedFacet(node, count, active, baseParams) {
    if (!node) return;
    node.replaceChildren(
      facetLink("all", "", "saved", !active, baseParams, 0),
      facetLink("★ saved", "1", "saved", active, baseParams, count)
    );
  }

  function renderFacets(node, entries, key, activeValue, baseParams) {
    const links = entries
      .slice(0, 28)
      .map((entry) => facetLink(entry.name, entry.name, key, same(activeValue, entry.name), baseParams, entry.count));
    node.replaceChildren(facetLink("all", "", key, activeValue === "", baseParams, 0), ...links);
  }

  function facetLink(label, value, key, active, baseParams, count) {
    const params = withParam(baseParams, key, value);
    const link = el(
      "a",
      { class: "filter-link" + (active ? " active" : ""), href: "?" + params.toString() },
      el("span", { text: label })
    );
    link.addEventListener("click", onNavigate(params));
    if (count > 0) link.append(el("b", { text: String(count) }));
    return link;
  }

  function facets(values, field) {
    const counts = new Map();
    for (const item of values) {
      const entries = field === "tags" ? item.tags || [] : [item[field]].filter(Boolean);
      for (const entry of entries) counts.set(entry, (counts.get(entry) || 0) + 1);
    }
    return [...counts.entries()]
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count || collator.compare(a.name, b.name));
  }

  // --- cards -------------------------------------------------------------

  function renderCard(item) {
    const meta = el("div", { class: "radar-meta" }, [
      el("span", { text: item.source_name || "unknown source" }),
      el("span", { text: dateLabel(item) }),
      item.source_kind ? el("span", { text: item.source_kind }) : null,
      item.score > 0 ? el("span", { class: "radar-score", text: "▲ " + item.score }) : null,
      saveButton(item),
    ]);

    const title = el(
      "h2",
      {},
      el("a", {
        href: safeURL(item.url),
        target: "_blank",
        rel: "noopener noreferrer",
        text: item.title || "Untitled",
      })
    );

    const summary = el("p", { text: item.summary || "No summary provided by the source." });

    const footer = el("div", { class: "radar-footer" }, [
      el("div", { class: "chip-row" }, (item.tags || []).map(tagChip)),
      item.author ? el("span", { text: "by " + item.author }) : null,
    ]);

    return el("article", { class: "radar-card" }, [meta, title, summary, footer]);
  }

  function tagChip(tag) {
    const params = withParam(currentParams(), "tag", tag);
    const chip = el("a", { class: "chip link-chip", href: "?" + params.toString(), text: tag });
    chip.addEventListener("click", onNavigate(params));
    return chip;
  }

  function saveButton(item) {
    const active = isSaved(item);
    const button = el("button", {
      type: "button",
      class: "save-btn" + (active ? " saved" : ""),
      text: active ? "★ saved" : "☆ save",
      "aria-pressed": String(active),
      title: active ? "remove from saved" : "save to this browser",
    });
    button.addEventListener("click", (event) => {
      event.preventDefault();
      toggleSaved(item);
    });
    return button;
  }

  function emptyState(prefix, message) {
    const line = el("p", { class: "terminal-line" }, [
      el("span", { class: "prompt", text: prefix }),
      " no matching items",
    ]);
    return el("div", { class: "empty-state" }, [line, el("h2", { text: message })]);
  }

  // --- text + value helpers ---------------------------------------------

  function summaryText(visible, total, query, tag, source, onlySaved) {
    const parts = [];
    if (onlySaved) parts.push("saved");
    if (query) parts.push('query "' + query + '"');
    if (tag) parts.push("tag " + tag);
    if (source) parts.push("source " + source);
    const scope = parts.length ? " for " + parts.join(", ") : "";
    return visible + " shown / " + total + " matches" + scope;
  }

  const tokens = (value) => norm(value).split(/[^a-z0-9_.+#-]+/).filter(Boolean);
  const norm = (value) => String(value || "").trim().toLowerCase();
  const same = (a, b) => norm(a) === norm(b);

  function dateValue(item) {
    const value = Date.parse(item.published_at || item.collected_at || "");
    return Number.isFinite(value) ? value : 0;
  }

  function dateLabel(item) {
    const value = dateValue(item);
    return value ? new Date(value).toISOString().slice(0, 10) : "unknown";
  }

  function safeURL(value) {
    try {
      const url = new URL(value, location.href);
      return url.protocol === "http:" || url.protocol === "https:" ? url.href : "#";
    } catch (_) {
      return "#";
    }
  }
})();
