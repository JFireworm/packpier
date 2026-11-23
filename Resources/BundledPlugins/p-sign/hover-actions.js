// Public v1 contract. Providers own their native button, its callback and its lifetime.
export const changedEvent = "packpier:p-sign:actions-changed:v1";
const selector = "button[data-packpier-p-sign-action]";
const actionID = /^[a-z0-9][a-z0-9._-]*\/[a-z0-9][a-z0-9._-]*$/;
const defaultPath = "M5 12h14M12 5v14";
const svgNS = "http://www.w3.org/2000/svg";

function available(source) {
  return source.isConnected && !source.matches(":disabled") && source.getAttribute("aria-disabled") !== "true";
}

export function hoverActions(toolbar, anchor) {
  const items = new Map();

  function add(id) {
    const button = document.createElement("button");
    button.type = "button";
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    const path = document.createElementNS(svgNS, "path");
    svg.append(path);
    button.append(svg);
    const item = { button, path, source: null };
    button.addEventListener("click", () => {
      if (available(item.source) && item.source.dataset.packpierPSignAction === id) item.source.click();
    });
    items.set(id, item);
    toolbar.append(button);
    return item;
  }

  function refresh() {
    const found = new Set();
    for (const source of document.querySelectorAll(selector)) {
      const id = source.dataset.packpierPSignAction;
      const label = source.getAttribute("aria-label")?.trim();
      if (!actionID.test(id) || !label || found.has(id)) continue;
      found.add(id);
      const item = items.get(id) || add(id);
      item.source = source;
      item.path.setAttribute("d", source.dataset.packpierPSignPath || defaultPath);
      item.button.setAttribute("aria-label", label);
      item.button.setAttribute("aria-disabled", String(!available(source)));
      item.button.dataset.tip = source.title || label;
    }
    for (const [id, item] of items) {
      if (found.has(id)) continue;
      if (document.activeElement === item.button) anchor.focus();
      item.button.remove();
      items.delete(id);
    }
  }

  function clear() {
    for (const { button } of items.values()) button.remove();
    items.clear();
  }
  return { refresh, clear };
}
