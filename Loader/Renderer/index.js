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

export function createWindowEffects({ prismService, backgroundService, settingsSections }) {
  const mounted = [];
  function mount(id) {
    const effect = effects.get(id);
    const root = document.createElement("div");
    root.dataset.packpierPlugin = id;
    document.body.append(root);
    const cleanups = [() => root.remove()];
    const onCleanup = callback => cleanups.push(callback);
    try {
      if (effect.css) {
        const style = document.createElement("style");
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
