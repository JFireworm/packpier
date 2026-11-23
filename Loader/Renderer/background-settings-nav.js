// The host renders the App settings group and its content as separate DOM surfaces.
const navSelector = "nav [data-settings-nav-scroll-container]";
const appearanceSelector = '[data-settings-panel-slug="appearance"]';
const panelSelector = "[data-settings-panel]";
const languageTitles = { zh: "自定义背景", en: "Custom background", ja: "カスタム背景", ko: "사용자 지정 배경" };

export function backgroundTitle() {
  const language = (document.documentElement.lang || navigator.language).split("-")[0];
  return languageTitles[language] || languageTitles.en;
}

export function registerBackgroundNavigation(section, closeSheet, openSheet) {
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.settingsPanelSlug = "packpier-custom-background";
  button.dataset.packpierBackgroundNav = "";
  button.innerHTML = '<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><rect x="2.5" y="4" width="19" height="16" rx="3"/><circle cx="8" cy="9.5" r="1.5"/><path d="m3 17 5-4.5 3.5 3 3.5-4 6 6"/></svg><span></span>';
  const label = button.lastElementChild;
  let nav = null;
  let content = null;
  let detach = null;

  function closeInline() {
    if (!content) return;
    try { detach?.(); } finally {
      content.parentElement?.removeAttribute("data-packpier-show-background");
      content.remove();
      content = null;
      detach = null;
      button.removeAttribute("aria-current");
    }
  }

  function nativeSelection(event) {
    if (event.target.closest?.("[data-settings-panel-slug],button,a,input") !== button) closeInline();
  }

  function openInline() {
    const dialog = nav?.closest('[role="dialog"],dialog');
    const panel = [...(dialog || document).querySelectorAll(panelSelector)]
      .find(node => !node.contains(nav) && node.getClientRects().length);
    if (!button.isConnected || !panel) return false;
    if (content?.parentElement === panel) return true;
    closeInline();
    closeSheet();
    content = document.createElement("section");
    content.dataset.packpierBackgroundPane = "";
    content.setAttribute("aria-label", backgroundTitle());
    panel.dataset.packpierShowBackground = "";
    panel.append(content);
    try { detach = section.mount(content); } catch (error) { closeInline(); throw error; }
    button.setAttribute("aria-current", "page");
    return true;
  }

  function refresh() {
    const anchor = document.querySelector(navSelector + " " + appearanceSelector);
    const nextNav = anchor?.closest("nav") ?? null;
    if (nav !== nextNav) {
      nav?.removeEventListener("click", nativeSelection, true);
      closeInline();
      nav = nextNav;
      nav?.addEventListener("click", nativeSelection, true);
    }
    if (content && !content.isConnected) closeInline();
    if (!anchor) { button.remove(); return; }
    const title = backgroundTitle();
    if (label.textContent !== title) label.textContent = title;
    if (anchor.nextElementSibling !== button) anchor.after(button);
  }

  button.addEventListener("click", () => { if (!openInline()) openSheet(); });
  const markers = "[data-settings-nav-scroll-container]," + appearanceSelector;
  const observer = new MutationObserver(records => {
    if ((nav && !nav.isConnected) || (content && !content.isConnected) ||
        records.some(record => record.type === "attributes" || nav?.contains(record.target) ||
          Array.from(record.addedNodes).some(node => node.nodeType === 1 &&
            (node.matches(markers) || node.querySelector(markers))))) refresh();
  });
  observer.observe(document.body, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ["data-settings-nav-scroll-container", "data-settings-panel-slug"],
  });
  observer.observe(document.documentElement, {attributes: true, attributeFilter: ["lang"]});
  refresh();
  return {
    openInline,
    unregister() {
      observer.disconnect();
      nav?.removeEventListener("click", nativeSelection, true);
      closeInline();
      button.remove();
    },
  };
}
