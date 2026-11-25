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
  localStorage.setItem(storageKey, JSON.stringify({ kind: "transparent", frostEnabled: true }));
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

  const scroll = () => {
    timeline.dispatchEvent(new Event("scroll"));
    renderFrame();
  };
  const surface = fixture.querySelector("#window-fixture");
  const frost = document.querySelector("[data-packpier-cbgp-window-frost]");
  transcript.style.height = "12000px";
  timeline.scrollTop = 6500;
  for (const zoom of [1.25, 0.8]) {
    fixture.style.zoom = String(zoom);
    window.dispatchEvent(new Event("resize"));
    await new Promise(resolve => setTimeout(resolve, 110));
    scroll();
    check(Math.abs(transcript.currentCSSZoom - zoom) < 0.01, "Transcript must inherit the fixture zoom");
    const x = timeline.getBoundingClientRect().left + 16;
    const visibleAt = y => document.elementsFromPoint(x, y).includes(transcript);
    const topEdge = topFade.getBoundingClientRect().bottom;
    const bottomEdge = footerFade.getBoundingClientRect().top;
    check(!visibleAt(topEdge - 3) && visibleAt(topEdge + 3) &&
      visibleAt(bottomEdge - 3) && !visibleAt(bottomEdge + 3),
      `Transcript clip missed viewport boundaries at zoom ${zoom}: ${getComputedStyle(transcript).clipPath}`);

    const { left, top, right, bottom } = surface.getBoundingClientRect();
    const polygon = [...frost.style.clipPath.matchAll(/(-?[\d.]+)px/g)].map(match => Number(match[1]));
    check(frost.parentElement === document.body && frost.currentCSSZoom === 1 &&
      [left, top, right, top, right, bottom, left, bottom].every((value, i) =>
        Math.abs(polygon[i + 10] - value) < 0.01), "The frost cutout did not follow the zoomed surface");
  }
  fixture.style.removeProperty("zoom");
  for (const height of [204, 220]) {
    footerFade.style.height = `${height}px`;
    scroll();
    check(getComputedStyle(transcript).clipPath === "none" && transcriptAt(110),
      "Equal or inverted boundaries hid the transcript instead of clearing the clip");
  }
  footerFade.style.height = "96px";
  scroll();
  check(transcriptAt(110) && !transcriptAt(160), "Clipping did not recover when the boundaries became valid");
  transcript.style.removeProperty("height");
  timeline.scrollTop = 160;
  scroll();

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

function checkHistoryMenuZoom(dialog) {
  const card = dialog.querySelector('[data-slot="favorites-grid"] .ct-cbgp-history-card');
  for (const zoom of [1.25, 0.8]) {
    dialog.style.zoom = String(zoom);
    const dispatchMenu = event => {
      card.dispatchEvent(event);
      const menu = dialog.querySelector("[data-packpier-cbgp-context-menu]");
      check(menu?.matches(":popover-open") && Math.abs(menu.currentCSSZoom - zoom) < 0.01,
        "The history popover must stay inside the zoomed settings pane");
      return menu.getBoundingClientRect();
    };
    const close = () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    const near = (actual, target) => Math.abs(actual - target) < 1;
    const point = dispatchMenu(new MouseEvent("contextmenu", { clientX: 200, clientY: 140 }));
    check(near(point.left, 200) && near(point.top, 140), "History menu missed its pointer anchor at zoom " + zoom);
    close();
    const edge = dispatchMenu(new MouseEvent("contextmenu", { clientX: innerWidth - 1, clientY: innerHeight - 1 }));
    check(near(edge.right, innerWidth - 8) && near(edge.bottom, innerHeight - 8),
      "History menu exceeded viewport edges at zoom " + zoom);
    close();
    const button = card.getBoundingClientRect();
    const keyboard = dispatchMenu(new KeyboardEvent("keydown", { key: "F10", shiftKey: true }));
    const clamp = (position, limit) => Math.max(8, Math.min(position, limit - 8));
    check(near(keyboard.left, clamp(button.left + 12, innerWidth - keyboard.width)) &&
      near(keyboard.top, clamp(button.bottom + 4, innerHeight - keyboard.height)),
      "History menu missed its keyboard anchor at zoom " + zoom);
    close();
  }
  dialog.style.removeProperty("zoom");
}

