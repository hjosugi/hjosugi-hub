(() => {
  const app = document.querySelector("[data-signal-app]");
  if (!app) return;

  const form = document.getElementById("static-search-form");
  const input = document.getElementById("signal-search");
  const resultsNode = app.querySelector("[data-results]");
  const summaryNode = app.querySelector("[data-result-summary]");
  const clearNode = app.querySelector("[data-clear-filters]");
  const tagFacetsNode = app.querySelector("[data-tag-facets]");
  const sourceFacetsNode = app.querySelector("[data-source-facets]");
  const totalCountNode = app.querySelector("[data-total-count]");
  let items = [];

  const collator = new Intl.Collator(undefined, { sensitivity: "base" });

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
      summaryNode.textContent = "Could not load the static signal index.";
      resultsNode.replaceChildren(emptyState("!", "The static data file is missing or unavailable."));
    });

  form?.addEventListener("submit", (event) => {
    event.preventDefault();
    const params = currentParams();
    params.set("q", input.value.trim());
    if (!params.get("q")) params.delete("q");
    navigate(params);
  });

  window.addEventListener("popstate", updateFromLocation);

  function updateFromLocation() {
    const params = currentParams();
    input.value = params.get("q") || "";
    render(params);
  }

  function render(params) {
    const query = params.get("q") || "";
    const tag = params.get("tag") || "";
    const source = params.get("source") || "";
    const ranked = rank(items, query)
      .filter((item) => !tag || item.tags?.some((value) => same(value, tag)))
      .filter((item) => !source || same(item.source_name, source) || same(item.source_id, source));
    const visible = ranked.slice(0, 80);

    summaryNode.textContent = summaryText(visible.length, ranked.length, query, tag, source);
    clearNode.hidden = !(query || tag || source);
    clearNode.onclick = (event) => {
      event.preventDefault();
      navigate(new URLSearchParams());
    };

    renderFacets(tagFacetsNode, facets(items, "tags"), "tag", tag, params);
    renderFacets(sourceFacetsNode, facets(items, "source_name"), "source", source, params);

    if (visible.length === 0) {
      resultsNode.replaceChildren(emptyState("!", "Try a broader query or clear the active filters."));
      return;
    }
    resultsNode.replaceChildren(...visible.map(renderCard));
  }

  function rank(values, query) {
    const terms = tokens(query);
    return [...values].map((item) => ({ item, score: score(item, terms, query) }))
      .sort((a, b) => b.score - a.score || dateValue(b.item) - dateValue(a.item))
      .map((entry) => entry.item);
  }

  function score(item, terms, query) {
    const dateScore = Math.max(0, dateValue(item) / 10000000000000);
    const phrase = norm(query);
    const title = norm(item.title);
    const tags = norm((item.tags || []).join(" "));
    const source = norm(item.source_name);
    const body = norm([item.summary, item.content, item.author].filter(Boolean).join(" "));
    let value = 0;
    if (terms.length === 0 && !phrase) return dateScore;
    for (const term of terms) {
      if (title === term) value += 12;
      if (title.includes(term)) value += 7;
      if (tags.includes(term)) value += 5;
      if (source.includes(term)) value += 3;
      if (body.includes(term)) value += 1;
    }
    if (phrase) {
      if (title.includes(phrase)) value += 6;
      if (tags.includes(phrase)) value += 4;
      if (source.includes(phrase)) value += 3;
      if (body.includes(phrase)) value += 2;
    }
    return value + dateScore;
  }

  function renderFacets(node, entries, key, activeValue, baseParams) {
    const all = facetLink("all", "", key, activeValue === "", baseParams, 0);
    const links = [all, ...entries.slice(0, 28).map((entry) => facetLink(entry.name, entry.name, key, same(activeValue, entry.name), baseParams, entry.count))];
    node.replaceChildren(...links);
  }

  function facetLink(label, value, key, active, baseParams, count) {
    const params = new URLSearchParams(baseParams);
    if (value) params.set(key, value);
    else params.delete(key);
    const link = document.createElement("a");
    link.className = "filter-link" + (active ? " active" : "");
    link.href = "?" + params.toString();
    link.addEventListener("click", (event) => {
      event.preventDefault();
      navigate(params);
    });

    const name = document.createElement("span");
    name.textContent = label;
    link.append(name);
    if (count > 0) {
      const badge = document.createElement("b");
      badge.textContent = String(count);
      link.append(badge);
    }
    return link;
  }

  function renderCard(item) {
    const article = document.createElement("article");
    article.className = "signal-card";

    const meta = document.createElement("div");
    meta.className = "signal-meta";
    meta.append(textSpan(item.source_name || "unknown source"));
    meta.append(textSpan(dateLabel(item)));
    if (item.source_kind) meta.append(textSpan(item.source_kind));

    const title = document.createElement("h2");
    const link = document.createElement("a");
    link.href = safeURL(item.url);
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = item.title || "Untitled";
    title.append(link);

    const summary = document.createElement("p");
    summary.textContent = item.summary || "No summary provided by the source.";

    const footer = document.createElement("div");
    footer.className = "signal-footer";
    const chips = document.createElement("div");
    chips.className = "chip-row";
    for (const tag of item.tags || []) {
      const chip = document.createElement("a");
      chip.className = "chip link-chip";
      const params = currentParams();
      params.set("tag", tag);
      chip.href = "?" + params.toString();
      chip.textContent = tag;
      chip.addEventListener("click", (event) => {
        event.preventDefault();
        navigate(params);
      });
      chips.append(chip);
    }
    footer.append(chips);
    if (item.author) {
      const author = document.createElement("span");
      author.textContent = "by " + item.author;
      footer.append(author);
    }

    article.append(meta, title, summary, footer);
    return article;
  }

  function emptyState(prefix, message) {
    const box = document.createElement("div");
    box.className = "empty-state";
    const line = document.createElement("p");
    line.className = "terminal-line";
    const prompt = document.createElement("span");
    prompt.className = "prompt";
    prompt.textContent = prefix;
    line.append(prompt, " no matching signals");
    const title = document.createElement("h2");
    title.textContent = message;
    box.append(line, title);
    return box;
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

  function summaryText(visible, total, query, tag, source) {
    const parts = [];
    if (query) parts.push("query \"" + query + "\"");
    if (tag) parts.push("tag " + tag);
    if (source) parts.push("source " + source);
    const scope = parts.length ? " for " + parts.join(", ") : "";
    return visible + " shown / " + total + " matches" + scope;
  }

  function navigate(params) {
    const query = params.toString();
    history.pushState(null, "", query ? "?" + query : location.pathname);
    updateFromLocation();
  }

  function currentParams() {
    return new URLSearchParams(location.search);
  }

  function tokens(value) {
    return norm(value).split(/[^a-z0-9_.+#-]+/).filter(Boolean);
  }

  function norm(value) {
    return String(value || "").trim().toLowerCase();
  }

  function same(a, b) {
    return norm(a) === norm(b);
  }

  function dateValue(item) {
    const value = Date.parse(item.published_at || item.collected_at || "");
    return Number.isFinite(value) ? value : 0;
  }

  function dateLabel(item) {
    const value = dateValue(item);
    if (!value) return "unknown";
    return new Date(value).toISOString().slice(0, 10);
  }

  function textSpan(value) {
    const span = document.createElement("span");
    span.textContent = value;
    return span;
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
