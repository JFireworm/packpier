import "./style.css";
import { changedEvent, hoverActions } from "./hover-actions.js";

const labels = {
  zh: ["插件快捷操作", "随机换一张", "打开自定义背景设置", "请先启用自定义背景", "选择内置图片后可换图"],
  en: ["Plugin shortcuts", "Randomize background", "Open custom background settings", "Enable Custom Background first", "Select built-in images to shuffle"],
  ja: ["プラグインの操作", "別の画像に切り替え", "背景設定を開く", "カスタム背景を有効にしてください", "内蔵画像を選ぶと切り替えられます"],
  ko: ["플러그인 바로가기", "다른 이미지로 변경", "사용자 지정 배경 설정 열기", "사용자 지정 배경을 먼저 켜세요", "기본 이미지를 선택하면 변경할 수 있어요"],
};

export function activate({ root, onCleanup }) {
  const text = labels[document.documentElement.lang.toLowerCase().split("-")[0]] || labels.en;
  const sign = document.createElement("div");
  sign.className = "packpier-p-sign";
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
      window.addEventListener("resize", fitTray);
    } else {
      document.removeEventListener(changedEvent, refreshOpenTray);
      window.removeEventListener("resize", fitTray);
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
  onCleanup(() => { show(false); sign.remove(); });
}
