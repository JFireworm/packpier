// First-party effects for a host document. The host provides each plugin's services.
import { activate as sign } from "../../Resources/BundledPlugins/p-sign/index.js";
import signStyle from "../../Resources/BundledPlugins/p-sign/style.css";
import { activate as prism } from "../../Plugins/Prism/renderer.js";
import { activate as background } from "../../Plugins/CustomBackground/src/index.js";
import backgroundStyle from "../../Plugins/CustomBackground/src/style.css";

const effects = new Map([
  ["p-sign", { activate: sign, css: signStyle }],
  ["prism", { activate: prism }],
  ["custom-background", { activate: background, css: backgroundStyle }],
]);

// Inspect selectors so comments and CSS strings in Codex's own sheets are untouched.
const legacySelector = /(?:\.packpier-p-sign(?![\w-])|\.prism-[\w-]+|\[data-(?:packpier-cbgp[\w-]*|packpier-settings-overlay|prism-[\w-]+)(?=[\s~|^$*=\]]))/;

function usesLegacySelectors(rules) {
  return Array.from(rules ?? []).some(rule =>
    legacySelector.test(rule.selectorText ?? "") || usesLegacySelectors(rule.cssRules));
}

export function createWindowEffects({ prismService, backgroundService, settingsSections }) {
  for (const style of document.querySelectorAll("style:not([data-packpier-style])")) {
    if (usesLegacySelectors(style.sheet?.cssRules)) style.remove();
  }
  const mounted = [];
  function mount(id) {
    const effect = effects.get(id);
    for (const orphan of document.querySelectorAll('style[data-packpier-style="' + id + '"]')) orphan.remove();
    const root = document.createElement("div");
    root.dataset.packpierPlugin = id;
    document.body.append(root);
    const cleanups = [() => root.remove()];
    const onCleanup = callback => cleanups.push(callback);
    try {
      if (effect.css) {
        const style = document.createElement("style");
        style.dataset.packpierStyle = id;
        style.textContent = effect.css;
        document.head.append(style);
        onCleanup(() => style.remove());
      }
      effect.activate({
        root, onCleanup, api: { registerCleanup: onCleanup },
        node: id === "prism" ? prismService : id === "custom-background" ? backgroundService : undefined,
        ui: id === "custom-background" ? { settingsSections } : undefined,
      });
    } catch (error) {
      dispose(cleanups);
      throw error;
    }
    return cleanups;
  }
  function dispose(cleanups) {
    for (const clean of cleanups.reverse()) {
      try { clean(); } catch (error) { console.error("Packpier effect cleanup failed", error); }
    }
  }
  function trim(count) {
    while (mounted.length > count) dispose(mounted.pop().cleanups);
  }
  return {
    apply({ enabled, packages, disabledPackageIDs = [] }) {
      const disabled = new Set(disabledPackageIDs);
      const wanted = enabled ? packages.filter(({ id }) => effects.has(id) && !disabled.has(id)) : [];
      // P-Sign provides shortcuts and can join or leave an existing set of effects.
      // Preserve the other effects and open settings panes when only its switch changes.
      const signIndex = mounted.findIndex(item => item.id === "p-sign");
      const nextSign = wanted.findIndex(item => item.id === "p-sign");
      if (signIndex >= 0 && nextSign < 0) dispose(mounted.splice(signIndex, 1)[0].cleanups);
      if (signIndex < 0 && nextSign >= 0 && mounted.length > 0 && mounted.length + 1 === wanted.length &&
          wanted.filter(item => item.id !== "p-sign").every((item, index) => item.id === mounted[index].id)) {
        const errors = {};
        try { mounted.splice(nextSign, 0, { id: "p-sign", cleanups: mount("p-sign") }); }
        catch (error) { errors["p-sign"] = String(error.message ?? error); }
        return { mounted: mounted.map(item => item.id), errors };
      }
      let keep = 0;
      while (keep < wanted.length && keep < mounted.length && wanted[keep].id === mounted[keep].id)
        keep++;
      trim(keep);
      const errors = {};
      for (const { id } of wanted.slice(keep)) {
        try { mounted.push({ id, cleanups: mount(id) }); }
        catch (error) { errors[id] = String(error.message ?? error); }
      }
      return { mounted: mounted.map(item => item.id), errors };
    },
    close() { trim(0); },
  };
}