function nativeRailRects(rail) {
  return JSON.stringify([...rail.querySelectorAll("button")].map(button => button.getBoundingClientRect().toJSON()));
}

async function checkPSignUpdateButton(rail, sign, originalRects) {
  const usage = rail.querySelector("button");
  const update = document.createElement("span");
  update.innerHTML = '<button type="button">Update available</button>';
  check(getComputedStyle(sign).transform === "none", "Legacy P-Sign transform changed the anchor position");
  const settle = () => new Promise(resolve => setTimeout(resolve, 0));

  function checkTargets(first, gap = 8) {
    const anchor = sign.querySelector(".pp-sign-anchor");
    const mark = sign.getBoundingClientRect();
    const native = first.getBoundingClientRect();
    check(mark.width === 36 && mark.height === 36 && mark.left === native.left &&
      native.top - mark.bottom === gap, "P-Sign did not follow the top visible native layout item");
    for (const button of [anchor, ...rail.querySelectorAll("button")]) {
      if (!button.getClientRects().length) continue;
      const rect = button.getBoundingClientRect();
      const name = button.getAttribute("aria-label") || button.textContent;
      check(button.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2)),
        name + " does not receive pointer input at its center");
    }
  }
  check(nativeRailRects(rail) === originalRects, "Mounting P-Sign moved native navigation buttons");
  checkTargets(usage);
  const initialTop = sign.getBoundingClientRect().top;
  usage.before(update);
  const withUpdate = nativeRailRects(rail);
  await settle();
  checkTargets(update.firstElementChild);
  check(sign.getBoundingClientRect().top === initialTop - 44, "P-Sign did not move up one native row");
  check(nativeRailRects(rail) === withUpdate, "Following the update button changed native button coordinates");

  const updateButton = update.firstElementChild;
  const icon = updateButton.firstChild;
  const updateTop = updateButton.getBoundingClientRect().top;
  const spinner = document.createElement("div");
  spinner.setAttribute("role", "progressbar");
  spinner.style.cssText = "width:36px;height:36px";
  icon.replaceWith(spinner);
  updateButton.disabled = true;
  updateButton.setAttribute("aria-hidden", "true");
  updateButton.style.opacity = "0";
  update.dataset.state = "loading";
  await settle();
  checkTargets(update);
  check(spinner.getBoundingClientRect().top - sign.getBoundingClientRect().bottom === 8,
    "The progressbar inside the faded update button lost its 8px gap");
  check(nativeRailRects(rail) === withUpdate, "An icon-to-spinner swap displaced native navigation buttons");

  const wrapper = document.createElement("div");
  wrapper.style.display = "contents";
  const busy = document.createElement("div");
  busy.setAttribute("aria-busy", "true");
  busy.dataset.state = "loading";
  busy.style.cssText = "width:36px;height:36px";
  busy.append(spinner);
  wrapper.append(busy);
  const remainingRects = JSON.stringify(JSON.parse(withUpdate).slice(1));
  update.replaceWith(wrapper);
  await settle();
  checkTargets(busy);
  check(busy.getBoundingClientRect().top === updateTop && nativeRailRects(rail) === remainingRects,
    "The busy wrapper or native navigation buttons moved during loading");

  wrapper.replaceWith(update);
  updateButton.append(icon);
  updateButton.disabled = false;
  updateButton.removeAttribute("aria-hidden");
  updateButton.style.removeProperty("opacity");
  delete update.dataset.state;
  await settle();
  checkTargets(updateButton);
  check(nativeRailRects(rail) === withUpdate, "Restoring the update icon displaced native navigation buttons");

  update.style.display = "none";
  await settle();
  checkTargets(usage);
  update.remove();
  await settle();
  checkTargets(usage);
  check(sign.getBoundingClientRect().top === initialTop && nativeRailRects(rail) === originalRects,
    "Removing the update button did not restore the original geometry");

  rail.style.top = "40px";
  rail.style.bottom = "auto";
  await settle();
  checkTargets(usage, 4);
  check(sign.getBoundingClientRect().top === 0, "P-Sign went outside the viewport when its gap was constrained");
  rail.style.top = "24px";
  await settle();
  check(sign.hidden, "P-Sign covered a native button when there was no room for the icon");
  rail.style.removeProperty("top");
  rail.style.removeProperty("bottom");
  await settle();
  checkTargets(usage);
}

