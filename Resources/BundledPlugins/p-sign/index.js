import "./style.css";
import { changedEvent, hoverActions } from "./hover-actions.js";

const labels = {
  zh: ["插件快捷操作", "随机换一张", "打开自定义背景设置", "请先启用自定义背景", "选择内置图片后可换图"],
  en: ["Plugin shortcuts", "Randomize background", "Open custom background settings", "Enable Custom Background first", "Select built-in images to shuffle"],
  ja: ["プラグインの操作", "別の画像に切り替え", "背景設定を開く", "カスタム背景を有効にしてください", "内蔵画像を選ぶと切り替えられます"],
  ko: ["플러그인 바로가기", "다른 이미지로 변경", "사용자 지정 배경 설정 열기", "사용자 지정 배경을 먼저 켜세요", "기본 이미지를 선택하면 변경할 수 있어요"],
};

const railSelector = "nav[data-app-navigation-rail]";
const signSize = 36;

function firstLayoutRect(stack, sign) {
  let first;
  for (const item of stack.children) {
    if (sign.contains(item)) continue;
    const { display, visibility } = getComputedStyle(item);
    if (display === "none") continue;
    const box = item.getBoundingClientRect();
    const inViewport = box.width > 0 && box.height > 0 && box.bottom > 0 && box.top < innerHeight &&
      box.right > 0 && box.left < innerWidth;
    // Loading indicators can be non-interactive, faded, or marked aria-hidden while keeping their slot.
    const candidate = visibility === "visible" && inViewport ? box : firstLayoutRect(item, sign);
    if (candidate && (!first || candidate.top < first.top)) first = candidate;
  }
  return first;
}

function followRail(sign, onPosition) {
  let rail, stack, queued = false, stopped = false;
  const changes = new MutationObserver(schedule);
  const sizes = new ResizeObserver(schedule);
  const visibilityAttributes = ["hidden", "style", "class", "aria-hidden", "aria-busy", "data-state", "disabled"];

  function observe(nextRail, nextStack) {
    rail = nextRail;
    stack = nextStack;
    changes.disconnect();
    sizes.disconnect();
    if (!rail) {
      changes.observe(document.body, { childList: true, subtree: true });
      return;
    }
    changes.observe(rail, { childList: true, subtree: true, attributes: true, attributeFilter: visibilityAttributes });
    for (let parent = rail.parentElement; parent; parent = parent.parentElement) {
      changes.observe(parent, { childList: true, attributes: true, attributeFilter: visibilityAttributes });
    }
    if (stack) sizes.observe(stack);
  }

  function place() {
    const nextRail = document.querySelector(railSelector);
    const nextStack = nextRail?.lastElementChild;
    if (rail !== nextRail || stack !== nextStack) observe(nextRail, nextStack);
    const first = stack && firstLayoutRect(stack, sign);
    // Below one icon-height there is nowhere to put P-Sign without covering the native button.
    sign.hidden = !first || first.top < signSize || innerWidth < signSize;
    if (!sign.hidden) {
      sign.style.left = Math.max(0, Math.min(first.left, innerWidth - signSize)) + "px";
      sign.style.top = Math.max(0, first.top - signSize - 8) + "px";
    }
    onPosition();
  }
  function schedule() {
    if (queued || stopped) return;
    queued = true;
    queueMicrotask(() => {
      queued = false;
      if (!stopped) place();
    });
  }

  window.addEventListener("resize", schedule);
  window.addEventListener("scroll", schedule, true);
  place();
  return () => {
    stopped = true;
    changes.disconnect();
    sizes.disconnect();
    window.removeEventListener("resize", schedule);
    window.removeEventListener("scroll", schedule, true);
  };
}

export function activate({ root, onCleanup }) {
  const text = labels[document.documentElement.lang.toLowerCase().split("-")[0]] || labels.en;
  const sign = document.createElement("div");
  sign.className = "packpier-p-sign";
  sign.hidden = true;
  sign.innerHTML = `<button type="button" class="pp-sign-anchor"></button>
    <div class="pp-sign-tray" hidden><div class="pp-sign-tools" role="toolbar">
      <button type="button"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="16" cy="9" r="1" fill="currentColor" stroke="none"/><path d="m3 16 5.5-5 4 4 2.5-2 6 5"/></svg></button>
      <button type="button"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h7m4 0h5M13 5v4M4 12h3m4 0h9M9 10v4M4 17h9m4 0h3M15 15v4"/></svg></button>
    </div></div>`;
  const [anchor, shuffle, settings] = sign.querySelectorAll("button");
  const tray = sign.querySelector(".pp-sign-tray");
  const toolbar = sign.querySelector('[role="toolbar"]');
  anchor.setAttribute("aria-label", "Packpier · " + text[0]);
  toolbar.setAttribute("aria-label", text[0]);

  // Resolve the active instance on demand so reloading either plugin is safe.
  function target(button) {
    return document.querySelector(button === shuffle
      ? '[data-packpier-cbgp-random-trigger][data-action="random"]'
      : '[data-packpier-cbgp-quick-action][data-action="settings"]');
  }
  function sync(button) {
    const action = target(button);
    const ready = action && !action.disabled;
    const label = button === shuffle ? text[1] : text[2];
    button.setAttribute("aria-disabled", String(!ready));
    button.setAttribute("aria-label", label);
    button.dataset.tip = action || !target(settings) ? (action ? label : text[3]) : text[4];
    return ready ? action : null;
  }
  const extensions = hoverActions(toolbar, anchor);

  function fitTray() {
    const maxHeight = Math.max(36, Math.floor(sign.getBoundingClientRect().top) - 10);
    const overflow = toolbar.children.length * 34 + 6 > maxHeight;
    toolbar.classList.toggle("pp-sign-scroll", overflow);
    toolbar.style.maxHeight = overflow ? maxHeight + "px" : "";
    for (const button of toolbar.children) {
      if (overflow) button.title = button.dataset.tip;
      else button.removeAttribute("title");
    }
  }
  function refreshOpenTray() {
    if (tray.hidden) return;
    sync(shuffle);
    sync(settings);
    extensions.refresh();
    fitTray();
  }
  let timer;
  function show(open) {
    clearTimeout(timer);
    if (open === !tray.hidden) return;
    tray.hidden = !open;
    anchor.setAttribute("aria-expanded", String(open));
    if (open) {
      refreshOpenTray();
      document.addEventListener(changedEvent, refreshOpenTray);
    } else {
      document.removeEventListener(changedEvent, refreshOpenTray);
      extensions.clear();
    }
  }
  function closeLater() {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (!sign.matches(":hover") && !sign.matches(":focus-within")) show(false);
    }, 180);
  }
  for (const button of [shuffle, settings]) {
    button.addEventListener("click", () => {
      const action = sync(button);
      if (action) action.click();
    });
  }
  sign.addEventListener("pointerenter", () => show(true));
  sign.addEventListener("pointerleave", closeLater);
  sign.addEventListener("focusin", () => show(true));
  sign.addEventListener("focusout", closeLater);
  anchor.addEventListener("click", () => show(true));
  sign.addEventListener("keydown", event => {
    if (event.key === "Escape") { event.stopPropagation(); anchor.focus(); show(false); }
  });
  anchor.setAttribute("aria-expanded", "false");
  root.append(sign);
  const stopFollowing = followRail(sign, () => {
    if (sign.hidden) show(false);
    else if (!tray.hidden) fitTray();
  });
  onCleanup(() => { stopFollowing(); show(false); sign.remove(); });
}
