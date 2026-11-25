import "./style.css";
import { localImageURL, runImageAction as performImageAction } from "./image-actions.js";
import {
  readStorageWithLegacyFallback,
  writeStorageAndRemoveLegacy,
} from "./storage-migration.js";
import {
  TRANSPARENT_BACKGROUND_KIND,
  canStoreBackgroundHistory,
  isTransparentBackgroundActive,
  normalizeBackgroundKind as normalizeKind,
} from "./background-mode.js";
import { isCodexPetRendererLocation } from "./renderer-scope.js";
import { createThreadClipping, THREAD_CLIP_ANCHORS } from "./thread-clipping.js";
import { effectiveCSSZoom } from "./css-zoom.js";

const RUNTIME_KEY = Symbol.for("codex-tweaks.codex-custom-background.runtime");
const LEGACY_RUNTIME_KEY = Symbol.for("codex-tweaks.codex-random-background.runtime");
const WALLPAPER_MARKER = "data-packpier-cbgp-wallpaper";
const WINDOW_FROST_MARKER = "data-packpier-cbgp-window-frost";
const THEME_MARKER = "data-packpier-cbgp-theme";
const FROST_MARKER = "data-packpier-cbgp-frost";
const BACKGROUND_FROST_MARKER = "data-packpier-cbgp-background-frost";
const TRANSPARENT_MARKER = "data-packpier-cbgp-transparent";
const BUTTON_MARKER = "data-packpier-cbgp-random-button";
const BUTTON_TRIGGER_MARKER = "data-packpier-cbgp-random-trigger";
const QUICK_ACTION_MARKER = "data-packpier-cbgp-quick-action";
const PANEL_MARKER = "data-packpier-cbgp-settings-panel";
const LEGACY_SETTINGS_EMBED_MARKER = "data-packpier-cbgp-embed";
const SETTINGS_NAV_LABEL = "自定义背景";
const IMAGE_JOB_MARKER = "data-packpier-cbgp-loading";
const STORAGE_KEY = "codex-tweaks:codex-custom-background:v1";
const LEGACY_STORAGE_KEY = "codex-tweaks:codex-random-background:v1";
const HISTORY_LIMIT = 10;
const STORED_IMAGE_MAX_EDGE = 2560;
const STORED_IMAGE_QUALITY = 0.82;
const DOM_SYNC_DEBOUNCE_MS = 80;
const PAGE_ANCHOR_SELECTOR = [
  "[data-app-shell-active-page]",
  '[data-app-shell-main-surface="default"]',
  "button[data-settings-panel-slug]",
  "aside.app-shell-left-panel",
  'main[class*="MainContentSurface"]',
  THREAD_CLIP_ANCHORS,
].join(", ");
const MASK_DEFAULTS = Object.freeze({
  light: Object.freeze({ color: "#f6f6f6", opacity: 0.72 }),
  dark: Object.freeze({ color: "#141418", opacity: 0.76 }),
});
const FROST_DEFAULTS = Object.freeze({ enabled: false, strength: 0.6 });
const FROST_MAX_BLUR_PX = 28;
const BACKGROUND_FROST_DEFAULTS = Object.freeze({ enabled: false, strength: 0.5 });
const BACKGROUND_FROST_MAX_BLUR_PX = 32;
const ACTION_TOAST_DURATION_MS = 3600;
const LEGACY_SURFACE_MARKERS = [
  "data-packpier-cbgp-transparent-surface",
  "data-packpier-cbgp-material-surface",
  "data-packpier-cbgp-hidden-chrome",
  "data-packpier-cbgp-composer-surface",
  "data-packpier-cbgp-suggestion-card",
  "data-codex-tweaks-rbgp-transparent-surface",
  "data-codex-tweaks-rbgp-material-surface",
  "data-codex-tweaks-rbgp-hidden-chrome",
  "data-codex-tweaks-rbgp-composer-surface",
  "data-codex-tweaks-rbgp-suggestion-card",
];
const LEGACY_RANDOM_BACKGROUND_NODE_MARKERS = [
  "data-codex-tweaks-rbgp-wallpaper",
  "data-codex-tweaks-rbgp-random-button",
  "data-codex-tweaks-rbgp-settings-panel",
  "data-codex-tweaks-rbgp-embed",
  "data-codex-tweaks-rbgp-context-menu",
  "data-codex-tweaks-rbgp-action-toast",
];
const LEGACY_RANDOM_BACKGROUND_ROOT_MARKERS = [
  "data-codex-tweaks-rbgp-theme",
  "data-codex-tweaks-rbgp-frost",
  "data-codex-tweaks-rbgp-background-frost",
  "data-codex-tweaks-rbgp-loading",
];
const CURRENT_BACKGROUND_NODE_MARKERS = [
  WALLPAPER_MARKER,
  WINDOW_FROST_MARKER,
  BUTTON_MARKER,
  PANEL_MARKER,
  "data-packpier-cbgp-settings-dialog",
  "data-packpier-cbgp-context-menu",
  "data-packpier-cbgp-action-toast",
];
const CURRENT_BACKGROUND_ROOT_MARKERS = [
  THEME_MARKER,
  FROST_MARKER,
  BACKGROUND_FROST_MARKER,
  TRANSPARENT_MARKER,
  IMAGE_JOB_MARKER,
];

const RANDOM_PROVIDERS = new Map([
  [
    "alcy-pc",
    {
      id: "alcy-pc",
      label: "栗次元（t.alcy.cc）",
      url: "https://t.alcy.cc/pc",
      jsonUrl: "https://t.alcy.cc/json?pc=1",
      imageOrigins: ["https://tc.alcy.cc"],
      // 新版服务把静态图片放在 API 同域名下，只接受固定图片路径。
      imagePathPatterns: {
        "https://t.alcy.cc": /^\/pic\/pc\/[^/]+\.(?:webp|png|jpe?g|avif)$/i,
      },
    },
  ],
]);
const DEFAULT_PROVIDER_ID = "alcy-pc";

function isResolvedRandomImageUrl(value, provider = null) {
  if (typeof value !== "string" || !value.trim()) return false;
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password) return false;
    const providers = provider ? [provider] : [...RANDOM_PROVIDERS.values()];
    return providers.some((candidate) =>
      candidate.imageOrigins?.includes(parsed.origin) ||
      candidate.imagePathPatterns?.[parsed.origin]?.test(parsed.pathname),
    );
  } catch {
    return false;
  }
}

function normalizeMaskColor(value, fallback) {
  return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value)
    ? value.toLowerCase()
    : fallback;
}

function normalizeMaskOpacity(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(1, Math.max(0, number));
}

function maskRGBTriplet(color) {
  const normalized = normalizeMaskColor(color, "#000000");
  return [1, 3, 5]
    .map((offset) => Number.parseInt(normalized.slice(offset, offset + 2), 16))
    .join(" ");
}