function checkPalettePlacement() {
  const fixture = document.createElement("section");
  fixture.setAttribute("data-app-action-sidebar-section", "");
  fixture.setAttribute("data-app-action-sidebar-section-heading", "Placement fixture");
  fixture.innerHTML = `
    <style>
      .placement-row {width:240px;border:solid transparent;border-width:3px 4px 1px 2px;box-sizing:border-box;white-space:nowrap}
      .placement-title {display:block;width:100%;padding:3px 0;border:0;text-align:start}
      .placement-actions {display:flex;gap:5px;position:absolute;inset-inline-end:8px;top:3px}
      .placement-actions button {width:20px;height:20px;padding:0}
      .placement-ignored {position:absolute;inset-inline-start:65px;top:2px;width:20px;height:20px}
      .placement-fixed {display:block;height:36px;text-align:start}
    </style>
    <div class="placement-row" data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="placement">
      <div data-thread-title-trigger><button class="placement-title" data-interactive-row-button><span data-thread-title>Chat</span></button></div>
      <div class="placement-actions">
        <button data-interactive-row-button aria-label="Archive"></button>
        <button aria-label="More actions"></button>
      </div>
      <button class="placement-ignored sr-only" aria-label="Keyboard action"></button>
      <button class="placement-ignored" style="visibility:hidden" aria-label="Hidden action"></button>
    </div>
    <button class="placement-row placement-fixed" data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="placement-fixed">
      <span data-thread-title>Chat</span>
    </button>`;
  document.querySelector("[data-sidebar-navigation-root]").append(fixture);
  window.__prismNativeSidebarV1.refreshNow();
  const row = fixture.querySelector("div.placement-row");
  const fixedRow = fixture.querySelector(".placement-fixed");
  const title = row.querySelector("[data-thread-title]");
  const actions = row.querySelector(".placement-actions");
  const hover = (target = row) => {
    target.querySelector("[data-thread-title]").dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));
    return document.querySelector(".prism-dot");
  };
  function checkBounds(target, dot, rtl, dotZoom) {
    const box = dot.getBoundingClientRect();
    const bounds = target.getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(target.querySelector("[data-thread-title]"));
    const text = range.getBoundingClientRect();
    check(!dot.hidden && Math.abs(box.width - 22 * dotZoom) < 0.1 && box.left >= bounds.left && box.right <= bounds.right &&
      box.top >= bounds.top && box.bottom <= bounds.bottom, "Prism dot escaped its row");
    check(Math.abs((box.top + box.bottom) / 2 - (bounds.top + bounds.bottom) / 2) < 0.1,
      "Prism dot was not vertically centered at zoom " + target.currentCSSZoom);
    check(rtl ? box.right <= text.left : box.left >= text.right, "Prism dot overlaps the visible title text");
    return box;
  }
  function checkActions(dot, rtl = false, zoom = 1) {
    check(dot.parentElement === row, "Expected a nested dot");
    const box = checkBounds(row, dot, rtl, zoom);
    const native = actions.getBoundingClientRect();
    const gap = rtl ? box.left - native.right : native.left - box.right;
    check(gap >= 6 * zoom - 0.1 && gap < 6 * zoom + 1.1,
      "Prism dot spacing from native actions was wrong at zoom " + zoom);
  }
  function checkTrailingGap(target, box, rtl, zoom) {
    const bounds = target.getBoundingClientRect();
    const gap = rtl ? box.left - bounds.left : bounds.right - box.right;
    check(gap >= 30 * zoom - 0.1 && gap < 30 * zoom + 1.1,
      "An action-free row did not keep its trailing clearance at zoom " + zoom);
  }
  for (const zoom of [1.25, 0.8]) {
    fixture.style.zoom = String(zoom);
    for (const direction of ["ltr", "rtl"]) {
      const rtl = direction === "rtl";
      row.dir = fixedRow.dir = direction;
      checkActions(hover(), rtl, zoom);
      actions.hidden = true;
      actions.style.display = "none";
      checkTrailingGap(row, checkBounds(row, hover(), rtl, zoom), rtl, zoom);
      actions.hidden = false;
      actions.style.removeProperty("display");
      const fixedDot = hover(fixedRow);
      check(!fixedRow.contains(fixedDot) && getComputedStyle(fixedDot).position === "fixed", "Expected a body-portal dot");
      checkTrailingGap(fixedRow, checkBounds(fixedRow, fixedDot, rtl, 1), rtl, zoom);
    }
    const dot = hover(fixedRow);
    const anchor = dot.getBoundingClientRect();
    dot.click();
    const panel = document.querySelector('.prism-pop:not([hidden])[role="dialog"]');
    const picker = panel.getBoundingClientRect();
    const expectedTop = anchor.bottom + 5 + picker.height <= innerHeight - 5
      ? anchor.bottom + 5 : Math.max(5, anchor.top - 5 - picker.height);
    check(panel.currentCSSZoom === 1 && picker.left >= 5 && picker.right <= innerWidth - 5 &&
      Math.abs(picker.top - expectedTop) < 1, "Picker escaped the viewport or missed its zoomed row anchor");
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  }
  fixture.style.removeProperty("zoom");
  row.dir = "ltr";
  checkActions(hover());
  row.dir = "rtl";
  checkActions(hover(), true);
  row.dir = "ltr";
  row.style.width = "120px";
  checkActions(hover());
  actions.hidden = true;
  actions.style.display = "none";
  checkTrailingGap(row, checkBounds(row, hover(), false, 1), false, 1);
  row.style.width = "92px";
  title.textContent = "A long title";
  const narrowDot = hover();
  check(narrowDot.hidden && !narrowDot.getClientRects().length, "The dot should yield to text when it cannot fit");
  title.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", altKey: true, bubbles: true }));
  check(document.querySelector('.prism-pop:not([hidden])[role="dialog"]'), "The narrow row lost keyboard access to the color picker");
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  fixture.remove();
}

