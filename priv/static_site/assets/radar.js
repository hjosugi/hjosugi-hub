// Radar page entry: data loading, routing, rendering, and autocomplete UI.
import { collator, norm, same, safeURL, el, withParam, debounce } from "./radar-util.js";
import { prepare, rank, facets } from "./radar-search.js";

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
  const suggestNode = document.getElementById("search-suggest");

  // The landing view shows only the last N days; search opens the full archive.
  const RECENT_DAYS = 30;

  // Category-scoped views: all (/radar/), github (/radar/github/, links to
  // github.com), news (/radar/news/, aggregator sources). Each is its own URL
  // for deep links and no-JS, but switching tabs is client-side (no reload):
  // the category is a mutable filter re-applied over the items already loaded.
  let category = app.dataset.category || categoryFromPath();

  function categoryFromPath() {
    if (/\/radar\/github\/?$/.test(location.pathname)) return "github";
    if (/\/radar\/news\/?$/.test(location.pathname)) return "news";
    return "all";
  }

  function isGithubUrl(url) {
    try {
      const host = new URL(url).hostname.toLowerCase();
      return host === "github.com" || host.endsWith(".github.com");
    } catch (_) {
      return false;
    }
  }

  function inCategory(item) {
    if (category === "github") return isGithubUrl(item.url);
    if (category === "news") return item.source_kind === "aggregator";
    return true;
  }

  // The link's host, shown in each card so it is obvious where an item points
  // (e.g. why a Hacker News story appears on the github page: it links github.com).
  function linkHost(url) {
    try {
      return new URL(url).hostname.replace(/^www\./, "");
    } catch (_) {
      return "";
    }
  }

  // On phones the facet lists are long, so the filter panel is a disclosure that
  // stays collapsed; on wider screens it is always open as a sidebar.
  const filterDisclosure = app.querySelector(".filter-disclosure");
  if (filterDisclosure) {
    const wide = window.matchMedia("(min-width: 821px)");
    const syncFilters = () => {
      filterDisclosure.open = wide.matches;
    };
    syncFilters();
    wide.addEventListener("change", syncFilters);
  }

  let allItems = [];
  let items = [];
  // Recomputed whenever the category changes (counts and facets are scoped).
  let tagFacets = [];
  let sourceFacets = [];
  let uniqueTags = [];
  let uniqueSources = [];

  // Re-scope the loaded items to the active category and rebuild its index.
  function applyCategory() {
    items = allItems.filter(inCategory);
    if (totalCountNode) totalCountNode.textContent = String(items.length);
    indexData();
  }

  function indexData() {
    const tags = new Set();
    const sources = new Set();
    for (const item of items) {
      if (item.source_name) sources.add(item.source_name);
      for (const tag of item.tags || []) tags.add(tag);
    }
    uniqueTags = [...tags].sort((a, b) => collator.compare(a, b));
    uniqueSources = [...sources].sort((a, b) => collator.compare(a, b));
    tagFacets = facets(items, "tags");
    sourceFacets = facets(items, "source_name");
  }

  const onNavigate = (params) => (event) => {
    event.preventDefault();
    navigate(params);
  };

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
      allItems = (Array.isArray(data) ? data : []).map(prepare);
      applyCategory();
      updateActiveTab();
      updateFromLocation();
    })
    .catch(() => {
      summaryNode.textContent = "Could not load the static radar index.";
      resultsNode.replaceChildren(emptyState("!", "The static data file is missing or unavailable."));
    });

  form?.addEventListener("submit", (event) => {
    event.preventDefault();
    closeSuggest();
    navigate(withParam(currentParams(), "q", input.value.trim()));
  });

  window.addEventListener("popstate", switchFromLocation);

  // Tabs switch category without a full page load: intercept the click, push the
  // tab's URL, then re-scope and re-render in place.
  const tabs = [...app.querySelectorAll(".radar-tab")];
  for (const tab of tabs) {
    tab.addEventListener("click", (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.button) return;
      event.preventDefault();
      closeSuggest();
      history.pushState(null, "", tab.getAttribute("href"));
      switchFromLocation();
    });
  }

  function updateActiveTab() {
    for (const tab of tabs) {
      const active = tab.dataset.category === category;
      tab.classList.toggle("active", active);
      if (active) tab.setAttribute("aria-current", "page");
      else tab.removeAttribute("aria-current");
    }
  }

  function switchFromLocation() {
    const next = categoryFromPath();
    if (next !== category) {
      category = next;
      applyCategory();
      updateActiveTab();
    }
    updateFromLocation();
  }

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
    const tagN = norm(tag);
    const sourceN = norm(source);

    const ranked = rank(items, query).filter((item) => {
      if (onlySaved && !isSaved(item)) return false;
      if (tagN && !(item.tags || []).some((value) => norm(value) === tagN)) return false;
      if (sourceN && item._s.src !== sourceN && item._srcId !== sourceN) return false;
      if (defaultView && item._ts < cutoff) return false;
      return true;
    });
    const visible = ranked.slice(0, 80);

    summaryNode.textContent = defaultView
      ? "top " + visible.length + " from the last " + RECENT_DAYS + " days · " + items.length + " indexed — search to see all"
      : summaryText(visible.length, ranked.length, query, tag, source, onlySaved);
    clearNode.hidden = !(query || tag || source || onlySaved);
    clearNode.onclick = onNavigate(new URLSearchParams());

    renderSavedFacet(savedFacetsNode, items.filter(isSaved).length, onlySaved, params);
    renderFacets(tagFacetsNode, tagFacets, "tag", tag, params);
    renderFacets(sourceFacetsNode, sourceFacets, "source", source, params);

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

  // --- cards -------------------------------------------------------------

  function renderCard(item) {
    const host = linkHost(item.url);
    const meta = el("div", { class: "radar-meta" }, [
      el("span", { text: item.source_name || "unknown source" }),
      host ? el("span", { class: "radar-host", text: host }) : null,
      el("span", { text: item._date }),
      item.source_kind ? el("span", { text: item.source_kind }) : null,
      item.score > 0
        ? el("span", {
            class: "radar-score",
            title: "crowd-vote points (e.g. Hacker News upvotes)",
            text: "▲ " + item.score + " pts",
          })
        : null,
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

  function summaryText(visible, total, query, tag, source, onlySaved) {
    const parts = [];
    if (onlySaved) parts.push("saved");
    if (query) parts.push('query "' + query + '"');
    if (tag) parts.push("tag " + tag);
    if (source) parts.push("source " + source);
    const scope = parts.length ? " for " + parts.join(", ") : "";
    return visible + " shown / " + total + " matches" + scope;
  }

  // --- autocomplete ------------------------------------------------------

  let suggestions = [];
  let activeIndex = -1;

  function computeSuggestions(value) {
    const q = norm(value);
    if (q.length < 2) return [];
    const tagHits = uniqueTags
      .filter((t) => norm(t).includes(q))
      .slice(0, 4)
      .map((t) => ({ kind: "tag", label: t }));
    const sourceHits = uniqueSources
      .filter((s) => norm(s).includes(q))
      .slice(0, 3)
      .map((s) => ({ kind: "source", label: s }));
    const titleHits = rank(items.filter((i) => i._s.t.includes(q)), value)
      .slice(0, 6)
      .map((i) => ({ kind: "item", label: i.title || "Untitled", item: i }));
    return [...tagHits, ...sourceHits, ...titleHits].slice(0, 12);
  }

  function renderSuggest() {
    if (!suggestNode) return;
    if (suggestions.length === 0) return closeSuggest();
    const rows = suggestions.map((s, idx) => {
      const row = el(
        "div",
        { class: "suggest-item" + (idx === activeIndex ? " active" : ""), role: "option" },
        [
          el("span", { class: "suggest-kind", text: s.kind === "item" ? "open" : s.kind }),
          el("span", { class: "suggest-label", text: s.label }),
        ]
      );
      // mousedown (not click) fires before the input blur, so focus is kept.
      row.addEventListener("mousedown", (event) => {
        event.preventDefault();
        selectSuggestion(idx);
      });
      return row;
    });
    suggestNode.replaceChildren(...rows);
    suggestNode.hidden = false;
    input.setAttribute("aria-expanded", "true");
  }

  function closeSuggest() {
    suggestions = [];
    activeIndex = -1;
    if (suggestNode) {
      suggestNode.hidden = true;
      suggestNode.replaceChildren();
    }
    input.setAttribute("aria-expanded", "false");
  }

  function selectSuggestion(idx) {
    const choice = suggestions[idx];
    if (!choice) return;
    closeSuggest();
    if (choice.kind === "item") {
      window.open(safeURL(choice.item.url), "_blank", "noopener");
      return;
    }
    input.value = "";
    navigate(withParam(new URLSearchParams(), choice.kind, choice.label));
  }

  if (input && suggestNode) {
    input.addEventListener(
      "input",
      debounce(() => {
        suggestions = computeSuggestions(input.value);
        activeIndex = -1;
        renderSuggest();
      }, 120)
    );

    input.addEventListener("keydown", (event) => {
      if (suggestNode.hidden || suggestions.length === 0) return;
      if (event.key === "ArrowDown") {
        event.preventDefault();
        activeIndex = (activeIndex + 1) % suggestions.length;
        renderSuggest();
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        activeIndex = (activeIndex - 1 + suggestions.length) % suggestions.length;
        renderSuggest();
      } else if (event.key === "Enter" && activeIndex >= 0) {
        event.preventDefault();
        selectSuggestion(activeIndex);
      } else if (event.key === "Escape") {
        closeSuggest();
      }
    });

    input.addEventListener("blur", () => window.setTimeout(closeSuggest, 120));
  }
})();
