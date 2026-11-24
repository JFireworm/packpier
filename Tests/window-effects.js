// Runs in a fresh browser profile against the built renderer and a synthetic Codex document.
import "packpier-test-host";
import { createWindowEffects } from "packpier-test-effects";

function check(value, detail) {
  if (!value) throw Error(detail);
}

async function checkTransparentWindow(effects, storageKey) {
  const fixture = document.createElement("div");
  fixture.innerHTML = `<style>
      #window-fixture { position: fixed; top: 16px; left: 16px; width: 320px; z-index: 100; }
      #timeline { height: 240px; overflow-y: auto; }
      #transcript { height: 720px; background: blue; }
      #top-fade, #footer-fade::before { background-image: linear-gradient(transparent, white); }
      #top-fade, #footer-fade { position: absolute; left: 0; right: 0; pointer-events: none; z-index: 2; }
      #top-fade { top: 0; height: 36px; }
      #footer-fade { bottom: 0; height: 52px; }
      #composer { position: absolute; right: 10px; bottom: 8px; pointer-events: auto; }
      #footer-fade::before, #footer-fade::after { content: ""; }
      #footer-fade::after, #composer, #dialog { background-color: white; }
    </style>
    <div class="macos-window-backdrop" style="opacity: 0"></div>
    <section id="window-fixture" data-app-shell-main-surface="default">
      <div id="top-fade" aria-hidden="true" class="pointer-events-none bg-[image:var(--app-shell-content-fade,linear-gradient(to_bottom,currentColor,transparent))]"></div>
      <div id="timeline" data-app-action-timeline-scroll>
        <div id="transcript" class="[container-name:thread-content]">Chat content</div>
        <div id="footer-fade" class="pointer-events-none absolute">
          <div data-thread-scroll-footer="true">
            <div data-thread-composer-backdrop><textarea id="composer" data-composer-body></textarea></div>
          </div>
        </div>
      </div>
      <div id="dialog" role="dialog" class="bg-surface"></div>
    </section>`;
  document.body.append(fixture);
  const backdrop = fixture.querySelector(".macos-window-backdrop");
  const topFade = fixture.querySelector("#top-fade");
  const footerFade = fixture.querySelector("#footer-fade");
  const paint = () => ({
    backdrop: getComputedStyle(backdrop).opacity,
    topFade: getComputedStyle(topFade).backgroundImage,
    footerFade: getComputedStyle(footerFade, "::before").backgroundImage,
    footerFill: getComputedStyle(footerFade, "::after").backgroundColor,
  });
  const timeline = fixture.querySelector("#timeline");
  const transcript = fixture.querySelector("#transcript");
  const subscriptions = new Set();
  const add = timeline.addEventListener.bind(timeline);
  const remove = timeline.removeEventListener.bind(timeline);
  timeline.addEventListener = (type, callback, options) => {
    if (type === "scroll") subscriptions.add(callback);
    add(type, callback, options);
  };
  timeline.removeEventListener = (type, callback, options) => {
    if (type === "scroll") subscriptions.delete(callback);
    remove(type, callback, options);
  };

  const NativeResizeObserver = window.ResizeObserver;
  const observed = new Set();
  window.ResizeObserver = class extends NativeResizeObserver {
    observe(target) {
      if (target === transcript) observed.add(this);
      super.observe(target);
    }
    disconnect() {
      observed.delete(this);
      super.disconnect();
    }
  };
  const requestFrame = window.requestAnimationFrame;
  const cancelFrame = window.cancelAnimationFrame;
  const frames = new Map();
  let frameId = 0;
  // Drive frames explicitly because headless Chromium uses virtual time.
  window.requestAnimationFrame = callback => {
    frames.set(++frameId, callback);
    return frameId;
  };
  window.cancelAnimationFrame = id => frames.delete(id);
  function renderFrame() {
    const callbacks = [...frames.values()];
    frames.clear();
    for (const callback of callbacks) callback(performance.now());
  }

  const nativePaint = paint();
  const previous = localStorage.getItem(storageKey);
  localStorage.setItem(storageKey, JSON.stringify({ kind: "transparent" }));
  const state = { enabled: true, packages: [{ id: "custom-background" }] };
  effects.apply(state);
  check(document.documentElement.hasAttribute("data-packpier-cbgp-transparent"), "Transparent mode did not mount");
  for (const opacity of ["1", "0"]) {
    backdrop.style.opacity = opacity;
    const actual = paint();
    check(actual.backdrop === "0" && actual.topFade === "none" && actual.footerFade === "none" &&
      actual.footerFill === "rgba(0, 0, 0, 0)", `Native decorations are visible at backdrop opacity ${opacity}: ${JSON.stringify(actual)}`);
  }
  for (const selector of ["#composer", "#dialog"]) {
    check(getComputedStyle(fixture.querySelector(selector)).backgroundColor === "rgb(255, 255, 255)",
      `Background override affected ${selector}`);
  }

  check(subscriptions.size === 1 && observed.size === 1, "Missing clipping subscriptions");
  const { left, top } = timeline.getBoundingClientRect();
  const transcriptAt = y => document.elementsFromPoint(left + 16, top + y).includes(transcript);
  const measure = transcript.getBoundingClientRect.bind(transcript);
  let reads = 0;
  transcript.getBoundingClientRect = () => {
    reads++;
    return measure();
  };
  timeline.scrollTop = 160;
  for (let i = 0; i < 5; i++) timeline.dispatchEvent(new Event("scroll"));
  check(reads === 0, "Scroll measured layout before the animation frame");
  renderFrame();
  check(reads === 1, "Scroll did not coalesce to one layout measurement");
  const visible = [18, 110, 222].map(transcriptAt);
  check(!visible[0] && visible[1] && !visible[2],
    `Unexpected scroll boundary at ${timeline.scrollTop}: ${visible.join(", ")} (${getComputedStyle(transcript).clipPath})`);
  footerFade.style.height = "96px";
  window.dispatchEvent(new Event("resize"));
  await new Promise(resolve => setTimeout(resolve, 120));
  renderFrame();
  check(transcriptAt(110) && !transcriptAt(160), "Growing the composer did not update the transcript boundary");
  const composer = fixture.querySelector("#composer");
  const composerBox = composer.getBoundingClientRect();
  check(document.elementFromPoint(composerBox.x + 8, composerBox.y + 8) === composer,
    "Clipping the transcript affected interaction with the composer");

  const marker = "data-packpier-cbgp-transcript-clip";
  const clearClip = () => !transcript.hasAttribute(marker) &&
    !transcript.style.getPropertyValue("--ct-cbgp-transcript-clip") &&
    getComputedStyle(transcript).clipPath === "none" && !subscriptions.size && !observed.size;

  topFade.remove();
  await new Promise(resolve => setTimeout(resolve, 120));
  check(clearClip(), "Unrecognized Codex layout did not fall back to native scrolling");
  timeline.before(topFade);
  await new Promise(resolve => setTimeout(resolve, 120));
  check(transcript.hasAttribute(marker) && subscriptions.size === 1 && observed.size === 1, "Clipping did not recover");

  const stopEffect = [
    () => effects.apply({ ...state, enabled: false }),
    () => effects.close(),
  ];
  for (const stop of stopEffect) {
    effects.apply(state);
    renderFrame();
    const beforeScroll = reads;
    timeline.dispatchEvent(new Event("scroll"));
    check(frames.size === 1, "Scroll did not queue a clipping frame");
    stop();
    check(clearClip() && frames.size === 0, "Clipping attributes or subscriptions survived teardown");
    renderFrame();
    check(reads === beforeScroll, "A clipping update ran after teardown");
    backdrop.style.opacity = "0";
    check(JSON.stringify(paint()) === JSON.stringify(nativePaint), "Teardown did not restore native decorations");
    check(transcriptAt(18) && transcriptAt(222), "Teardown did not restore native scrolling");
  }
  window.ResizeObserver = NativeResizeObserver;
  window.requestAnimationFrame = requestFrame;
  window.cancelAnimationFrame = cancelFrame;
  localStorage.setItem(storageKey, previous);
  fixture.remove();
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
  await checkTransparentWindow(effects, storageKey);
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
