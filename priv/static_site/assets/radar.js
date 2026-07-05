// Radar page entry: data loading, routing, and autocomplete UI wiring.
import { safeURL, el, withParam, debounce } from "./radar-util.js";
import { createRadarState } from "./radar-state.js";
import { renderRadar, emptyState } from "./radar-render.js";

(() => {
  const app = document.querySelector("[data-radar-app]");
  if (!app) return;

  const form = document.getElementById("static-search-form");
  const input = document.getElementById("radar-search");
  const nodes = {
    resultsNode: app.querySelector("[data-results]"),
    summaryNode: app.querySelector("[data-result-summary]"),
    clearNode: app.querySelector("[data-clear-filters]"),
    tagFacetsNode: app.querySelector("[data-tag-facets]"),
    sourceFacetsNode: app.querySelector("[data-source-facets]"),
    savedFacetsNode: app.querySelector("[data-saved-facets]"),
  };
  const totalCountNode = app.querySelector("[data-total-count]");
  const suggestNode = document.getElementById("search-suggest");
  const state = createRadarState(app.dataset.category || "all");
  let activeResultIndex = -1;
  let focusActiveAfterRender = false;

  setupFilterDisclosure(app);

  const onNavigate = (params) => (event) => {
    event.preventDefault();
    navigate(params);
  };

  fetch(app.dataset.itemsUrl)
    .then((response) => {
      if (!response.ok) throw new Error("items request failed");
      return response.json();
    })
    .then((data) => {
      state.setItems(data);
      updateFromLocation();
    })
    .catch(() => {
      nodes.summaryNode.textContent = "Could not load the static radar index.";
      nodes.resultsNode.replaceChildren(emptyState("!", "The static data file is missing or unavailable."));
    });

  form?.addEventListener("submit", (event) => {
    event.preventDefault();
    closeSuggest();
    activeResultIndex = -1;
    navigate(withParam(currentParams(), "q", input.value.trim()));
    input.blur();
  });

  window.addEventListener("popstate", updateFromLocation);
  document.addEventListener("keydown", handleResultKeys);

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

  function render(params) {
    if (totalCountNode) totalCountNode.textContent = String(state.totalCount());
    renderRadar(nodes, state.filteredView(params), {
      params,
      onNavigate,
      currentParams,
      isSaved: state.isSaved,
      toggleSaved: (item) => {
        state.toggleSaved(item);
        render(currentParams());
      },
      exportSaved: () => downloadSaved(state.exportSaved()),
      importSaved: async (file) => {
        try {
          const payload = JSON.parse(await file.text());
          state.importSaved(payload);
          render(currentParams());
        } catch (_) {
          nodes.summaryNode.textContent = "Could not import saved items from that JSON file.";
        }
      },
    });
    syncActiveResult();
  }

  const currentParams = () => new URLSearchParams(location.search);

  function resultCards() {
    return [...nodes.resultsNode.querySelectorAll("[data-result-card]")];
  }

  function syncActiveResult() {
    const cards = resultCards();
    if (cards.length === 0) {
      activeResultIndex = -1;
      focusActiveAfterRender = false;
      return;
    }
    if (activeResultIndex >= cards.length) activeResultIndex = cards.length - 1;
    cards.forEach((card, idx) => {
      const active = idx === activeResultIndex;
      card.classList.toggle("keyboard-active", active);
      card.tabIndex = active ? 0 : -1;
    });
    if (focusActiveAfterRender && activeResultIndex >= 0) {
      cards[activeResultIndex].focus({ preventScroll: true });
    }
    focusActiveAfterRender = false;
  }

  function moveActiveResult(delta) {
    const cards = resultCards();
    if (cards.length === 0) return;
    const fallback = delta > 0 ? 0 : cards.length - 1;
    const next = activeResultIndex < 0 ? fallback : activeResultIndex + delta;
    activeResultIndex = Math.max(0, Math.min(cards.length - 1, next));
    syncActiveResult();
    const active = cards[activeResultIndex];
    active.focus({ preventScroll: true });
    active.scrollIntoView({ block: "nearest" });
  }

  function activeResultCard() {
    const cards = resultCards();
    return activeResultIndex >= 0 ? cards[activeResultIndex] : null;
  }

  function openActiveResult() {
    const link = activeResultCard()?.querySelector("h2 a");
    if (link) window.open(link.href, "_blank", "noopener");
  }

  function toggleActiveSaved() {
    const button = activeResultCard()?.querySelector(".save-btn");
    if (!button) return;
    focusActiveAfterRender = true;
    button.click();
  }

  function handleResultKeys(event) {
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return;
    if (isInteractiveTarget(event.target)) return;
    if (event.key === "j") {
      event.preventDefault();
      moveActiveResult(1);
    } else if (event.key === "k") {
      event.preventDefault();
      moveActiveResult(-1);
    } else if ((event.key === "o" || event.key === "Enter") && activeResultIndex >= 0) {
      event.preventDefault();
      openActiveResult();
    } else if (event.key === "s" && activeResultIndex >= 0) {
      event.preventDefault();
      toggleActiveSaved();
    }
  }

  // --- autocomplete ------------------------------------------------------

  let suggestions = [];
  let activeIndex = -1;

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
        suggestions = state.suggestions(input.value);
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

function isInteractiveTarget(target) {
  return Boolean(
    target?.closest?.("a, button, input, textarea, select, [contenteditable='true'], [contenteditable='']")
  );
}

function downloadSaved(payload) {
  const blob = new Blob([JSON.stringify(payload, null, 2) + "\n"], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "hjosugi-hub-saved.json";
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

function setupFilterDisclosure(app) {
  // On phones the facet lists are long, so the filter panel is a disclosure that
  // stays collapsed; on wider screens it is always open as a sidebar.
  const filterDisclosure = app.querySelector(".filter-disclosure");
  if (!filterDisclosure) return;
  const wide = window.matchMedia("(min-width: 821px)");
  const syncFilters = () => {
    filterDisclosure.open = wide.matches;
  };
  syncFilters();
  wide.addEventListener("change", syncFilters);
}
