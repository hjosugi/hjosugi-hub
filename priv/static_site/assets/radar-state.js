// Radar state: category scoping, saved items, filtering, and suggestions.
import { collator, norm } from "./radar-util.js";
import { prepare, rank, facets } from "./radar-search.js";

// The landing view shows only the last N days; search opens the full archive.
export const RECENT_DAYS = 30;

const SAVED_KEY = "hjosugi-hub-saved";

export function createRadarState(category = "all") {
  let allItems = [];
  let items = [];
  let tagFacets = [];
  let sourceFacets = [];
  let uniqueTags = [];
  let uniqueSources = [];
  let totalCountOverride = null;
  const saved = loadSaved();

  function setItems(data, options = {}) {
    allItems = (Array.isArray(data) ? data : []).map(prepare);
    totalCountOverride = Number.isFinite(options.totalCount) ? options.totalCount : null;
    applyCategory();
  }

  function applyCategory() {
    items = allItems.filter(inCategory);
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

  function inCategory(item) {
    if (category === "github") return isGithubUrl(item.url);
    return true;
  }

  const itemKey = (item) => String(item.id || item.url || item.title || "");
  const isSaved = (item) => saved.has(itemKey(item));

  function toggleSaved(item) {
    const key = itemKey(item);
    saved.has(key) ? saved.delete(key) : saved.add(key);
    persistSaved(saved);
  }

  function exportSaved() {
    const byKey = new Map(allItems.map((item) => [itemKey(item), item]));
    return {
      version: 1,
      exported_at: new Date().toISOString(),
      items: [...saved].sort().map((key) => exportSavedItem(key, byKey.get(key))),
    };
  }

  function importSaved(payload) {
    const imported = importSavedItems(payload);
    let added = 0;
    for (const entry of imported) {
      const key = importedKey(entry);
      if (!key || saved.has(key)) continue;
      saved.add(key);
      added += 1;
    }
    if (added > 0) persistSaved(saved);
    return { imported: imported.length, added, savedSize: saved.size };
  }

  function filteredView(params) {
    const query = params.get("q") || "";
    const tag = params.get("tag") || "";
    const source = params.get("source") || "";
    const onlySaved = params.get("saved") === "1";
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

    return {
      query,
      tag,
      source,
      onlySaved,
      defaultView,
      ranked,
      visible: ranked.slice(0, 80),
      totalCount: totalCount(),
      savedCount: items.filter(isSaved).length,
      savedSize: saved.size,
      tagFacets,
      sourceFacets,
    };
  }

  function suggestions(value) {
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

  return {
    setItems,
    totalCount,
    filteredView,
    suggestions,
    isSaved,
    toggleSaved,
    exportSaved,
    importSaved,
  };

  function totalCount() {
    return totalCountOverride ?? items.length;
  }
}

function exportSavedItem(key, item) {
  return {
    key,
    id: item?.id || null,
    url: item?.url || "",
    title: item?.title || "",
    source_name: item?.source_name || "",
    saved_key: key,
  };
}

function importSavedItems(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload?.version === 1 && Array.isArray(payload.items)) return payload.items;
  return [];
}

function importedKey(entry) {
  if (typeof entry === "string") return entry.trim();
  if (!entry || typeof entry !== "object") return "";
  return String(entry.key || entry.saved_key || entry.id || entry.url || entry.title || "").trim();
}

function loadSaved() {
  try {
    const list = JSON.parse(window.localStorage.getItem(SAVED_KEY) || "[]");
    return new Set(Array.isArray(list) ? list.map(String) : []);
  } catch (_) {
    return new Set();
  }
}

function persistSaved(saved) {
  try {
    window.localStorage.setItem(SAVED_KEY, JSON.stringify([...saved]));
  } catch (_) {
    /* private mode or full storage: keep the in-memory set only */
  }
}

function isGithubUrl(url) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host === "github.com" || host.endsWith(".github.com");
  } catch (_) {
    return false;
  }
}