export function activate({ api, node, ui }) {
  const runtimeHost = document.documentElement;
  runtimeHost[RUNTIME_KEY]?.cleanup?.();
  runtimeHost[LEGACY_RUNTIME_KEY]?.cleanup?.();

  function removeLegacyRandomBackgroundArtifacts() {
    for (const marker of LEGACY_RANDOM_BACKGROUND_NODE_MARKERS) {
      for (const node of document.querySelectorAll(`[${marker}]`)) node.remove();
    }
    for (const marker of LEGACY_RANDOM_BACKGROUND_ROOT_MARKERS) {
      runtimeHost.removeAttribute(marker);
    }
    runtimeHost.style.removeProperty("--ct-rbgp-frost-blur");
  }

  // 1.0.0 早期版本会把设置面板直接嵌入「个性化」。独立设置路由启用后，
  // 主动移除热重载或异常退出可能留下的旧节点，避免同一套设置同时出现在两处。
  function removeLegacySettingsEmbed() {
    for (const node of document.querySelectorAll(`[${LEGACY_SETTINGS_EMBED_MARKER}]`)) {
      node.remove();
    }
  }

  function removeLegacySurfaceMarkers() {
    for (const marker of LEGACY_SURFACE_MARKERS) {
      for (const node of document.querySelectorAll(`[${marker}]`)) {
        node.removeAttribute(marker);
      }
    }
  }

  function removeCurrentBackgroundArtifacts() {
    for (const marker of CURRENT_BACKGROUND_NODE_MARKERS) {
      for (const node of document.querySelectorAll(`[${marker}]`)) node.remove();
    }
    for (const marker of CURRENT_BACKGROUND_ROOT_MARKERS) {
      runtimeHost.removeAttribute(marker);
    }
    runtimeHost.style.removeProperty("--ct-cbgp-frost-blur");
  }

  removeLegacyRandomBackgroundArtifacts();
  removeLegacySettingsEmbed();
  removeLegacySurfaceMarkers();

  // Codex 宠物运行在独立透明 Renderer 及多个 composition surface 中。背景包
  // 只属于主 Codex 窗口；在宠物 Renderer 继续创建全屏壁纸/遮罩，会直接变成
  // 宠物背后的矩形底板。热重载时也主动清理旧版本可能留下的当前标记。
  if (isCodexPetRendererLocation(window.location.href)) {
    const cleanupPetRenderer = () => {
      removeCurrentBackgroundArtifacts();
      if (runtimeHost[RUNTIME_KEY]?.cleanup === cleanupPetRenderer) {
        delete runtimeHost[RUNTIME_KEY];
      }
    };
    cleanupPetRenderer();
    api.registerCleanup(cleanupPetRenderer);
    runtimeHost[RUNTIME_KEY] = { cleanup: cleanupPetRenderer };
    return;
  }

  if (!node) throw new Error("Node runtime is required");
  const network = {
    request(parameters) {
      return node.invoke("network.request", parameters);
    },
  };
  let disposed = false;
  let shouldRefreshLegacyRandom = false;
  let shouldRemoveLegacyStorage = false;
  let state = loadState();
  const favoriteDownloads = new Map();
  const localURLs = new Map();
  let currentLocal = null;
  let wallpaperNode = null;
  let windowFrostNode = null;
  let windowFrostSurface = null;
  let windowFrostObserver = null;
  let windowFrostClip = "";
  const threadClipping = createThreadClipping();
  let signShuffle = null;
  let settingsPaneNode = null;
  let previewTheme = document.documentElement.matches('[data-theme="light"], .electron-light') ? "light" : "dark";
  let advancedOpen = false;
  let settingsSectionRegistration = null;
  let openSettingsSelect = null;
  let settingsSelectSequence = 0;
  let panelOpen = false;
  let historyContextMenuNode = null;
  let historyContextMenuTriggerNode = null;
  let historyActionPending = false;
  let actionToastNode = null;
  let actionToastTimer = null;
  let confirmDialogNode = null;
  let confirmDialogReturnFocusNode = null;
  let imageJobToken = 0;
  let domObserver = null;
  let domSyncTimer = null;

  /* -------------------------------- 状态 -------------------------------- */

  function loadState() {
    try {
      const stored = readStorageWithLegacyFallback(
        window.localStorage,
        STORAGE_KEY,
        LEGACY_STORAGE_KEY,
      );
      shouldRemoveLegacyStorage = stored.hasLegacy;
      const { raw } = stored;
      if (!raw) return defaultState();
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object") return defaultState();
      const storedKind = normalizeKind(parsed.kind);
      const resolvedRandomUrl = isResolvedRandomImageUrl(parsed.finalUrl)
        ? parsed.finalUrl.trim()
        : isResolvedRandomImageUrl(parsed.alcyUrl)
          ? parsed.alcyUrl.trim()
          : "";
      const kind = storedKind === "alcy" && !resolvedRandomUrl ? "none" : storedKind;
      if (storedKind === "alcy" && kind === "none") {
        shouldRefreshLegacyRandom = true;
      }
      const history = (Array.isArray(parsed.history) ? parsed.history : [])
        .map(normalizeHistoryEntry).filter(Boolean).slice(0, HISTORY_LIMIT);
      const favorites = (Array.isArray(parsed.favorites) ? parsed.favorites : []).map(item =>
        typeof item === "string" ? history.find(entry => entry.id === item) :
          item?.historyId ? normalizeHistoryEntry({ ...history.find(entry => entry.id === item.historyId), file: item.file }) :
          normalizeHistoryEntry(item)
      ).filter(Boolean);
      return {
        backgroundEnabled: parsed.backgroundEnabled !== false,
        maskLightColor: normalizeMaskColor(
          parsed.maskLightColor,
          MASK_DEFAULTS.light.color,
        ),
        maskLightOpacity: normalizeMaskOpacity(
          parsed.maskLightOpacity,
          MASK_DEFAULTS.light.opacity,
        ),
        maskDarkColor: normalizeMaskColor(
          parsed.maskDarkColor,
          MASK_DEFAULTS.dark.color,
        ),
        maskDarkOpacity: normalizeMaskOpacity(
          parsed.maskDarkOpacity,
          MASK_DEFAULTS.dark.opacity,
        ),
        frostEnabled: typeof parsed.frostEnabled === "boolean" ? parsed.frostEnabled : FROST_DEFAULTS.enabled,
        frostStrength: normalizeMaskOpacity(
          parsed.frostStrength,
          FROST_DEFAULTS.strength,
        ),
        backgroundFrostEnabled: parsed.backgroundFrostEnabled === true,
        backgroundFrostStrength: normalizeMaskOpacity(
          parsed.backgroundFrostStrength,
          BACKGROUND_FROST_DEFAULTS.strength,
        ),
        kind,
        providerId: normalizeProviderId(parsed.providerId),
        url: typeof parsed.url === "string" ? parsed.url : "",
        dataUrl: typeof parsed.dataUrl === "string" ? parsed.dataUrl : "",
        finalUrl: kind === "alcy" ? resolvedRandomUrl : "",
        alcyUrl: kind === "alcy" ? resolvedRandomUrl : "",
        updatedAt: Number(parsed.updatedAt) || 0,
        history,
        favorites,
      };
    } catch {
      return defaultState();
    }
  }

  function normalizeHistoryEntry(entry) {
    if (!entry || typeof entry !== "object") return null;
    const kind = normalizeKind(entry.kind);
    if (!canStoreBackgroundHistory(kind)) return null;
    const url = typeof entry.url === "string" ? entry.url.trim() : "";
    const dataUrl = typeof entry.dataUrl === "string" ? entry.dataUrl : "";
    if (kind === "alcy" && !isResolvedRandomImageUrl(url)) return null;
    if (kind === "url" && !/^(https?:|data:image\/)/i.test(url)) return null;
    if (kind === "local" && !/^data:image\//i.test(dataUrl)) return null;
    const normalized = {
      kind,
      id: typeof entry.id === "string" ? entry.id : "",
      url,
      dataUrl,
      updatedAt: Number(entry.updatedAt) || 0,
    };
    if (typeof entry.file === "string" && /^[a-f0-9]{64}\.(png|jpg|webp|gif|avif|heic|tif|bmp)$/.test(entry.file)) normalized.file = entry.file;
    normalized.id = historyEntryId(normalized);
    return normalized;
  }

  function defaultState() {
    return {
      backgroundEnabled: true,
      maskLightColor: MASK_DEFAULTS.light.color,
      maskLightOpacity: MASK_DEFAULTS.light.opacity,
      maskDarkColor: MASK_DEFAULTS.dark.color,
      maskDarkOpacity: MASK_DEFAULTS.dark.opacity,
      frostEnabled: FROST_DEFAULTS.enabled,
      frostStrength: FROST_DEFAULTS.strength,
      backgroundFrostEnabled: BACKGROUND_FROST_DEFAULTS.enabled,
      backgroundFrostStrength: BACKGROUND_FROST_DEFAULTS.strength,
      kind: "none",
      providerId: DEFAULT_PROVIDER_ID,
      url: "",
      dataUrl: "",
      finalUrl: "",
      alcyUrl: "",
      updatedAt: 0,
      history: [],
      favorites: [],
    };
  }

  function normalizeProviderId(id) {
    if (typeof id === "string" && RANDOM_PROVIDERS.has(id)) return id;
    return DEFAULT_PROVIDER_ID;
  }

  function getActiveProvider() {
    return RANDOM_PROVIDERS.get(state.providerId) ?? RANDOM_PROVIDERS.get(DEFAULT_PROVIDER_ID);
  }

  function historyEntryId(entry) {
    if (typeof entry?.id === "string" && entry.id) return entry.id;
    return `${Number(entry?.updatedAt) || Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }

  function persistState() {
    try {
      writeStorageAndRemoveLegacy(
        window.localStorage,
        STORAGE_KEY,
        LEGACY_STORAGE_KEY,
        JSON.stringify({ ...state, favorites: state.favorites.map(entry => {
          const history = state.history.find(item => sameImage(item, entry));
          if (!history) return entry;
          return entry.file ? { historyId: history.id, file: entry.file } : history.id;
        }) }),
        shouldRemoveLegacyStorage,
      );
      shouldRemoveLegacyStorage = false;
      return true;
    } catch {
      return false;
    }
  }

  function sameImage(a, b) {
    return a.kind === b.kind && historyEntryImageSource(a) === historyEntryImageSource(b);
  }

  function pushHistory(kind, extra) {
    const entry = normalizeHistoryEntry({
      kind,
      updatedAt: Date.now(),
      ...(extra ?? {}),
    });
    if (!entry) return;
    state.history = [entry, ...state.history.filter(item => !sameImage(item, entry))].slice(0, HISTORY_LIMIT);
    state.updatedAt = entry.updatedAt;
  }

  /* ------------------------------ 壁纸层 -------------------------------- */

  function resolveBackgroundUrl() {
    const source = currentSource();
    return currentLocal?.source === source ? currentLocal.url : source;
  }

  function currentSource() {
    if (state.kind === "url" && state.url.trim()) return state.url.trim();
    if (state.kind === "local" && state.dataUrl) return state.dataUrl;
    if (state.kind === "alcy") {
      if (isResolvedRandomImageUrl(state.finalUrl)) return state.finalUrl;
      if (isResolvedRandomImageUrl(state.alcyUrl)) return state.alcyUrl;
    }
    return null;
  }

  function cssEscapeUrl(value) {
    return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  }

  function applyMaskVariables(node) {
    node.style.setProperty("--ct-cbgp-mask-light-rgb", maskRGBTriplet(state.maskLightColor));
    node.style.setProperty(
      "--ct-cbgp-mask-light-opacity",
      String(state.maskLightOpacity),
    );
    node.style.setProperty("--ct-cbgp-mask-dark-rgb", maskRGBTriplet(state.maskDarkColor));
    node.style.setProperty(
      "--ct-cbgp-mask-dark-opacity",
      String(state.maskDarkOpacity),
    );
  }

  function applyFrostAppearance() {
    runtimeHost.style.setProperty(
      "--ct-cbgp-frost-blur",
      `${Math.round(state.frostStrength * FROST_MAX_BLUR_PX)}px`,
    );
    runtimeHost.toggleAttribute(FROST_MARKER, state.frostEnabled);
  }

  function applyBackgroundFrostAppearance(node) {
    const blur = state.backgroundFrostEnabled
      ? Math.round(state.backgroundFrostStrength * BACKGROUND_FROST_MAX_BLUR_PX)
      : 0;
    node.style.setProperty("--ct-cbgp-background-frost-blur", `${blur}px`);
    node.style.setProperty(
      "--ct-cbgp-background-frost-overscan",
      `${Math.ceil(blur * 1.5)}px`,
    );
    runtimeHost.toggleAttribute(
      BACKGROUND_FROST_MARKER,
      state.backgroundFrostEnabled,
    );
  }

  function removeFrostAppearance() {
    runtimeHost.removeAttribute(FROST_MARKER);
    runtimeHost.removeAttribute(BACKGROUND_FROST_MARKER);
    runtimeHost.style.removeProperty("--ct-cbgp-frost-blur");
  }

  function applyPreviewBackground(preview, url) {
    const light = previewTheme === "light";
    const color = light ? state.maskLightColor : state.maskDarkColor;
    const strength = light ? state.maskLightOpacity : state.maskDarkOpacity;
    preview.dataset.theme = previewTheme;
    preview.style.setProperty("--ct-preview-tint", 'rgb(' + maskRGBTriplet(color) + ' / ' + strength + ')');
    preview.style.setProperty("--ct-preview-blur", (state.backgroundFrostEnabled ? Math.round(state.backgroundFrostStrength * BACKGROUND_FROST_MAX_BLUR_PX) : 0) + "px");
    if (url) preview.style.backgroundImage = 'url("' + cssEscapeUrl(url) + '")';
  }

  function ensureWallpaperNode() {
    if (wallpaperNode?.isConnected) return wallpaperNode;
    const node = document.createElement("div");
    node.setAttribute(WALLPAPER_MARKER, "");
    node.setAttribute("aria-hidden", "true");
    node.hidden = true;
    // P-Sign discovers these two commands by selector. Keep them outside the visible UI and tab order.
    signShuffle = document.createElement("button");
    signShuffle.type = "button";
    signShuffle.hidden = true;
    signShuffle.dataset.action = "random";
    signShuffle.addEventListener("click", () => {
      if (state.kind === "alcy") applyRandom();
    });
    const settings = document.createElement("button");
    settings.type = "button";
    settings.hidden = true;
    settings.setAttribute(QUICK_ACTION_MARKER, "");
    settings.dataset.action = "settings";
    settings.addEventListener("click", openCustomBackgroundSettings);
    node.append(signShuffle, settings);
    document.body.prepend(node);
    wallpaperNode = node;
    return node;
  }

  function syncWindowFrost() {
    if (disposed || !wallpaperNode?.isConnected) return;
    if (!state.frostEnabled || !runtimeHost.hasAttribute(THEME_MARKER)) {
      windowFrostObserver?.disconnect();
      windowFrostSurface = null;
      if (windowFrostNode && !windowFrostNode.hidden) windowFrostNode.hidden = true;
      return;
    }
    if (!windowFrostNode?.isConnected) {
      windowFrostNode = document.createElement("div");
      windowFrostClip = "";
      windowFrostNode.setAttribute(WINDOW_FROST_MARKER, "");
      windowFrostNode.setAttribute("aria-hidden", "true");
      wallpaperNode.after(windowFrostNode);
    }
    const surface = getActivePageRoot().querySelector('[data-app-shell-main-surface="default"]');
    if (surface !== windowFrostSurface) {
      windowFrostObserver?.disconnect();
      windowFrostSurface = surface;
      if (surface) {
        windowFrostObserver ??= new ResizeObserver(syncWindowFrost);
        windowFrostObserver.observe(surface);
      }
    }
    if (windowFrostNode.hidden !== !surface) windowFrostNode.hidden = !surface;
    if (!surface) return;
    // 一个独立的底层磨砂面覆盖侧栏、标题栏和外圈，中间工作区挖空。
    // 不把滤镜加在应用祖先上，避免再次截断输入框的 backdrop 采样。
    // 磨砂节点挂在 body，位于 Codex 缩放容器之外，直接使用视口坐标。
    const { left, top, right, bottom } = surface.getBoundingClientRect();
    const width = window.innerWidth;
    const height = window.innerHeight;
    const clip = `polygon(evenodd, 0px 0px, ${width}px 0px, ${width}px ${height}px, 0px ${height}px, 0px 0px, ${left}px ${top}px, ${right}px ${top}px, ${right}px ${bottom}px, ${left}px ${bottom}px, ${left}px ${top}px, 0px 0px)`;
    // CSSOM 会把小数坐标舍入，不能用序列化后的样式与原始坐标比较。
    if (windowFrostClip !== clip) {
      windowFrostNode.style.clipPath = clip;
      windowFrostClip = clip;
    }
  }

  function syncBackgroundLayout() {
    syncWindowFrost();
    threadClipping.sync(runtimeHost.hasAttribute(THEME_MARKER) ? getActivePageRoot() : null);
  }

  function applyWallpaper() {
    if (disposed) return;
    const transparent = isTransparentBackgroundActive(
      state.kind,
      state.backgroundEnabled,
    );
    const url = state.backgroundEnabled ? resolveBackgroundUrl() : null;
    const node = ensureWallpaperNode();
    signShuffle.toggleAttribute(BUTTON_TRIGGER_MARKER, state.kind === "alcy");
    applyMaskVariables(node);
    applyBackgroundFrostAppearance(node);
    node.toggleAttribute(TRANSPARENT_MARKER, transparent);
    runtimeHost.toggleAttribute(TRANSPARENT_MARKER, transparent);
    if (!url && !transparent) {
      node.hidden = true;
      node.style.removeProperty("--ct-cbgp-bg-image");
      runtimeHost.removeAttribute(THEME_MARKER);
      removeFrostAppearance();
      syncBackgroundLayout();
      return;
    }
    if (url) {
      node.style.setProperty("--ct-cbgp-bg-image", `url("${cssEscapeUrl(url)}")`);
    } else {
      node.style.removeProperty("--ct-cbgp-bg-image");
    }
    node.hidden = false;
    runtimeHost.setAttribute(THEME_MARKER, "");
    applyFrostAppearance();
    syncBackgroundLayout();
  }

  function removeWallpaper() {
    threadClipping.clear();
    runtimeHost.removeAttribute(THEME_MARKER);
    runtimeHost.removeAttribute(TRANSPARENT_MARKER);
    removeFrostAppearance();
    wallpaperNode?.remove();
    wallpaperNode = null;
    windowFrostObserver?.disconnect();
    windowFrostObserver = null;
    windowFrostSurface = null;
    windowFrostNode?.remove();
    windowFrostNode = null;
    windowFrostClip = "";
  }

  /* ---------------------------- 随机与固定来源 ---------------------------- */

  function setLoading(jobId, loading) {
    if (jobId !== imageJobToken || disposed) return;
    document.documentElement.toggleAttribute(IMAGE_JOB_MARKER, loading);
    const shuffle = settingsPaneNode?.querySelector('[data-slot="preview-shuffle"]');
    if (shuffle) shuffle.disabled = loading;
    if (signShuffle) signShuffle.disabled = loading;
  }

  function cancelPendingImageJob() {
    imageJobToken += 1;
    setLoading(imageJobToken, false);
  }

  function markFailed(message = "") {
    if (message) showActionToast(message, "error");
  }

  function preloadImage(src, timeoutMs = 20000) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      let settled = false;
      const timer = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        image.src = "";
        reject(new Error("timeout"));
      }, timeoutMs);
      image.onload = () => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timer);
        resolve(image);
      };
      image.onerror = () => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timer);
        reject(new Error("load error"));
      };
      image.referrerPolicy = "no-referrer";
      image.src = src;
    });
  }

  function makeAlcyRequestUrl(provider) {
    // 每次点击都加唯一查询参数，强制浏览器重新请求，避免命中缓存后点击无效。
    return `${provider.url}?ct=${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  }

  async function resolveFinalAlcyUrl(provider, requestUrl) {
    let redirectError = null;
    try {
      const redirected = await network.request({
        url: requestUrl,
        method: "HEAD",
        responseType: "none",
        timeoutMs: 8000,
      });
      if (
        redirected?.ok &&
        isResolvedRandomImageUrl(redirected.finalUrl, provider)
      ) {
        return redirected.finalUrl;
      }
      redirectError = new Error(`http ${redirected?.status ?? "unknown"}`);
    } catch (error) {
      redirectError = error;
    }

    if (!provider.jsonUrl) throw redirectError ?? new Error("no resolver");
    const response = await network.request({
      url: provider.jsonUrl,
      method: "GET",
      responseType: "json",
      timeoutMs: 8000,
    });
    if (!response?.ok) throw new Error(`http ${response?.status ?? "unknown"}`);
    const payload = response.body;
    const link =
      typeof payload?.data?.link === "string"
        ? payload.data.link
        : typeof payload?.link === "string"
          ? payload.link
          : "";
    if (!isResolvedRandomImageUrl(link, provider)) throw new Error("bad payload");
    return link;
  }

  function completeRandom(jobId, finalUrl) {
    if (disposed || jobId !== imageJobToken) return;
    state.backgroundEnabled = true;
    state.kind = "alcy";
    state.url = "";
    state.dataUrl = "";
    state.finalUrl = finalUrl;
    state.alcyUrl = finalUrl;
    pushHistory("alcy", { url: finalUrl });
    persistState();
    applyWallpaper();
    refreshSettingsPaneIfOpen();
  }

  function applyRandom() {
    const provider = getActiveProvider();
    if (!provider) return;
    const jobId = ++imageJobToken;
    setLoading(jobId, true);
    const requestUrl = makeAlcyRequestUrl(provider);

    resolveFinalAlcyUrl(provider, requestUrl)
      .then((finalUrl) => {
        if (disposed || jobId !== imageJobToken) return;
        return preloadImage(finalUrl).then(() => {
          completeRandom(jobId, finalUrl);
        });
      })
      .catch(() => {
        if (disposed || jobId !== imageJobToken) return;
        const { isChinese } = getLocaleStrings();
        markFailed(
          isChinese
            ? "内置图片获取失败，已保留当前背景，请稍后重试。"
            : "Could not load a random image. The current background was kept; try again later.",
        );
      })
      .finally(() => setLoading(jobId, false));
  }

  function applyLocalFile(file) {
    if (!file || !/^image\//i.test(file.type)) return;
    const jobId = ++imageJobToken;
    setLoading(jobId, true);
    fileToCompressedDataUrl(file, STORED_IMAGE_MAX_EDGE, STORED_IMAGE_QUALITY)
      .then((dataUrl) => {
        if (disposed || jobId !== imageJobToken) return;
        if (!dataUrl) {
          markFailed();
          return;
        }
        state.backgroundEnabled = true;
        state.kind = "local";
        state.dataUrl = dataUrl;
        state.url = "";
        state.finalUrl = "";
        state.alcyUrl = "";
        pushHistory("local", { dataUrl });
        persistState();
        applyWallpaper();
        refreshSettingsPaneIfOpen();
      })
      .catch(() => {
        if (disposed || jobId !== imageJobToken) return;
        markFailed();
      })
      .finally(() => setLoading(jobId, false));
  }

  function fileToCompressedDataUrl(file, maxEdge, quality) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(reader.error);
      reader.onload = () => {
        const probe = new Image();
        probe.onload = () => {
          try {
            const { width, height } = fitSize(
              probe.naturalWidth,
              probe.naturalHeight,
              maxEdge,
            );
            const canvas = document.createElement("canvas");
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext("2d");
            ctx.drawImage(probe, 0, 0, width, height);
            const webp = canvas.toDataURL("image/webp", quality);
            const out = webp.startsWith("data:image/webp")
              ? webp
              : canvas.toDataURL("image/jpeg", Math.min(0.9, quality + 0.06));
            resolve(out);
          } catch (error) {
            reject(error);
          }
        };
        probe.onerror = () => reject(new Error("image decode error"));
        probe.src = reader.result;
      };
      reader.readAsDataURL(file);
    });
  }

  function fitSize(width, height, maxEdge) {
    if (!width || !height) return { width: 1, height: 1 };
    const scale = Math.min(1, maxEdge / Math.max(width, height));
    return {
      width: Math.max(1, Math.round(width * scale)),
      height: Math.max(1, Math.round(height * scale)),
    };
  }

  function clearBackground() {
    cancelPendingImageJob();
    state.backgroundEnabled = true;
    state.kind = "none";
    state.url = "";
    state.dataUrl = "";
    state.finalUrl = "";
    state.alcyUrl = "";
    state.updatedAt = Date.now();
    persistState();
    applyWallpaper();
    refreshSettingsPaneIfOpen();
  }

  function restoreHistoryEntry(entry) {
    if (!entry) return;
    const stored =
      entry.kind === "url" ? entry.url : entry.kind === "local" ? entry.dataUrl : "";
    const target = entry.kind === "alcy" ? entry.url : stored;
    if (!target) return;
    const jobId = ++imageJobToken;
    setLoading(jobId, true);
    const file = favoriteFor(entry)?.file || entry.file;
    const local = file && entry.kind !== "local" ? readFavorite(file).catch(() => null) : Promise.resolve(null);
    local.then(async url => {
      await preloadImage(url || target);
      return url;
    }).then(url => {
        if (disposed || jobId !== imageJobToken) return;
        state.backgroundEnabled = true;
        currentLocal = url ? {source: target, url} : null;
        state.kind = entry.kind;
        state.url = entry.kind === "url" ? entry.url : "";
        state.dataUrl = entry.kind === "local" ? entry.dataUrl : "";
        state.finalUrl = entry.kind === "alcy" ? entry.url : "";
        state.alcyUrl = entry.kind === "alcy" ? entry.url : "";
        pushHistory(entry.kind, { ...entry, updatedAt: Date.now() });
        persistState();
        applyWallpaper();
        refreshSettingsPaneIfOpen();
      })
      .catch(() => {
        if (disposed || jobId !== imageJobToken) return;
        markFailed();
      })
      .finally(() => setLoading(jobId, false));
  }

  function clearHistory() {
    state.history = [];
    persistState();
    refreshSettingsPaneIfOpen();
  }

  function getActivePageRoot() {
    return document.querySelector('[data-app-shell-active-page="true"]') ?? document;
  }

  function createStrokeIcon(paths, strokeWidth = "1.8") {
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.setAttribute("viewBox", "0 0 24 24");
    icon.setAttribute("fill", "none");
    icon.setAttribute("aria-hidden", "true");
    icon.setAttribute("width", "18");
    icon.setAttribute("height", "18");
    for (const d of paths) {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      path.setAttribute("stroke", "currentColor");
      path.setAttribute("stroke-width", strokeWidth);
      path.setAttribute("stroke-linecap", "round");
      path.setAttribute("stroke-linejoin", "round");
      icon.append(path);
    }
    return icon;
  }

  function releaseNativeSettingsSection() {
    const registration = settingsSectionRegistration;
    settingsSectionRegistration = null;
    try {
      registration?.unregister?.();
    } catch (error) {
      console.warn("自定义背景原生设置入口无法注销", error);
    }
  }

  function openCustomBackgroundSettings() {
    if (disposed) return;
    if (panelOpen && settingsPaneNode?.isConnected) return;
    try {
      if (!settingsSectionRegistration) throw new Error("设置扩展不可用");
      settingsSectionRegistration.open();
    } catch (error) {
      const { isChinese } = getLocaleStrings();
      showActionToast(isChinese
        ? "无法打开自定义背景设置，请检查 Packpier 连接后重试"
        : "Check the Packpier connection and try opening Custom Background again.", "error");
      console.warn("自定义背景原生设置入口不可用", error);
    }
  }

  /* --------------------- 设置面板：不依赖 Codex 私有路由 --------------------- */

  function getLocaleStrings() {
    const locale = document.documentElement.lang || navigator.language || "zh-CN";
    return { locale, isChinese: locale.toLowerCase().startsWith("zh") };
  }

  function createSection(title) {
    const section = document.createElement("section");
    section.className = "ct-cbgp-section";
    const heading = document.createElement("h2");
    heading.textContent = title;
    section.append(heading);
    return section;
  }

  function toolButton(label, onClick) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "ct-cbgp-tool-button";
    button.textContent = label;
    button.addEventListener("click", onClick);
    return button;
  }

  function switchButton({ checked, slot, ariaLabel, onToggle }) {
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "ct-cbgp-toggle";
    toggle.setAttribute("role", "switch");
    toggle.setAttribute("aria-label", ariaLabel);
    toggle.setAttribute("data-slot", slot);
    const knob = document.createElement("span");
    knob.className = "ct-cbgp-toggle-knob";
    toggle.append(knob);

    let current = Boolean(checked);
    const render = () => {
      toggle.setAttribute("aria-checked", String(current));
      toggle.toggleAttribute("data-on", current);
    };
    render();
    toggle.addEventListener("click", () => {
      current = !current;
      render();
      onToggle(current);
    });
    return toggle;
  }

  function closeOpenSettingsSelect({ restoreFocus = false } = {}) {
    openSettingsSelect?.close({ restoreFocus });
  }

  function createSelectControl({ slot, value, options, ariaLabel, unlistedLabel, onChange }) {
    const normalizedOptions = options.map(([optionValue, optionLabel]) => ({
      value: optionValue,
      label: optionLabel,
    }));
    let selectedIndex = normalizedOptions.findIndex((option) => option.value === value);
    const controlId = `ct-cbgp-select-${settingsSelectSequence += 1}`;

    const root = document.createElement("div");
    root.className = "ct-cbgp-select-control";

    // 保留原生 select 作为状态与自动化兼容层；用户看到并操作的是下方的
    // 自绘 listbox，避免 Chromium 无法定制的系统下拉浮层破坏设置页材质。
    const nativeSelect = document.createElement("select");
    nativeSelect.hidden = true;
    nativeSelect.setAttribute("data-slot", slot);
    nativeSelect.setAttribute("aria-hidden", "true");
    nativeSelect.tabIndex = -1;
    for (const option of normalizedOptions) {
      nativeSelect.append(new Option(option.label, option.value));
    }
    nativeSelect.selectedIndex = selectedIndex;

    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "ct-cbgp-select-trigger";
    trigger.setAttribute("aria-label", ariaLabel);
    trigger.setAttribute("aria-haspopup", "listbox");
    trigger.setAttribute("aria-expanded", "false");
    trigger.setAttribute("aria-controls", `${controlId}-listbox`);
    trigger.setAttribute("data-slot", `${slot}-trigger`);

    const triggerLabel = document.createElement("span");
    triggerLabel.className = "ct-cbgp-select-value";
    triggerLabel.textContent = normalizedOptions[selectedIndex]?.label ?? unlistedLabel;
    const chevron = createStrokeIcon(["m8 10 4 4 4-4"], "1.9");
    chevron.classList.add("ct-cbgp-select-chevron");
    trigger.append(triggerLabel, chevron);

    const menu = document.createElement("div");
    menu.id = `${controlId}-listbox`;
    menu.className = "ct-cbgp-select-menu";
    menu.setAttribute("role", "listbox");
    menu.setAttribute("aria-label", ariaLabel);
    menu.setAttribute("aria-hidden", "true");
    menu.setAttribute("data-slot", `${slot}-listbox`);

    const optionNodes = normalizedOptions.map((option, index) => {
      const optionNode = document.createElement("button");
      optionNode.type = "button";
      optionNode.className = "ct-cbgp-select-option";
      optionNode.setAttribute("role", "option");
      optionNode.setAttribute("aria-selected", String(index === selectedIndex));
      optionNode.tabIndex = -1;
      optionNode.dataset.value = option.value;
      const label = document.createElement("span");
      label.textContent = option.label;
      const check = createStrokeIcon(["m6.5 12.5 3.25 3.25L17.5 8"], "2");
      check.classList.add("ct-cbgp-select-check");
      optionNode.append(label, check);
      menu.append(optionNode);
      return optionNode;
    });

    let open = false;
    const focusOption = (index) => {
      const normalizedIndex = Math.min(
        optionNodes.length - 1,
        Math.max(0, index),
      );
      optionNodes[normalizedIndex]?.focus();
    };
    const close = ({ restoreFocus = false } = {}) => {
      if (!open && openSettingsSelect?.root !== root) return;
      open = false;
      root.removeAttribute("data-open");
      trigger.setAttribute("aria-expanded", "false");
      menu.setAttribute("aria-hidden", "true");
      if (openSettingsSelect?.root === root) openSettingsSelect = null;
      if (restoreFocus && trigger.isConnected) trigger.focus();
    };
    const openMenu = (focusIndex = selectedIndex) => {
      if (open) {
        focusOption(focusIndex);
        return;
      }
      closeOpenSettingsSelect();
      open = true;
      root.setAttribute("data-open", "");
      trigger.setAttribute("aria-expanded", "true");
      menu.setAttribute("aria-hidden", "false");
      openSettingsSelect = { root, close };
      window.requestAnimationFrame(() => {
        if (open && root.isConnected) focusOption(focusIndex);
      });
    };
    const selectOption = (index) => {
      const option = normalizedOptions[index];
      if (!option) return;
      close();
      nativeSelect.value = option.value;
      nativeSelect.dispatchEvent(new Event("change", { bubbles: true }));
    };

    trigger.addEventListener("click", () => {
      if (open) close({ restoreFocus: true });
      else openMenu(selectedIndex);
    });
    trigger.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        openMenu(event.key === "ArrowDown" ? selectedIndex : optionNodes.length - 1);
      } else if (event.key === "Home" || event.key === "End") {
        event.preventDefault();
        openMenu(event.key === "Home" ? 0 : optionNodes.length - 1);
      }
    });
    optionNodes.forEach((optionNode, index) => {
      optionNode.addEventListener("click", () => selectOption(index));
      optionNode.addEventListener("keydown", (event) => {
        let nextIndex = null;
        if (event.key === "ArrowDown") nextIndex = (index + 1) % optionNodes.length;
        else if (event.key === "ArrowUp") nextIndex = (index - 1 + optionNodes.length) % optionNodes.length;
        else if (event.key === "Home") nextIndex = 0;
        else if (event.key === "End") nextIndex = optionNodes.length - 1;
        else if (event.key === "Escape") {
          event.preventDefault();
          close({ restoreFocus: true });
          return;
        } else if (event.key === "Tab") {
          close();
          return;
        }
        if (nextIndex !== null) {
          event.preventDefault();
          focusOption(nextIndex);
        }
      });
    });
    nativeSelect.addEventListener("change", () => {
      const nextIndex = normalizedOptions.findIndex(
        (option) => option.value === nativeSelect.value,
      );
      if (nextIndex >= 0) {
        selectedIndex = nextIndex;
        triggerLabel.textContent = normalizedOptions[nextIndex].label;
        optionNodes.forEach((optionNode, index) => {
          optionNode.setAttribute("aria-selected", String(index === nextIndex));
        });
      }
      onChange(nativeSelect.value);
    });
    root.append(nativeSelect, trigger, menu);
    return root;
  }

  function updateRangeFill(range) {
    const min = Number(range.min) || 0;
    const max = Number(range.max) || 100;
    const progress = max > min ? (Number(range.value) - min) / (max - min) : 0;
    range.style.setProperty("--ct-cbgp-range-progress", String(progress));
  }

  function createMaskControlRow(theme, isChinese, preview, backgroundUrl) {
    const isLight = theme === "light";
    const colorKey = isLight ? "maskLightColor" : "maskDarkColor";
    const opacityKey = isLight ? "maskLightOpacity" : "maskDarkOpacity";
    const themeLabel = isLight
      ? (isChinese ? "浅色模式" : "Light mode")
      : (isChinese ? "深色模式" : "Dark mode");

    const row = document.createElement("div");
    row.className = "ct-cbgp-row ct-cbgp-mask-row";
    const label = document.createElement("span");
    label.className = "ct-cbgp-field-label";
    label.textContent = themeLabel;

    const controls = document.createElement("div");
    controls.className = "ct-cbgp-mask-controls";
    const color = document.createElement("input");
    color.type = "color";
    color.className = "ct-cbgp-color-input";
    color.value = state[colorKey];
    color.setAttribute("data-slot", `mask-${theme}-color`);
    color.setAttribute(
      "aria-label",
      isChinese ? `${themeLabel}遮罩颜色` : `${themeLabel} mask color`,
    );
    const colorValue = document.createElement("span");
    colorValue.className = "ct-cbgp-color-value";
    colorValue.textContent = state[colorKey].toUpperCase();

    const range = document.createElement("input");
    range.type = "range";
    range.className = "ct-cbgp-range";
    range.min = "0";
    range.max = "100";
    range.step = "1";
    range.value = String(Math.round(state[opacityKey] * 100));
    updateRangeFill(range);
    range.setAttribute("data-slot", `mask-${theme}-opacity`);
    range.setAttribute(
      "aria-label",
      isChinese ? `${themeLabel}遮罩强度` : `${themeLabel} mask strength`,
    );
    const value = document.createElement("output");
    value.className = "ct-cbgp-range-value";
    value.textContent = `${range.value}%`;

    const applyMaskSetting = () => {
      persistState();
      applyWallpaper();
      applyPreviewBackground(preview, backgroundUrl);
    };
    color.addEventListener("input", () => {
      state[colorKey] = normalizeMaskColor(color.value, state[colorKey]);
      colorValue.textContent = state[colorKey].toUpperCase();
      applyMaskSetting();
    });
    range.addEventListener("input", () => {
      updateRangeFill(range);
      state[opacityKey] = normalizeMaskOpacity(Number(range.value) / 100, state[opacityKey]);
      value.textContent = `${Math.round(state[opacityKey] * 100)}%`;
      applyMaskSetting();
    });

    controls.append(color, colorValue, range, value);
    row.append(label, controls);
    return row;
  }

  function createFrostControlRows({
    slotPrefix,
    enabled,
    strength,
    toggleLabel,
    strengthLabel,
    onEnabledChange,
    onStrengthChange,
  }) {
    const range = document.createElement("input");
    range.type = "range";
    range.className = "ct-cbgp-range";
    range.min = "0";
    range.max = "100";
    range.step = "1";
    range.value = String(Math.round(strength * 100));
    updateRangeFill(range);
    range.disabled = !enabled;
    range.setAttribute("data-slot", `${slotPrefix}-strength`);
    range.setAttribute("aria-label", strengthLabel);
    const rangeValue = document.createElement("output");
    rangeValue.className = "ct-cbgp-range-value";
    rangeValue.textContent = `${range.value}%`;

    const toggleRow = document.createElement("div");
    toggleRow.className = "ct-cbgp-row ct-cbgp-toggle-row";
    const toggleText = document.createElement("span");
    toggleText.className = "ct-cbgp-field-label";
    toggleText.textContent = toggleLabel;
    const toggle = switchButton({
      checked: enabled,
      slot: `${slotPrefix}-enabled-toggle`,
      ariaLabel: toggleLabel,
      onToggle: (nextEnabled) => {
        range.disabled = !nextEnabled;
        onEnabledChange(nextEnabled);
      },
    });
    toggleRow.append(toggleText, toggle);

    const strengthRow = document.createElement("div");
    strengthRow.className = "ct-cbgp-row ct-cbgp-frost-row";
    const strengthText = document.createElement("span");
    strengthText.className = "ct-cbgp-field-label";
    strengthText.textContent = strengthLabel;
    const controls = document.createElement("div");
    controls.className = "ct-cbgp-frost-controls";
    range.addEventListener("input", () => {
      updateRangeFill(range);
      const nextStrength = normalizeMaskOpacity(Number(range.value) / 100, strength);
      rangeValue.textContent = `${Math.round(nextStrength * 100)}%`;
      onStrengthChange(nextStrength);
    });
    controls.append(range, rangeValue);
    strengthRow.append(strengthText, controls);
    return [toggleRow, strengthRow];
  }

  function formatTime(ts, formatter) {
    if (!(Number.isFinite(ts) && ts > 0)) return "";
    const date = new Date(ts);
    if (!Number.isFinite(date.getTime())) return "";
    return formatter.format(date);
  }

  function timeFormatter(locale) {
    return new Intl.DateTimeFormat(locale, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  function kindLabel(kind, isChinese) {
    switch (kind) {
      case TRANSPARENT_BACKGROUND_KIND:
        return isChinese ? "透明背景" : "Transparent";
      case "alcy":
        return isChinese ? "内置" : "Built-in";
      case "url":
        return isChinese ? "固定 · 链接" : "Fixed · URL";
      case "local":
        return isChinese ? "固定 · 本地" : "Fixed · Local";
      default:
        return isChinese ? "无背景" : "None";
    }
  }

  function createHistoryCard(entry, formatTimeFn, isChinese) {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "ct-cbgp-history-card";
    const thumb = document.createElement("img");
    thumb.className = "ct-cbgp-history-thumb";
    thumb.alt = "";
    thumb.loading = "lazy";
    thumb.decoding = "async";
    const url = entry.kind === "local" ? entry.dataUrl : entry.url;
    const file = favoriteFor(entry)?.file || entry.file;
    if (file && entry.kind !== "local") {
      // Reuse an already decoded local file, or fall back to disk if an online thumbnail fails.
      const local = localURLs.get(file);
      if (local) local.then(src => { thumb.src = src; }).catch(() => { thumb.src = url; });
      else {
        thumb.addEventListener("error", () => {
          readFavorite(file).then(src => { if (thumb.isConnected) thumb.src = src; }).catch(() => {});
        }, { once: true });
        thumb.src = url;
      }
    } else thumb.src = url;
    const label = document.createElement("span");
    label.className = "ct-cbgp-history-label";
    label.textContent = formatTimeFn(entry.updatedAt);
    if (!label.textContent) label.textContent = kindLabel(entry.kind, isChinese);
    card.append(thumb, label);
    card.title = label.textContent;
    card.dataset.entryId = entry.id ?? "";
    card.setAttribute("aria-haspopup", "menu");
    card.addEventListener("click", () => restoreHistoryEntry(entry));
    card.addEventListener("contextmenu", (event) => openHistoryContextMenu(event, entry));
    card.addEventListener("keydown", (event) => {
      if (event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")) {
        openHistoryContextMenu(event, entry);
      }
    });
    card.setAttribute("aria-label", card.title);
    label.hidden = true;
    const active = url === currentSource();
    card.setAttribute("aria-pressed", String(active));
    const saved = Boolean(favoriteFor(entry));
    const star = toolButton(saved ? "★" : "☆", async () => {
      if (star.disabled) return;
      star.disabled = true;
      try {
        if (saved) {
          const previous = state.favorites;
          state.favorites = previous.filter(item => !sameImage(item, entry));
          if (!persistState()) { state.favorites = previous; throw Error("Local storage is full"); }
        } else {
          showActionToast(isChinese ? "正在下载收藏图片…" : "Downloading favorite…");
          const file = await saveFavoriteFile(entry);
          if (disposed || favoriteFor(entry)) return;
          const previous = state.favorites;
          state.favorites = [...previous, {...entry, file}];
          if (!persistState()) { state.favorites = previous; throw Error("Local storage is full"); }
          showActionToast(isChinese ? "已收藏到「图片/Packpier/收藏」。" : "Saved to Pictures/Packpier/收藏.", "success");
        }
        refreshSettingsPaneIfOpen();
      } catch (error) {
        showActionToast((isChinese ? "收藏更新失败：" : "Could not update favorite: ") + error.message, "error");
      } finally { star.disabled = false; }
    });
    star.className = "ct-cbgp-star";
    star.setAttribute("aria-pressed", String(saved));
    star.title = saved ? (isChinese ? "取消收藏" : "Remove favorite") : (isChinese ? "收藏图片" : "Favorite image");
    star.setAttribute("aria-label", star.title);
    const tile = document.createElement("div");
    tile.className = "ct-cbgp-tile";
    tile.append(card, star);
    return tile;
  }

  function fillImageGrid(grid, entries, formatTimeFn, isChinese) {
    let index = 0;
    const appendBatch = () => {
      const end = Math.min(index + 8, entries.length);
      while (index < end) grid.append(createHistoryCard(entries[index++], formatTimeFn, isChinese));
      if (index < entries.length) requestAnimationFrame(() => {
        if (grid.isConnected) appendBatch();
      });
    };
    appendBatch();
  }

  function renderSettingsPane(container) {
    if (disposed) return;
    closeOpenSettingsSelect();
    container.replaceChildren();
    const { locale, isChinese } = getLocaleStrings();
    const formatter = timeFormatter(locale);
    const formatTimeFn = ts => formatTime(ts, formatter);

    const header = document.createElement("header");
    header.className = "ct-cbgp-pane-header";
    const title = document.createElement("h1");
    title.textContent = isChinese ? SETTINGS_NAV_LABEL : "Custom background";
    header.append(title);
    container.append(header);
    const work = document.createElement("div");
    work.className = "ct-cbgp-work";
    const currentSection = document.createElement("div");
    const inspector = document.createElement("div");
    inspector.className = "ct-cbgp-inspector";
    work.append(currentSection, inspector);
    container.append(work);
    const preview = document.createElement("div");
    preview.className = "ct-cbgp-preview";
    preview.setAttribute("data-slot", "preview");
    const url = resolveBackgroundUrl();
    if (state.kind === TRANSPARENT_BACKGROUND_KIND) {
      preview.classList.add("ct-cbgp-transparent");
      preview.setAttribute("role", "img");
      preview.setAttribute(
        "aria-label",
        isChinese ? "透明背景预览" : "Transparent background preview",
      );
      preview.setAttribute(
        "data-empty-label",
        isChinese ? "透明背景" : "Transparent background",
      );
    } else if (!url) {
      preview.classList.add("ct-cbgp-empty");
      preview.setAttribute("data-empty-label", isChinese ? "无背景" : "No background");
    }
    applyPreviewBackground(preview, url);
    if (url) {
      for (const line of (isChinese ? ["帮我整理今天的设计反馈。", "先看看置顶会话的顺序。"] : ["Organize today’s feedback.", "Let’s check the pinned chats first."])) {
        const bubble = document.createElement("span");
        bubble.className = "ct-cbgp-bubble";
        bubble.textContent = line;
        preview.append(bubble);
      }
    }
    currentSection.append(preview);

    const currentInfo = document.createElement("div");
    currentInfo.className = "ct-cbgp-current-info";
    const kindSpan = document.createElement("span");
    kindSpan.className = "ct-cbgp-chip";
    kindSpan.textContent = kindLabel(state.kind, isChinese);
    currentInfo.append(kindSpan);
    if (state.kind === "alcy") {
      const shuffle = toolButton(isChinese ? "随机换一张" : "Shuffle image", applyRandom);
      shuffle.dataset.slot = "preview-shuffle";
      shuffle.disabled = document.documentElement.hasAttribute(IMAGE_JOB_MARKER);
      currentInfo.append(shuffle);
    }
    const atSpan = document.createElement("span");
    atSpan.className = "ct-cbgp-time";
    atSpan.textContent = formatTimeFn(state.updatedAt);
    if (atSpan.textContent) currentInfo.append(atSpan);
    currentSection.append(currentInfo);

    const maskSection = document.createElement("details");
    maskSection.className = "ct-cbgp-advanced";
    maskSection.open = advancedOpen;
    maskSection.addEventListener("toggle", () => { if (maskSection.isConnected) advancedOpen = maskSection.open; });
    const summary = document.createElement("summary");
    summary.textContent = isChinese ? "高级效果" : "Advanced effects";
    maskSection.append(summary);
    const themes = document.createElement("div");
    themes.className = "ct-cbgp-themes";
    let maskRow;
    function showTheme(theme) {
      previewTheme = theme;
      for (const button of themes.children) button.setAttribute("aria-pressed", String(button.dataset.theme === theme));
      const next = createMaskControlRow(theme, isChinese, preview, url);
      next.querySelector(".ct-cbgp-field-label").textContent = isChinese ? "遮罩强度" : "Mask strength";
      if (maskRow) maskRow.replaceWith(next);
      else inspector.append(next);
      maskRow = next;
      applyPreviewBackground(preview, url);
    }
    for (const [theme, label] of [["dark", isChinese ? "深色" : "Dark"], ["light", isChinese ? "浅色" : "Light"]]) {
      const button = toolButton(label, () => showTheme(theme));
      button.dataset.theme = theme;
      themes.append(button);
    }
    inspector.append(themes);
    showTheme(previewTheme);

    maskSection.append(
      ...createFrostControlRows({
        slotPrefix: "background-frost",
        enabled: state.backgroundFrostEnabled,
        strength: state.backgroundFrostStrength,
        toggleLabel: state.kind === TRANSPARENT_BACKGROUND_KIND
          ? isChinese ? "透明背景磨砂" : "Frost transparent background"
          : isChinese ? "背景图磨砂" : "Background image blur",
        strengthLabel: state.kind === TRANSPARENT_BACKGROUND_KIND
          ? isChinese ? "透明磨砂强度" : "Transparency frost strength"
          : isChinese ? "背景图磨砂强度" : "Background image blur strength",
        onEnabledChange: (enabled) => {
          state.backgroundFrostEnabled = enabled;
          applyPreviewBackground(preview, url);
          persistState();
          applyWallpaper();
        },
        onStrengthChange: (strength) => {
          state.backgroundFrostStrength = strength;
          applyPreviewBackground(preview, url);
          persistState();
          applyWallpaper();
        },
      }),
      ...createFrostControlRows({
        slotPrefix: "control-frost",
        enabled: state.frostEnabled,
        strength: state.frostStrength,
        toggleLabel: isChinese ? "界面控件磨砂" : "Frost interface controls",
        strengthLabel: isChinese ? "控件磨砂强度" : "Control frost strength",
        onEnabledChange: (enabled) => {
          state.frostEnabled = enabled;
          persistState();
          applyWallpaper();
        },
        onStrengthChange: (strength) => {
          state.frostStrength = strength;
          persistState();
          applyWallpaper();
        },
      }),
    );

    const maskNote = document.createElement("p");
    maskNote.className = "ct-cbgp-note";
    maskNote.textContent = state.kind === TRANSPARENT_BACKGROUND_KIND
      ? isChinese
        ? "遮罩颜色与强度用于给透明窗口增加底色；控件磨砂处理界面承载面，透明背景磨砂处理窗口底层。三种效果可以组合并立即应用。"
        : "Mask color and strength tint the transparent window. Control frost affects interface surfaces, while transparent background frost affects the window backdrop. All three combine and apply immediately."
      : isChinese
        ? "背景图磨砂会模糊壁纸，强度越高，壁纸越模糊。界面控件磨砂可单独调节。"
        : "Background image blur softens the wallpaper. Increase the strength for a softer image. You can adjust interface control blur separately.";
    maskSection.append(maskNote);
    const maskActions = document.createElement("div");
    maskActions.className = "ct-cbgp-actions";
    maskActions.append(
      toolButton(isChinese ? "恢复背景效果默认值" : "Restore appearance defaults", () => {
        state.maskLightColor = MASK_DEFAULTS.light.color;
        state.maskLightOpacity = MASK_DEFAULTS.light.opacity;
        state.maskDarkColor = MASK_DEFAULTS.dark.color;
        state.maskDarkOpacity = MASK_DEFAULTS.dark.opacity;
        state.frostEnabled = FROST_DEFAULTS.enabled;
        state.frostStrength = FROST_DEFAULTS.strength;
        state.backgroundFrostEnabled = BACKGROUND_FROST_DEFAULTS.enabled;
        state.backgroundFrostStrength = BACKGROUND_FROST_DEFAULTS.strength;
        persistState();
        applyWallpaper();
        refreshSettingsPaneIfOpen();
      }),
    );
    maskSection.append(maskActions);
    inspector.append(maskSection);

    const sourceSection = createSection(isChinese ? "背景来源" : "Background source");
    const selectRow = document.createElement("div");
    selectRow.className = "ct-cbgp-row";
    const selectTitle = document.createElement("span");
    selectTitle.className = "ct-cbgp-field-label";
    selectTitle.textContent = isChinese ? "来源类型" : "Source type";
    const kindOptions = [
      ["none", isChinese ? "无背景" : "No background"],
      [TRANSPARENT_BACKGROUND_KIND, isChinese ? "透明背景" : "Transparent background"],
      ["alcy", isChinese ? "内置图片" : "Built-in images"],
      ["local", isChinese ? "固定图片：本地文件" : "Fixed: local file"],
    ];
    const kindSelect = createSelectControl({
      slot: "kind-select",
      value: state.kind,
      options: kindOptions,
      ariaLabel: isChinese ? "背景来源类型" : "Background source type",
      unlistedLabel: isChinese ? "已保存的图片" : "Saved image",
      onChange: handleKindSelectChange,
    });
    selectRow.append(selectTitle, kindSelect);
    sourceSection.append(selectRow);

    const transparentNote = document.createElement("p");
    transparentNote.className = "ct-cbgp-note";
    transparentNote.setAttribute("data-slot", "transparent-note");
    transparentNote.hidden = state.kind !== TRANSPARENT_BACKGROUND_KIND;
    transparentNote.textContent = isChinese
      ? "透明背景会透出窗口后方内容，并保留颜色遮罩、界面控件磨砂和透明背景磨砂设置。"
      : "Transparent background reveals content behind the window while preserving the color mask, interface control frost, and transparent background frost settings.";
    sourceSection.append(transparentNote);

    const localRow = document.createElement("div");
    localRow.className = "ct-cbgp-row";
    localRow.hidden = state.kind !== "local";
    const localTitle = document.createElement("span");
    localTitle.className = "ct-cbgp-field-label";
    localTitle.textContent = isChinese ? "本地图片" : "Local image";
    const fileInput = document.createElement("input");
    fileInput.type = "file";
    fileInput.hidden = true;
    fileInput.accept = "image/*";
    fileInput.setAttribute("data-slot", "file-input");
    fileInput.addEventListener("change", () => {
      const file = fileInput.files?.[0];
      if (file) applyLocalFile(file);
    });
    const fileButton = toolButton(
      state.dataUrl
        ? isChinese ? "更换图片" : "Change image"
        : isChinese ? "选择图片" : "Choose image",
      () => {
        fileInput.value = "";
        fileInput.click();
      },
    );
    fileButton.setAttribute("data-slot", "file-button");
    localRow.append(localTitle, fileInput, fileButton);
    sourceSection.append(localRow);
    inspector.prepend(sourceSection);
    const favoritesSection = createSection(isChinese ? "收藏" : "Favorites");
    const favoriteGrid = document.createElement("div");
    favoriteGrid.className = "ct-cbgp-history-grid";
    favoriteGrid.dataset.slot = "favorites-grid";
    if (state.favorites.length) {
      fillImageGrid(favoriteGrid, state.favorites, formatTimeFn, isChinese);
    } else {
      const empty = document.createElement("p");
      empty.className = "ct-cbgp-note";
      empty.textContent = isChinese ? "点图片上的星标即可收藏。" : "Use the star on an image to save it here.";
      favoriteGrid.append(empty);
    }
    favoritesSection.append(favoriteGrid);
    container.append(favoritesSection);

    const historySection = createSection(
      isChinese ? "最近使用" : "Recently used",
    );
    const historyGrid = document.createElement("div");
    historyGrid.className = "ct-cbgp-history-grid";
    historyGrid.setAttribute("data-slot", "history-grid");
    if (state.history.length === 0) {
      const empty = document.createElement("p");
      empty.className = "ct-cbgp-note";
      empty.textContent = isChinese ? "暂无历史背景。" : "No history yet.";
      historyGrid.append(empty);
    } else {
      fillImageGrid(historyGrid, state.history, formatTimeFn, isChinese);
    }
    historySection.append(historyGrid);
    if (state.history.length > 0) {
      const historyActions = document.createElement("div");
      historyActions.className = "ct-cbgp-actions";
      historyActions.append(
        toolButton(isChinese ? "清空历史" : "Clear history", () => {
          openConfirmDialog({
            title: isChinese ? "清空历史" : "Clear history",
            message: isChinese
              ? `确定要清空全部 ${state.history.length} 张历史背景吗？此操作无法撤销。`
              : `Remove all ${state.history.length} history images? This cannot be undone.`,
            confirmLabel: isChinese ? "清空" : "Clear",
            cancelLabel: isChinese ? "取消" : "Cancel",
            onConfirm: clearHistory,
          });
        }),
      );
      historySection.append(historyActions);
    }
    container.append(historySection);

  }

  function createSettingsPane() {
    const pane = document.createElement("div");
    pane.setAttribute(PANEL_MARKER, "");
    renderSettingsPane(pane);
    return pane;
  }

  function detachSettingsPane(pane) {
    closeOpenSettingsSelect();
    pane?.remove();
    if (settingsPaneNode === pane) {
      settingsPaneNode = null;
      panelOpen = false;
      closeHistoryContextMenu();
      closeConfirmDialog();
    }
  }

  function mountSettingsPane(container) {
    if (disposed || !(container instanceof Element)) {
      throw new Error("自定义背景设置页面无法挂载");
    }
    if (settingsPaneNode) detachSettingsPane(settingsPaneNode);
    const pane = createSettingsPane();
    settingsPaneNode = pane;
    panelOpen = true;
    container.append(pane);
    return () => detachSettingsPane(pane);
  }

  function historyEntryImageSource(entry) {
    return entry?.kind === "local" ? entry.dataUrl : entry?.url;
  }

  function favoriteFor(entry) {
    return state.favorites.find(item => sameImage(item, entry));
  }

  function imageAction(action, entry) {
    const source = historyEntryImageSource(entry);
    return performImageAction(node, action, source, favoriteFor(entry)?.file || entry.file,
      entry.kind === "alcy" && isResolvedRandomImageUrl(source));
  }

  function saveFavoriteFile(entry) {
    const key = historyEntryImageSource(entry);
    if (!favoriteDownloads.has(key)) {
      const job = imageAction("favorite", entry).then(result => result.file)
        .finally(() => favoriteDownloads.delete(key));
      favoriteDownloads.set(key, job);
    }
    return favoriteDownloads.get(key);
  }

  function readFavorite(file) {
    if (!localURLs.has(file)) {
      const job = localImageURL(node, file).then(url => {
        if (disposed) { URL.revokeObjectURL(url); throw Error("Plugin unloaded"); }
        return url;
      }).catch(error => { localURLs.delete(file); throw error; });
      localURLs.set(file, job);
    }
    return localURLs.get(file);
  }

  async function restoreFavoriteFiles() {
    let failures = 0;
    for (const entry of [...state.favorites]) {
      if (disposed) return;
      if (entry.file || !favoriteFor(entry)) continue;
      try {
        const file = await saveFavoriteFile(entry);
        const item = favoriteFor(entry);
        if (disposed || !item) continue;
        item.file = file;
        if (!persistState()) { delete item.file; throw Error("Local storage is full"); }
      } catch { failures++; }
    }
    if (disposed) return;
    const source = currentSource();
    const active = state.favorites.find(item => historyEntryImageSource(item) === source);
    if (active?.file && active.kind !== "local") {
      try {
        const url = await readFavorite(active.file);
        if (!disposed && currentSource() === source) {
          currentLocal = {source, url};
          applyWallpaper();
        }
      } catch { /* The original URL is still available if the file was moved. */ }
    }
    refreshSettingsPaneIfOpen();
    if (failures) showActionToast(getLocaleStrings().isChinese
      ? `有 ${failures} 张旧收藏暂未下载，下次打开插件时会重试。`
      : `${failures} favorites could not be downloaded. They will be retried next time.`, "error");
  }

  function clearActionToast() {
    if (actionToastTimer !== null) window.clearTimeout(actionToastTimer);
    actionToastTimer = null;
    actionToastNode?.remove();
    actionToastNode = null;
  }

  function showActionToast(message, tone = "info") {
    if (disposed) return;
    clearActionToast();
    const toast = document.createElement("div");
    toast.className = "ct-cbgp-action-toast";
    toast.setAttribute("data-packpier-cbgp-action-toast", "");
    toast.setAttribute("data-tone", tone);
    toast.setAttribute("role", tone === "error" ? "alert" : "status");
    toast.setAttribute("aria-live", tone === "error" ? "assertive" : "polite");
    toast.textContent = message;
    document.body.append(toast);
    actionToastNode = toast;
    actionToastTimer = window.setTimeout(clearActionToast, ACTION_TOAST_DURATION_MS);
  }

  /* ----------------------------- 确认对话框 ----------------------------- */

  function openConfirmDialog({ title, message, confirmLabel, cancelLabel, onConfirm, returnFocusNode }) {
    if (disposed) return;
    closeConfirmDialog();
    confirmDialogReturnFocusNode =
      returnFocusNode ?? (document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null);
    const backdrop = document.createElement("div");
    backdrop.className = "ct-cbgp-confirm-backdrop";
    backdrop.setAttribute("data-packpier-cbgp-confirm-dialog", "");
    const dialog = document.createElement("div");
    dialog.className = "ct-cbgp-confirm-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-labelledby", "ct-cbgp-confirm-title");
    const titleEl = document.createElement("h3");
    titleEl.className = "ct-cbgp-confirm-title";
    titleEl.setAttribute("id", "ct-cbgp-confirm-title");
    titleEl.textContent = title;
    const messageEl = document.createElement("p");
    messageEl.className = "ct-cbgp-confirm-message";
    messageEl.textContent = message;
    const actions = document.createElement("div");
    actions.className = "ct-cbgp-confirm-actions";
    const cancelButton = document.createElement("button");
    cancelButton.type = "button";
    cancelButton.className = "ct-cbgp-confirm-button";
    cancelButton.textContent = cancelLabel;
    const confirmButton = document.createElement("button");
    confirmButton.type = "button";
    confirmButton.className =
      "ct-cbgp-confirm-button ct-cbgp-confirm-button-primary";
    confirmButton.textContent = confirmLabel;
    actions.append(cancelButton, confirmButton);
    dialog.append(titleEl, messageEl, actions);
    backdrop.append(dialog);
    document.body.append(backdrop);
    confirmDialogNode = backdrop;
    cancelButton.addEventListener("click", () => closeConfirmDialog(true));
    backdrop.addEventListener("pointerdown", (event) => {
      if (event.target === backdrop) closeConfirmDialog(true);
    });
    confirmButton.addEventListener("click", () => {
      closeConfirmDialog();
      onConfirm();
    });
    window.requestAnimationFrame(() => cancelButton.focus());
  }

  function closeConfirmDialog(restoreFocus = false) {
    const returnNode = confirmDialogReturnFocusNode;
    confirmDialogNode?.remove();
    confirmDialogNode = null;
    confirmDialogReturnFocusNode = null;
    if (restoreFocus && returnNode?.isConnected) {
      window.requestAnimationFrame(() => returnNode.focus());
    }
  }

  function openHistoryContextMenu(event, entry) {
    event.preventDefault();
    event.stopPropagation();
    if (historyActionPending || confirmDialogNode) return;
    closeHistoryContextMenu();
    const { isChinese } = getLocaleStrings();
    const menu = document.createElement("div");
    menu.className = "ct-cbgp-context-menu";
    menu.setAttribute("data-packpier-cbgp-context-menu", "");
    menu.setAttribute("role", "menu");
    menu.setAttribute("aria-label", isChinese ? "历史背景操作" : "History image actions");

    const createMenuItem = (label) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "ct-cbgp-context-item";
      item.setAttribute("role", "menuitem");
      item.textContent = label;
      return item;
    };
    const runImageAction = async ({ action, item, pendingLabel, successLabel, run }) => {
      if (historyActionPending) return;
      historyActionPending = true;
      const originalLabel = item.textContent;
      for (const button of menu.querySelectorAll("button")) button.disabled = true;
      item.textContent = pendingLabel;
      item.setAttribute("aria-busy", "true");
      showActionToast(pendingLabel);
      try {
        const result = await run();
        closeHistoryContextMenu(true);
        showActionToast(typeof successLabel === "function" ? successLabel(result) : successLabel, "success");
      } catch (error) {
        const label = action === "copy" ? (isChinese ? "复制失败" : "Copy failed") : (isChinese ? "保存失败" : "Save failed");
        showActionToast(label + " · " + error.message, "error");
      } finally {
        historyActionPending = false;
        item.textContent = originalLabel;
        item.removeAttribute("aria-busy");
        for (const button of menu.querySelectorAll("button")) button.disabled = false;
        if (menu.isConnected) item.focus();
      }
    };

    const copyItem = createMenuItem(isChinese ? "复制图片" : "Copy image");
    copyItem.addEventListener("click", () => runImageAction({
      action: "copy",
      item: copyItem,
      pendingLabel: isChinese ? "正在复制图片…" : "Copying image…",
      successLabel: isChinese ? "图片已复制。" : "Image copied.",
      run: () => imageAction("copy", entry),
    }));
    const saveItem = createMenuItem(isChinese ? "保存图片" : "Save image");
    saveItem.addEventListener("click", () => runImageAction({
      action: "save",
      item: saveItem,
      pendingLabel: isChinese ? "正在准备图片…" : "Preparing image…",
      successLabel: result => isChinese ? `已保存到「下载」：${result.file}` : `Saved to Downloads: ${result.file}`,
      run: () => imageAction("save", entry),
    }));

    menu.append(copyItem, saveItem);
    // The settings dialog owns the pointer and focus scope. The popover uses the viewport
    // as its containing block and still inherits CSS zoom from the settings pane.
    menu.popover = "manual";
    (settingsPaneNode || document.body).append(menu);
    menu.showPopover();
    const rect = menu.getBoundingClientRect();
    const trigger = event.currentTarget instanceof HTMLElement
      ? event.currentTarget
      : null;
    const triggerRect = trigger?.getBoundingClientRect();
    const eventHasPoint = Number.isFinite(event.clientX) && Number.isFinite(event.clientY) &&
      (event.clientX !== 0 || event.clientY !== 0);
    const anchorX = eventHasPoint ? event.clientX : (triggerRect?.left ?? 8) + 12;
    const anchorY = eventHasPoint ? event.clientY : (triggerRect?.bottom ?? 8) + 4;
    const margin = 8;
    const left = Math.max(margin, Math.min(anchorX, window.innerWidth - rect.width - margin));
    const top = Math.max(margin, Math.min(anchorY, window.innerHeight - rect.height - margin));
    const zoom = effectiveCSSZoom(menu);
    menu.style.left = `${left / zoom}px`;
    menu.style.top = `${top / zoom}px`;
    historyContextMenuNode = menu;
    historyContextMenuTriggerNode = trigger;
    window.requestAnimationFrame(() => {
      if (menu.isConnected) copyItem.focus();
    });
  }

  function closeHistoryContextMenu(restoreFocus = false) {
    const trigger = historyContextMenuTriggerNode;
    historyContextMenuNode?.remove();
    historyContextMenuNode = null;
    historyContextMenuTriggerNode = null;
    if (restoreFocus && trigger?.isConnected) {
      window.requestAnimationFrame(() => trigger.focus());
    }
  }

  function handleKindSelectChange(value) {
    if (value === "none") clearBackground();
    else if (value === "alcy") applyRandom();
    else if (
      value === TRANSPARENT_BACKGROUND_KIND || value === "local"
    ) {
      cancelPendingImageJob();
      state.backgroundEnabled = true;
      state.kind = value;
      if (value === TRANSPARENT_BACKGROUND_KIND) state.updatedAt = Date.now();
      persistState();
      applyWallpaper();
      refreshSettingsPaneIfOpen();
    }
  }

  function refreshSettingsPaneIfOpen() {
    if (!panelOpen || !settingsPaneNode?.isConnected) return;
    renderSettingsPane(settingsPaneNode);
  }

  function handleDocumentClick(event) {
    if (openSettingsSelect && !openSettingsSelect.root.contains(event.target)) {
      closeOpenSettingsSelect();
    }
    if (
      historyContextMenuNode &&
      !event.target?.closest?.('[data-packpier-cbgp-context-menu]')
    ) {
      closeHistoryContextMenu();
    }
  }

  function handleKeyDown(event) {
    if (confirmDialogNode) {
      const buttons = [...confirmDialogNode.querySelectorAll("button")];
      if (event.key === "Escape") {
        event.preventDefault();
        closeConfirmDialog(true);
      } else if (event.key === "Tab" && buttons.length) {
        const first = buttons[0];
        const last = buttons[buttons.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      } else if (!buttons.length) {
        return;
      }
      return;
    }
    if (openSettingsSelect && event.key === "Escape") {
      event.preventDefault();
      closeOpenSettingsSelect({ restoreFocus: true });
      return;
    }
    if (!historyContextMenuNode) return;
    if (event.key === "Escape") {
      event.preventDefault();
      closeHistoryContextMenu(true);
      return;
    }
    if (event.key === "Tab") {
      closeHistoryContextMenu();
      return;
    }
    const items = [...historyContextMenuNode.querySelectorAll(
      '.ct-cbgp-context-item:not(:disabled)',
    )];
    if (!items.length) return;
    const currentIndex = Math.max(0, items.indexOf(document.activeElement));
    let nextIndex = null;
    if (event.key === "ArrowDown") nextIndex = (currentIndex + 1) % items.length;
    else if (event.key === "ArrowUp") nextIndex = (currentIndex - 1 + items.length) % items.length;
    else if (event.key === "Home") nextIndex = 0;
    else if (event.key === "End") nextIndex = items.length - 1;
    if (nextIndex !== null) {
      event.preventDefault();
      items[nextIndex].focus();
    }
  }

  /* -------------------------------- 生命周期 ----------------------------- */

  function syncDOM() {
    if (disposed) return;
    if (!wallpaperNode?.isConnected) {
      applyWallpaper();
      return;
    }
    syncBackgroundLayout();
  }

  function scheduleDOMSync() {
    if (disposed || domSyncTimer !== null) return;
    domSyncTimer = window.setTimeout(() => {
      domSyncTimer = null;
      syncDOM();
    }, DOM_SYNC_DEBOUNCE_MS);
  }

  function handleDOMMutations(records) {
    if (!wallpaperNode?.isConnected ||
        (windowFrostNode && !windowFrostNode.isConnected)) {
      scheduleDOMSync();
      return;
    }
    for (const record of records) {
      if (record.type === "attributes") {
        scheduleDOMSync();
        return;
      }
      // 流式文本、工具结果、菜单和侧栏列表更新都不会改变页面壳。
      // 只检查本次增删的子树，不因此重新扫描页面或读取布局。
      for (const node of [...record.addedNodes, ...record.removedNodes]) {
        if (node instanceof Element &&
            (node.matches(PAGE_ANCHOR_SELECTOR) || node.querySelector(PAGE_ANCHOR_SELECTOR))) {
          scheduleDOMSync();
          return;
        }
      }
    }
  }

  function cleanup() {
    if (disposed) return;
    disposed = true;
    domObserver?.disconnect();
    domObserver = null;
    if (domSyncTimer !== null) {
      window.clearTimeout(domSyncTimer);
      domSyncTimer = null;
    }
    document.removeEventListener("click", handleDocumentClick);
    document.removeEventListener("keydown", handleKeyDown);
    window.removeEventListener("resize", scheduleDOMSync);
    window.visualViewport?.removeEventListener(
      "resize",
      scheduleDOMSync,
    );
    closeHistoryContextMenu();
    closeConfirmDialog();
    clearActionToast();
    for (const url of localURLs.values()) url.then(value => URL.revokeObjectURL(value)).catch(() => {});
    localURLs.clear();
    releaseNativeSettingsSection();
    closeOpenSettingsSelect();
    removeWallpaper();
    document.documentElement.removeAttribute(IMAGE_JOB_MARKER);
    if (runtimeHost[RUNTIME_KEY]?.cleanup === cleanup) {
      delete runtimeHost[RUNTIME_KEY];
    }
  }

  api.registerCleanup(cleanup);
  try {
    settingsSectionRegistration = ui?.settingsSections?.register({
      id: "custom-background",
      mount: mountSettingsPane,
    }) ?? null;
  } catch (error) {
    console.warn("自定义背景原生设置入口不可用", error);
  }
  domObserver = new MutationObserver(handleDOMMutations);
  domObserver.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-app-shell-active-page"],
  });
  domObserver.observe(runtimeHost, { attributes: true, attributeFilter: ["lang"] });

  document.addEventListener("click", handleDocumentClick);
  document.addEventListener("keydown", handleKeyDown);
  window.addEventListener("resize", scheduleDOMSync);
  window.visualViewport?.addEventListener(
    "resize",
    scheduleDOMSync,
  );
  runtimeHost[RUNTIME_KEY] = { cleanup };
  // 同步写回规范化结果：清理旧版本留下的“随机”占位历史，并保留所有
  // 仍指向确定图片地址的有效条目。
  persistState();
  syncDOM();
  void restoreFavoriteFiles();
  if (shouldRefreshLegacyRandom) {
    shouldRefreshLegacyRandom = false;
    applyRandom();
  }
}
