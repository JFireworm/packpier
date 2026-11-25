import assert from "node:assert/strict";
import { test } from "node:test";
import { effectiveCSSZoom } from "./css-zoom.js";

test("uses positive finite CSS zoom and falls back to 1", () => {
  for (const zoom of [0.8, 1, 1.25]) {
    assert.equal(effectiveCSSZoom({ currentCSSZoom: zoom }), zoom);
  }
  for (const zoom of [undefined, 0, -1, Infinity, NaN]) {
    assert.equal(effectiveCSSZoom({ currentCSSZoom: zoom }), 1);
  }
});
