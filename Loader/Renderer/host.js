// Packpier window runtime. Runs inside each injectable Codex page.
// The Node host provides __packpierRpc; this module never talks to CDP directly.
import { createWindowEffects } from "./index.js";

import { backgroundTitle, registerBackgroundNavigation } from "./background-settings-nav.js";

const VERSION = "packpier-window-4";

const pending = new Map();
const listeners = new Map();
let sequence = 0;

function subscribe(plugin, name, callback) {
  const key = plugin + ":" + name;
  const set = listeners.get(key) ?? new Set();
  set.add(callback);
  listeners.set(key, set);
  return () => { set.delete(callback); if (!set.size) listeners.delete(key); };
}

function emit(plugin, name, payload) {
  for (const callback of listeners.get(plugin + ":" + name) ?? []) {
    try { callback(payload); } catch (error) { console.error("Packpier event handler failed", error); }
  }
}

function invoke(plugin, method, parameters) {
  if (typeof globalThis.__packpierRpc !== "function") {
    return Promise.reject(new Error("Packpier host is not connected"));
  }
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    try {
      globalThis.__packpierRpc(JSON.stringify({ id, plugin, method, parameters: parameters ?? {} }));
    } catch (error) {
      pending.delete(id);
      reject(error);
    }
  });
}

globalThis.__packpierResolve = (id, ok, value) => {
  const entry = pending.get(Number(id));
  if (!entry) return;
  pending.delete(Number(id));
  if (ok) entry.resolve(value);
  else entry.reject(new Error(value?.message ?? String(value)));
};
globalThis.__packpierEvent = (plugin, name, payload) => emit(String(plugin), String(name), payload);

/* Settings host: mounts plugin settings panes in a Packpier-owned sheet instead of
   depending on Codex's private settings router. */
const settingsSections = (() => {
  let overlay = null;
  let body = null;
  let detach = null;

  function close() {
    if (typeof detach === "function") { try { detach(); } catch {} }
    detach = null;
    if (overlay) overlay.hidden = true;
  }

  function onKeyDown(event) {
    if (event.key === "Escape" && overlay && !overlay.hidden) close();
  }

  function ensure() {
    if (overlay?.isConnected) return;
    overlay = document.createElement("div");
    overlay.dataset.packpierSettingsOverlay = "";
    overlay.hidden = true;
    overlay.innerHTML = `<div data-packpier-settings-backdrop></div>
      <section data-packpier-settings-sheet role="dialog" aria-modal="true">
        <header><span data-packpier-settings-title></span>
        <button type="button" data-packpier-settings-close aria-label="Close">✕</button></header>
        <div data-packpier-settings-body></div>
      </section>`;
    const style = document.createElement("style");
    style.textContent = `
      [data-packpier-background-nav] { display:flex; align-items:center; gap:8px; width:100%; padding:6px 8px; border:0; border-radius:7px; color:inherit; background:transparent; text-align:start; font:inherit; font-size:14px; cursor:pointer; }
      [data-packpier-background-nav]:hover, [data-packpier-background-nav][aria-current] { background:color-mix(in srgb, currentColor 9%, transparent); }
      [data-packpier-background-nav]:focus-visible { outline:2px solid Highlight; outline-offset:-2px; }
      [data-packpier-show-background] > :not([data-packpier-background-pane]) { display:none !important; }
      [data-packpier-background-pane] { flex:1; min-height:0; min-width:0; overflow:auto; }
      [data-packpier-settings-overlay] { position: fixed; inset: 0; z-index: 2147483000; display: grid; place-items: center; }
      [data-packpier-settings-overlay][hidden] { display: none; }
      [data-packpier-settings-backdrop] { position: absolute; inset: 0; background: rgb(0 0 0 / .45); backdrop-filter: blur(6px); }
      [data-packpier-settings-sheet] { position: relative; width: min(720px, calc(100vw - 64px)); height: min(620px, calc(100vh - 96px));
        display: flex; flex-direction: column; overflow: hidden; border-radius: 16px;
        background: light-dark(#fff, #1d1d20); color: light-dark(#18181b, #f4f4f5);
        box-shadow: 0 24px 80px rgb(0 0 0 / .45); border: 1px solid light-dark(rgb(0 0 0 / .08), rgb(255 255 255 / .1)); }
      [data-packpier-settings-sheet] > header { display: flex; align-items: center; justify-content: space-between;
        padding: 14px 18px; border-bottom: 1px solid light-dark(rgb(0 0 0 / .07), rgb(255 255 255 / .08)); font-weight: 600; }
      [data-packpier-settings-close] { border: 0; background: transparent; color: inherit; font-size: 15px; cursor: pointer;
        width: 28px; height: 28px; border-radius: 8px; }
      [data-packpier-settings-close]:hover { background: light-dark(rgb(0 0 0 / .06), rgb(255 255 255 / .1)); }
      [data-packpier-settings-body] { flex: 1; overflow: auto; }
    `;
    overlay.prepend(style);
    document.body.append(overlay);
    body = overlay.querySelector("[data-packpier-settings-body]");
    overlay.querySelector("[data-packpier-settings-close]").addEventListener("click", close);
    overlay.querySelector("[data-packpier-settings-backdrop]").addEventListener("click", close);
    document.addEventListener("keydown", onKeyDown);
  }

  return {
    register(section) {
      ensure();
      function openSheet() {
        ensure();
        overlay.querySelector("[data-packpier-settings-title]").textContent = section.title || backgroundTitle();
        close();
        body.replaceChildren();
        detach = section.mount(body) || null;
        overlay.hidden = false;
      }
      const navigation = registerBackgroundNavigation(section, close, openSheet);
      return {
        open() {
          if (!navigation.openInline()) openSheet();
        },
        unregister() {
          navigation.unregister();
          close();
          overlay?.remove();
          overlay = null;
          body = null;
          document.removeEventListener("keydown", onKeyDown);
        },
      };
    },
  };
})();

const prismService = {
  invoke: (method, parameters) => invoke("prism", method, parameters),
  on: (name, callback) => subscribe("prism", name, callback),
};
const backgroundService = {
  invoke: (method, parameters) => invoke("custom-background", method, parameters),
  on: (name, callback) => subscribe("custom-background", name, callback),
};

const effects = createWindowEffects({ prismService, backgroundService, settingsSections });

globalThis.__PACKPIER__ = {
  version: VERSION,
  apply(state) {
    try {
      return effects.apply(state);
    } catch (error) {
      return { mounted: [], errors: { runtime: String(error?.message ?? error) } };
    }
  },
  close() { try { effects.close(); } catch {} },
};