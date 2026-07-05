// Radar rendering: result summary, facets, cards, and empty states.
import { same, safeURL, el, withParam } from "./radar-util.js";
import { RECENT_DAYS } from "./radar-state.js";

export function renderRadar(nodes, view, actions) {
  const { resultsNode, summaryNode, clearNode, tagFacetsNode, sourceFacetsNode, savedFacetsNode } = nodes;
  const { params, onNavigate } = actions;

  summaryNode.textContent = view.defaultView
    ? "top " +
      view.visible.length +
      " from the last " +
      RECENT_DAYS +
      " days · " +
      view.totalCount +
      " indexed — search to see all"
    : summaryText(view.visible.length, view.ranked.length, view);
  clearNode.hidden = !(view.query || view.tag || view.source || view.onlySaved);
  clearNode.onclick = onNavigate(new URLSearchParams());

  renderSavedFacet(savedFacetsNode, view.savedCount, view.onlySaved, params, onNavigate, actions);
  renderFacets(tagFacetsNode, view.tagFacets, "tag", view.tag, params, onNavigate);
  renderFacets(sourceFacetsNode, view.sourceFacets, "source", view.source, params, onNavigate);

  if (view.visible.length === 0) {
    const message = view.defaultView
      ? "No items in the last " + RECENT_DAYS + " days — try a search."
      : view.onlySaved && view.savedSize === 0
        ? "Nothing saved yet. Tap the star on any item to keep it here."
        : "Try a broader query or clear the active filters.";
    resultsNode.replaceChildren(emptyState("!", message));
    return;
  }

  resultsNode.replaceChildren(...view.visible.map((item) => renderCard(item, actions)));
}

export function emptyState(prefix, message) {
  const line = el("p", { class: "terminal-line" }, [
    el("span", { class: "prompt", text: prefix }),
    " no matching items",
  ]);
  return el("div", { class: "empty-state" }, [line, el("h2", { text: message })]);
}

function renderSavedFacet(node, count, active, baseParams, onNavigate, actions) {
  if (!node) return;
  const exportButton = el("button", {
    type: "button",
    class: "filter-action",
    text: "export",
    disabled: count === 0,
    "data-export-saved": "",
  });
  exportButton.addEventListener("click", actions.exportSaved);

  const importInput = el("input", {
    type: "file",
    accept: "application/json,.json",
    class: "saved-file-input",
    "data-import-saved": "",
    "aria-label": "Import saved items JSON",
  });
  importInput.addEventListener("change", () => {
    const file = importInput.files?.[0];
    if (file) actions.importSaved(file);
    importInput.value = "";
  });

  node.replaceChildren(
    facetLink("all", "", "saved", !active, baseParams, 0, onNavigate),
    facetLink("★ saved", "1", "saved", active, baseParams, count, onNavigate),
    el("div", { class: "saved-tools" }, [
      exportButton,
      el("label", { class: "filter-action import-action", text: "import" }, importInput),
    ])
  );
}

function renderFacets(node, entries, key, activeValue, baseParams, onNavigate) {
  if (!node) return;
  const links = entries
    .slice(0, 28)
    .map((entry) =>
      facetLink(entry.name, entry.name, key, same(activeValue, entry.name), baseParams, entry.count, onNavigate)
    );
  node.replaceChildren(facetLink("all", "", key, activeValue === "", baseParams, 0, onNavigate), ...links);
}

function facetLink(label, value, key, active, baseParams, count, onNavigate) {
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

function renderCard(item, actions) {
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
    saveButton(item, actions),
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
    el("div", { class: "chip-row" }, (item.tags || []).map((tag) => tagChip(tag, actions))),
    item.author ? el("span", { text: "by " + item.author }) : null,
  ]);

  return el(
    "article",
    { class: "radar-card", tabindex: "-1", "data-result-card": "", "aria-label": item.title || "Untitled" },
    [meta, title, summary, footer]
  );
}

function tagChip(tag, { currentParams, onNavigate }) {
  const params = withParam(currentParams(), "tag", tag);
  const chip = el("a", { class: "chip link-chip", href: "?" + params.toString(), text: tag });
  chip.addEventListener("click", onNavigate(params));
  return chip;
}

function saveButton(item, { isSaved, toggleSaved }) {
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

function linkHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch (_) {
    return "";
  }
}

function summaryText(visible, total, { query, tag, source, onlySaved }) {
  const parts = [];
  if (onlySaved) parts.push("saved");
  if (query) parts.push('query "' + query + '"');
  if (tag) parts.push("tag " + tag);
  if (source) parts.push("source " + source);
  const scope = parts.length ? " for " + parts.join(", ") : "";
  return visible + " shown / " + total + " matches" + scope;
}
