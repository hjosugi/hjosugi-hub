// Shared, state-free helpers for the radar page.

export const collator = new Intl.Collator(undefined, { sensitivity: "base" });

const foldKatakana = (value) =>
  value.replace(/[\u30a1-\u30f6]/g, (char) => String.fromCharCode(char.charCodeAt(0) - 0x60));

// Character normalization only: no dictionary transliteration between scripts.
export const norm = (value) =>
  foldKatakana(String(value || "").normalize("NFKC").trim().toLowerCase()).replace(/\u30fc/g, "");
export const same = (a, b) => norm(a) === norm(b);
export const tokens = (value) => norm(value).split(/[^a-z0-9_.+#-]+/).filter(Boolean);

export function parseTs(value) {
  const ts = Date.parse(value || "");
  return Number.isFinite(ts) ? ts : 0;
}

export function safeURL(value) {
  try {
    const url = new URL(value, location.href);
    return url.protocol === "http:" || url.protocol === "https:" ? url.href : "#";
  } catch (_) {
    return "#";
  }
}

// el("a", {class, href, text, "aria-pressed"}, child|[children]) -> element.
// Known DOM properties are assigned directly; everything else via attribute.
export function el(tag, props = {}, children = []) {
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

export function withParam(base, key, value) {
  const params = new URLSearchParams(base);
  if (value) params.set(key, value);
  else params.delete(key);
  return params;
}

export function debounce(fn, ms) {
  let timer;
  return () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(fn, ms);
  };
}