async function run() {
  document.documentElement.lang = "zh-CN";
  const pinnedClient = "client-new-thread:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const fallbackClient = "client-new-thread:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const flyingClient = "client-new-thread:cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  document.body.innerHTML = `<style>
      [data-app-action-sidebar-thread-row],[data-app-action-sidebar-project-row] { min-height: 26px; }
      nav[data-app-navigation-rail] { position: fixed; left: 8px; bottom: 4px; width: 36px; }
      aside[data-sidebar-navigation-root] { margin-left: 52px; }
      .rail-stack { display: flex; flex-direction: column; gap: 8px; }
      .rail-stack button { display: grid; place-items: center; width: 36px; height: 36px; padding: 0; border: 0; }
      .rail-stack span { display: inline-flex; }
    </style>
    <nav data-app-navigation-rail><div><div class="rail-stack">
      <div class="rail-stack"><button aria-haspopup="menu">Usage</button></div>
      <div><button aria-haspopup="menu">Profile</button></div>
    </div></div></nav>
    <aside data-sidebar-navigation-root><section data-app-action-sidebar-section data-app-action-sidebar-section-heading="Recents">
      <div data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="sample" data-app-action-sidebar-thread-kind="local">Sample chat</div>
    </section><section data-app-action-sidebar-section data-app-action-sidebar-section-heading="Pinned">
      <h2>Pinned</h2><div role="list">
        <div role="listitem"><div id="mapped-pin" data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="local:${pinnedClient}" data-app-action-sidebar-thread-kind="local" data-app-action-sidebar-thread-pinned="true">First pin</div></div>
        <div role="listitem"><div id="unmapped-pin" data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="local:${fallbackClient}" data-app-action-sidebar-thread-kind="local" data-app-action-sidebar-thread-pinned="true">Second pin</div></div>
      </div>
    </section><section id="flying" data-app-action-sidebar-section data-app-action-sidebar-section-heading="Flying">
      <div id="flying-chat" data-app-action-sidebar-thread-row data-app-action-sidebar-thread-id="local:${flyingClient}" data-app-action-sidebar-thread-kind="local" data-app-action-sidebar-thread-pinned="false">Flying chat</div>
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
  const pinnedKey = "codex:thread:local:pin-one";
  const fallbackKey = "codex:thread:local:" + fallbackClient;
  const lateClient = "client-new-thread:dddddddd-dddd-4ddd-8ddd-dddddddddddd";
  const unresolvedClient = "client-new-thread:eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
  const lateKey = "codex:thread:local:pin-late";
  const noDatabaseKey = "codex:thread:local:pin-no-db";
  const unresolvedKey = "codex:thread:local:" + unresolvedClient;
  const preferences = { mode: "project", colors: { "codex:thread:local:sample": "#FF79A9",
    [pinnedKey]: "#5E5EFF", [fallbackKey]: "#A86422", [flyingProjectKey]: "#118ACC",
    "project:beak-id": "#39856D", [unresolvedKey]: "#8844BB" },
    threadColorModes: { [flyingThreadKey]: "project" }, order: [], recentColors: [],
    presetColors: Array.from({ length: 16 }, (_, i) => "#" + (0x559900 + i).toString(16)) };
  const threads = [{ id: "pin-one", projectId: "beak-id", nativeIndex: 1 },
    { id: fallbackClient, projectId: "field-notes", nativeIndex: 2 },
    { id: "pin-no-db", projectId: null, nativeIndex: 3, pending: true }];
  const clientBindings = { [pinnedClient]: "pin-one", ["local:" + flyingClient]: "01a202f7" };
  const threadProjects = { [pinnedKey]: "beak-id", [flyingThreadKey]: "d0b14761" };
  let snapshotReads = 0;
  const edits = [];
  const addSheet = (css) => {
    const sheet = document.createElement("style");
    sheet.textContent = css;
    document.head.append(sheet);
    return sheet;
  };
  const legacySheets = [
    addSheet("@supports (position-anchor: --packpier-profile) { .packpier-p-sign { position-anchor: --packpier-profile; transform: translate(-50%, -50%); } }"),
    addSheet(".prism-tools { visibility: hidden; }"),
    addSheet("[data-packpier-cbgp-wallpaper] { visibility: hidden; }"),
  ];
  const nativeSheet = addSheet('/* .prism- is only mentioned in a comment */ aside { --fixture-label: ".packpier-p-sign"; }');
  const effects = createWindowEffects({
    prismService: {
      on: () => () => {},
      invoke: async (method, { operation } = {}) => {
        if (method === "update") {
          edits.push(operation);
          preferences.colors[operation.key] = operation.value;
        } else if (method === "snapshot") snapshotReads++;
        return { account: "test", projects: [{ id: "beak-id", name: "beak" }, { id: "field-notes", name: "Field Notes" }],
          language: "en", preferences, threads, clientBindings, threadProjects,
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
  check(legacySheets.every(sheet => !sheet.isConnected) && nativeSheet.isConnected,
    "Runtime startup should remove only identifiable legacy plugin styles");
  const markedOrphan = addSheet(".packpier-p-sign { transform: translate(-50%, -50%); }");
  markedOrphan.dataset.packpierStyle = "p-sign";
  const state = window.fixtureState;
  const rail = document.querySelector("nav[data-app-navigation-rail]");
  const originalRailRects = nativeRailRects(rail);
  const result = effects.apply(state);
  check(result.mounted.join() === "p-sign,prism,custom-background", JSON.stringify(result));
  check(!markedOrphan.isConnected && document.querySelectorAll('style[data-packpier-style="p-sign"]').length === 1,
    "P-Sign mount did not replace the previously marked style");
  await new Promise(resolve => setTimeout(resolve, 100));
  check(document.querySelectorAll('style[data-packpier-style="prism"]').length === 2 &&
    document.querySelectorAll('style[data-packpier-style="custom-background"]').length === 1, "A plugin style is missing its ID");
  const row = document.querySelector("[data-app-action-sidebar-thread-row]");
  check(row.style.getPropertyValue("--prism-native-color") === "#FF79A9", "Missing native row color");
  const flying = document.querySelector("#flying");
  const flyingChat = document.querySelector("#flying-chat");
  const flyingProject = document.querySelector("#flying-project");
  const tint = target => target.style.getPropertyValue("--prism-native-color");
  const pins = () => [...document.querySelectorAll("[data-prism-native-rank]")].map(pin => pin.getAttribute("data-prism-native-rank")).join(",");
  const pinOrder = pins();
  check(pinOrder === "01,02" && document.querySelector(".prism-tools"), "Pinned rank or toolbar missing");
  const mappedPin = document.querySelector("#mapped-pin");
  const unmappedPin = document.querySelector("#unmapped-pin");
  const beak = document.querySelector('[data-prism-group-project="beak-id"]');
  const orderOf = row => Number(row.closest("[role=listitem]").style.getPropertyValue("--prism-order"));
  check(beak?.textContent === "beak1" && orderOf(mappedPin) === Number(beak.style.order) + 3,
    "Mapped pinned row did not join beak");
  check(unmappedPin.style.getPropertyValue("--prism-native-color") === "#A86422" &&
    orderOf(unmappedPin) > orderOf(mappedPin) && !unmappedPin.hasAttribute("data-prism-native-filtered"),
    "Unmapped pinned row did not keep fallback behavior");
  check(tint(mappedPin) === "#5E5EFF", "Real pinned key did not pick up the saved color");
  check(tint(flyingChat) === "#118ACC" && tint(flyingProject) === "#118ACC", "Flying inheritance missing");
  check(!flyingChat.hasAttribute("data-prism-native-rank"), "Custom row entered Pinned ranking");
  function openPalette(target) {
    target.dispatchEvent(new PointerEvent("pointerover", { bubbles: true }));
    const palette = document.querySelector(".prism-dot:not([hidden])");
    check(palette, "No palette on " + target.textContent);
    palette.click();
    const panel = document.querySelector(".prism-pop:not([hidden])");
    check(panel, "Palette did not open");
    return panel;
  }
  const swatch = (panel) => panel.querySelector(".prism-swatches button[data-color]");
  for (const [target, key] of [[mappedPin, pinnedKey], [flyingChat, flyingThreadKey], [flyingProject, flyingProjectKey]]) {
    const firstSwatch = swatch(openPalette(target));
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

  const list = mappedPin.closest("[role=list]");
  const addPin = (id) => {
    const item = document.createElement("div");
    item.setAttribute("role", "listitem");
    const pin = document.createElement("div");
    pin.setAttribute("data-app-action-sidebar-thread-row", "");
    pin.setAttribute("data-app-action-sidebar-thread-id", "local:" + id);
    pin.setAttribute("data-app-action-sidebar-thread-kind", "local");
    pin.setAttribute("data-app-action-sidebar-thread-pinned", "true");
    pin.textContent = "New pin";
    item.append(pin);
    return item;
  };
  const late = addPin(lateClient);
  const unresolved = addPin(unresolvedClient);
  const noDatabaseRow = addPin("pin-no-db");
  list.insertBefore(late, unmappedPin.parentElement);
  list.insertBefore(unresolved, unmappedPin.parentElement);
  list.insertBefore(noDatabaseRow, unmappedPin.parentElement);
  const stillNative = (item) => item.parentElement === list && !item.hasAttribute("data-prism-item") &&
    !item.style.getPropertyValue("--prism-order") && !item.firstElementChild.hasAttribute("data-prism-native-rank") &&
    !tint(item.firstElementChild);
  const placements = new Set();
  let sawUngrouped = false;
  const observer = new MutationObserver(() => {
    sawUngrouped ||= [...list.querySelectorAll(".prism-group-toggle span")]
      .some(title => ["No project", "未归属项目"].includes(title.textContent));
    if (late.hasAttribute("data-prism-item")) placements.add(late.style.getPropertyValue("--prism-order"));
  });
  observer.observe(list, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "data-prism-item"] });
  const beforePinReads = snapshotReads;
  window.__prismNativeSidebarV1.refreshNow();
  check(stillNative(late) && stillNative(unresolved) && stillNative(noDatabaseRow) && late.nextElementSibling === unresolved &&
    unresolved.nextElementSibling === noDatabaseRow && noDatabaseRow.nextElementSibling === unmappedPin.parentElement &&
    beak.textContent === "beak1", "A pending pin left its native position");
  const pendingEdits = edits.length;
  const waitingPanel = openPalette(late.firstElementChild);
  swatch(waitingPanel).click();
  check(edits.length === pendingEdits && !waitingPanel.hidden &&
    document.querySelector(".prism-error:not([hidden])")?.textContent === "Chat is syncing. Try again in a moment.",
    "Unbound pin should keep its palette open and show the syncing notice without an update");
  await new Promise(resolve => setTimeout(resolve, 340));
  check(snapshotReads === beforePinReads + 1 && stillNative(late) && stillNative(unresolved) && !sawUngrouped,
    "The first stale snapshot moved a pending pin");
  check(edits.length === pendingEdits, "An unbound pin sent an asynchronous update");
  clientBindings[lateClient] = "pin-late";
  threads.push({ id: "pin-late", projectId: "beak-id", nativeIndex: 2, pending: true },
    { id: unresolvedClient, projectId: null, nativeIndex: 4, pending: true });
  threads[1].nativeIndex = 3;
  threads[2].nativeIndex = 5;
  preferences.threadColorModes[lateKey] = "project";
  await new Promise(resolve => setTimeout(resolve, 470));
  observer.disconnect();
  check(snapshotReads === beforePinReads + 2 && !sawUngrouped && stillNative(unresolved) && placements.size === 1 &&
    [...placements][0] === String(Number(beak.style.order) + 6) && beak.textContent === "beak2",
    "A delayed binding did not join beak once or an unresolved pin left its native position");
  check(late.firstElementChild.getAttribute("data-prism-native-rank") === "02" &&
    tint(late.firstElementChild) === "#39856D" && pins() === "01,02,03", "Resolved pin rank or inherited color is wrong");
  check(!waitingPanel.hidden, "Syncing closed the open color picker");
  swatch(waitingPanel).click();
  await new Promise(resolve => setTimeout(resolve, 30));
  check(edits.length === pendingEdits + 1 && edits.at(-1)?.key === lateKey && tint(late.firstElementChild) === edits.at(-1)?.value,
    "Retrying from an open picker must use the newly bound ID");
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  swatch(openPalette(noDatabaseRow.firstElementChild)).click();
  await new Promise(resolve => setTimeout(resolve, 30));
  check(edits.at(-1)?.key === noDatabaseKey && tint(noDatabaseRow.firstElementChild) === edits.at(-1)?.value &&
    !noDatabaseRow.hasAttribute("data-prism-item") && pins() === "01,02,03", "A real pin without a database row could not change color in place");
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
  checkPalettePlacement();

  const wallpaper = document.querySelector("[data-packpier-cbgp-wallpaper]");
  check(!wallpaper.hidden && wallpaper.style.cssText.includes("first.webp"), "Missing wallpaper");
  const sign = document.querySelector(".packpier-p-sign");
  check(getComputedStyle(sign).display !== "none", "P-Sign hidden");
  await checkPSignUpdateButton(rail, sign, originalRailRects);
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
  const nativeRectsBeforeStop = nativeRailRects(rail);
  const withoutSign = effects.apply({ ...state, packages: state.packages.filter(p => p.id !== "p-sign") });
  check(withoutSign.mounted.join() === "prism,custom-background" && !sign.isConnected, "P-Sign did not stop independently");
  check(!document.querySelector('style[data-packpier-style="p-sign"]'), "Disabling P-Sign left its style mounted");
  check(nativeRailRects(rail) === nativeRectsBeforeStop, "Stopping P-Sign changed native button coordinates");
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
  check(!document.querySelector("style[data-packpier-style]") && nativeSheet.isConnected,
    "Shutdown must remove current plugin styles and keep native styles");
  nativeSheet.remove();
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
      if (i === 0) checkHistoryMenuZoom(dialog);
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
