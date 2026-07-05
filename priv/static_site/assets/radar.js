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
    });
  }

  const currentParams = () => new URLSearchParams(location.search);

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
