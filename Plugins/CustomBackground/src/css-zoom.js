export function effectiveCSSZoom(element) {
  const zoom = element.currentCSSZoom;
  return Number.isFinite(zoom) && zoom > 0 ? zoom : 1;
}
