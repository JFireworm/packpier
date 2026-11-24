// Runs in a fresh browser profile against the built renderer and a synthetic Codex document.
import "packpier-test-host";
import { createWindowEffects } from "packpier-test-effects";

function check(value, detail) {
  if (!value) throw Error(detail);
}
async function run() {
  document.documentElement.lang = "zh-CN";
  document.body.innerHTML = `<nav data-app-navigation-rail><div><div><div><button aria-haspopup="menu">Usage</button></div><div>Profile</div></div></div></nav>
    <aside data-sidebar-navigation-root><section data-app-action-sidebar-section data-app-action-sidebar-section-heading="Recents">
      <div data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="sample" data-app-action-sidebar-thread-kind="local">Sample chat</div>
    </section><section data-app-action-sidebar-section data-app-action-sidebar-section-heading="Pinned">
      <h2>Pinned</h2><div data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="pin-one" data-app-action-sidebar-thread-kind="local" data-app-action-sidebar-thread-pinned="true">First pin</div>
      <div data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="pin-two" data-app-action-sidebar-thread-kind="local" data-app-action-sidebar-thread-pinned="true">Second pin</div>
    </section><section id="flying" data-app-action-sidebar-section data-app-action-sidebar-section-heading="Flying">
      <div id="flying-chat" data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="local:01a202f7" data-app-action-sidebar-thread-kind="local" data-app-action-sidebar-thread-pinned="false">Flying chat</div>
      <div id="flying-project" data-app-action-sidebar-project-row data-app-action-sidebar-project-id="codex:project:d0b14761">Flying project</div>
    </section></aside><main></main>`;
  const storageKey = "codex-tweaks:codex-custom-background:v1";
  const pixel = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==";
  const favorite = { kind: "local", dataUrl: pixel, file: "a".repeat(64) + ".gif" };
  localStorage.setItem(storageKey, JSON.stringify({
    kind: "alcy", finalUrl: "https://t.alcy.cc/pic/pc/first.webp", favorites: [favorite],
  }));
  let requests = 0;
  const flyingThreadKey = "codex:thread:local:01a202f7";
  const flyingProjectKey = "project:d0b14761";
  const preferences = { mode: "all", colors: { "codex:thread:local:sample": "#FF79A9",
    [flyingThreadKey]: "#408A70", [flyingProjectKey]: "#118ACC" }, order: [], recentColors: [],
    presetColors: Array.from({ length: 16 }, (_, i) => "#" + (0x559900 + i).toString(16)) };
  const edits = [];
  const effects = createWindowEffects({
    prismService: {
      on: () => () => {},
      invoke: async (method, { operation } = {}) => {
        if (method === "update") {
          edits.push(operation);
          preferences.colors[operation.key] = operation.value;
        }
        return { account: "test", projects: [], language: "en", preferences,
          threads: [{ id: "pin-one", nativeIndex: 1 }, { id: "pin-two", nativeIndex: 2 }],
          threadProjects: { [flyingThreadKey]: "d0b14761" },
          customSections: [{ id: "flying", name: "Flying", threadKeys: [flyingThreadKey],
            projectKeys: ["codex:project:d0b14761"] }] };
      },
    },
    backgroundService: {
      invoke: async method => {
        if (method === "network.request") {
          requests++;
          return { ok: true, finalUrl: "https://t.alcy.cc/pic/pc/next.webp" };
        }
        if (method === "image.read") throw Error("Fixture has no disk cache");
        throw Error("Unexpected image operation: " + method);
      },
    },
    settingsSections: {
      register(section) {
        let detach;
        return {
          open() { detach = section.mount(document.querySelector("main")); },
          unregister() { detach?.(); },
        };
      },
    },
  });
  const state = window.fixtureState;
  const result = effects.apply(state);
  check(result.mounted.join() === "p-sign,prism,custom-background", JSON.stringify(result));
  await new Promise(resolve => setTimeout(resolve, 100));
  const row = document.querySelector("[data-app-action-sidebar-thread-row]");
  check(row.style.getPropertyValue("--prism-native-color") === "#FF79A9", "Missing native row color");
  const flying = document.querySelector("#flying");
  const flyingChat = document.querySelector("#flying-chat");
  const flyingProject = document.querySelector("#flying-project");
  const tint = target => target.style.getPropertyValue("--prism-native-color");
  const pins = () => [...document.querySelectorAll("[data-prism-native-rank]")].map(pin => pin.getAttribute("data-prism-native-rank")).join(",");
  const pinOrder = pins();
  check(pinOrder === "01,02" && document.querySelector(".prism-tools"), "Pinned rank or toolbar missing");
  check(tint(flyingChat) === "#408A70" && tint(flyingProject) === "#118ACC", "Flying colors missing");
  check(!flyingChat.hasAttribute("data-prism-native-rank"), "Custom row entered Pinned ranking");
  for (const [target, key] of [[flyingChat, flyingThreadKey], [flyingProject, flyingProjectKey]]) {
    target.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));
    const palette = document.querySelector(".prism-dot:not([hidden])");
    check(palette, "No palette on " + key);
    palette.click();
    const firstSwatch = document.querySelector(".prism-swatches button[data-color]");
    check(firstSwatch, "No swatches on " + key);
    firstSwatch.click();
    await new Promise(resolve => setTimeout(resolve, 30));
    check(edits.at(-1)?.key === key && tint(target) === edits.at(-1)?.value, "Color edit not applied to " + key);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  }
  flying.setAttribute("data-app-action-sidebar-section-collapsed", "true");
  window.__prismNativeSidebarV1.refreshNow();
  check(!tint(flyingChat) && !tint(flyingProject) && pins() === pinOrder, "Collapsed Flying affected Pinned");
  flying.removeAttribute("data-app-action-sidebar-section-collapsed");
  window.__prismNativeSidebarV1.refreshNow();
  check(tint(flyingChat) === preferences.colors[flyingThreadKey] &&
    tint(flyingProject) === preferences.colors[flyingProjectKey] && pins() === pinOrder, "Flying did not restore after reopening");
  const wallpaper = document.querySelector("[data-packpier-cbgp-wallpaper]");
  check(!wallpaper.hidden && wallpaper.style.cssText.includes("first.webp"), "Missing wallpaper");
  const sign = document.querySelector(".packpier-p-sign");
  check(getComputedStyle(sign).display !== "none", "P-Sign hidden");
  sign.dispatchEvent(new Event("pointerenter"));
  const [image, settings] = sign.querySelectorAll('[role="toolbar"] button');
  check(!image.closest("[hidden]"), "Hover tray hidden");
  image.click();
  check(requests === 1, "Image button did not request a fresh background");
  settings.click();
  check(document.querySelector("main").textContent.includes("收藏"), "Settings did not open");
  document.querySelector("main .ct-cbgp-history-card").click();
  await new Promise(resolve => setTimeout(resolve, 100));
  check(wallpaper.style.getPropertyValue("--ct-cbgp-bg-image").includes(pixel), "Favorite did not become wallpaper");
  effects.apply(state);
  check(sign === document.querySelector(".packpier-p-sign"), "Unexpected remount");
  const withoutSign = effects.apply({ ...state, packages: state.packages.filter(p => p.id !== "p-sign") });
  check(withoutSign.mounted.join() === "prism,custom-background" && !sign.isConnected, "P-Sign did not stop independently");
  check(row.style.getPropertyValue("--prism-native-color") === "#FF79A9" &&
    !wallpaper.hidden && wallpaper.isConnected, "Stopping P-Sign affected Prism or the wallpaper");
  check(JSON.parse(localStorage.getItem(storageKey)).favorites[0].file === favorite.file, "Stopping P-Sign lost a favorite");
  check(effects.apply(state).mounted.join() === "p-sign,prism,custom-background" &&
    wallpaper.isConnected && document.querySelector(".packpier-p-sign"), "Enabling P-Sign remounted other effects");
  effects.apply({ ...state, enabled: false });
  check(!document.querySelector(".packpier-p-sign,[data-packpier-cbgp-wallpaper],[data-prism-accent]"), "Effects leaked");
  check(JSON.parse(localStorage.getItem(storageKey)).favorites[0].file === favorite.file, "Favorite lost");
  check(effects.apply(state).mounted.length === 3, "Re-enable failed");
  effects.close();
  check(document.querySelectorAll("[data-packpier-plugin]").length === 0, "Plugin elements survived shutdown");
  check(![...document.querySelectorAll("[style]")].some(el => el.style.getPropertyValue("--prism-native-color")),
    "Prism row colors survived shutdown");
  const host = globalThis.__PACKPIER__;
  const navState = { enabled: true, packages: [{id:"p-sign"}, {id:"custom-background"}] };
  const many = Array.from({length: 64}, (_, i) => ({
    kind: "url", url: "https://example.invalid/wallpaper-" + i + ".png", updatedAt: i + 1,
    file: i.toString(16).padStart(64, "0") + ".png",
  }));
  const stored = JSON.parse(localStorage.getItem(storageKey));
  localStorage.setItem(storageKey, JSON.stringify({...stored, favorites: many}));
  const before = getComputedStyle(document.documentElement).position;
  const keys = new Set();
  const add = document.addEventListener;
  const remove = document.removeEventListener;
  document.addEventListener = function(type, fn, options) {
    if (type === "keydown") keys.add(fn);
    return add.call(this, type, fn, options);
  };
  document.removeEventListener = function(type, fn, options) {
    if (type === "keydown") keys.delete(fn);
    return remove.call(this, type, fn, options);
  };
  try {
    for (let i = 0; i < 2; i++) {
      host.apply(navState);
      const sheet = document.querySelector("[data-packpier-settings-overlay]");
      check(sheet?.hidden && getComputedStyle(sheet).display === "none", "Inactive settings sheet intercepted the page");
      const anchor = document.querySelector(".packpier-p-sign");
      anchor.dispatchEvent(new Event("pointerenter"));
      anchor.querySelectorAll('[role="toolbar"] button')[1].click();
      check(!sheet.hidden && getComputedStyle(sheet).display === "grid", "Settings did not open in production sheet");
      check(getComputedStyle(document.documentElement).position === before, "Settings displaced root");
      document.dispatchEvent(new KeyboardEvent("keydown", {key:"Escape"}));
      check(sheet.hidden, "Escape did not close settings");
      const dialog = document.createElement("div");
      dialog.setAttribute("role", "dialog");
      dialog.innerHTML = '<nav><div data-settings-nav-scroll-container><button data-settings-panel-slug="appearance">外观</button><button data-settings-panel-slug="voice">语音</button></div></nav><div data-settings-panel><div>Native page</div></div>';
      const delayed = dialog.querySelector('[data-settings-panel-slug="appearance"]');
      delayed.removeAttribute("data-settings-panel-slug");
      document.body.append(dialog);
      await Promise.resolve();
      delayed.dataset.settingsPanelSlug = "appearance";
      await Promise.resolve();
      const appearance = dialog.querySelector('[data-settings-panel-slug="appearance"]');
      const item = appearance.nextElementSibling;
      const native = dialog.querySelector("[data-settings-panel]").firstElementChild;
      check(item.matches("[data-packpier-background-nav]") && item.textContent === "自定义背景", "Missing App settings entry");
      item.click();
      const firstPaintTiles = dialog.querySelectorAll('[data-slot="favorites-grid"] .ct-cbgp-tile').length;
      check(firstPaintTiles > 0 && firstPaintTiles <= 8, "Thumbnail work blocked first paint: " + firstPaintTiles);
      check(native.parentNode.querySelector("[data-packpier-background-pane]")?.textContent.includes("收藏"), "Missing embedded background pane");
      check(sheet.hidden && getComputedStyle(native).display === "none", "Incorrect pane layering");
      dialog.querySelector('[data-settings-panel-slug="voice"]').click();
      check(getComputedStyle(native).display !== "none" && !dialog.querySelector("[data-packpier-background-pane]"), "Native tab did not recover");
      appearance.after(appearance.cloneNode(true));
      appearance.remove();
      await Promise.resolve();
      check(dialog.querySelectorAll("[data-packpier-background-nav]").length === 1, "Duplicate nav item after rerender");
      item.click();
      dialog.remove();
      await Promise.resolve();
      check(!dialog.querySelector("[data-packpier-background-pane]"), "Detached settings pane leaked");
      host.close();
      check(!sheet.isConnected && keys.size === 0, "Settings node or keyboard listener leaked");
    }
  } finally {
    document.addEventListener = add;
    document.removeEventListener = remove;
  }
}
run().then(() => document.body.textContent = "PACKPIER_EFFECTS_PASS").catch(error => {
  document.body.textContent = "PACKPIER_EFFECTS_FAIL " + error.stack;
});
