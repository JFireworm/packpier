// server/source.mjs
import { readFile } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { DatabaseSync } from "node:sqlite";
async function readCodexSnapshot(root = process.env.PRISM_CODEX_HOME || path.join(os.homedir(), ".codex"), requestedThreadKey, getProjectThreadKeys) {
  const state = JSON.parse(await readFile(path.join(root, ".codex-global-state.json"), "utf8"));
  const owners = Object.entries(state).filter(([k]) => k.startsWith("electron-owner-atoms:"));
  const owner = owners.find(([k]) => k.slice("electron-owner-atoms:".length) === state["electron-renderer-content-owner"]) || (owners.length === 1 ? owners[0] : null);
  if (!owner) throw new Error("\u65E0\u6CD5\u786E\u5B9A\u5F53\u524D Codex \u8D26\u6237\uFF0C\u5DF2\u505C\u6B62\u540C\u6B65\uFF0C\u907F\u514D\u6DF7\u5165\u5176\u4ED6\u8D26\u6237\u6570\u636E");
  const atoms = owner[1];
  const pins = atoms["app-server-pinned-thread-order-v1"];
  if (!Array.isArray(pins) || !pins.every((x) => typeof x === "string")) throw new Error("\u5F53\u524D Codex \u7F6E\u9876\u6570\u636E\u683C\u5F0F\u4E0D\u53D7\u652F\u6301");
  const account = owner[0].slice("electron-owner-atoms:".length);
  const projectThreadKeys = getProjectThreadKeys ? await getProjectThreadKeys(account) : [];
  const catalog = new DatabaseSync(path.join(root, "sqlite", "codex.db"), { readOnly: true });
  const legacy = new DatabaseSync(path.join(root, "state_5.sqlite"), { readOnly: true });
  try {
    const lookup = catalog.prepare("SELECT display_title, cwd, project_id FROM local_thread_catalog WHERE thread_id=? AND host_id=?");
    const fallback = legacy.prepare("SELECT name, cwd, archived FROM threads WHERE id=?");
    const assignments = state["thread-project-assignments"] || {};
    const rawProjects = state["local-projects"] || {};
    const appearances = state["project-appearances"] || {};
    const projectOrder = atoms["unified-sidebar-project-order-v1"] || [];
    const nativeToLegacy = /* @__PURE__ */ new Map();
    for (const mappings of Object.values(state["app-server-project-id-by-legacy-project-id-by-host"] || {})) {
      for (const [id, native] of Object.entries(mappings)) nativeToLegacy.set(native, id);
    }
    const projects = Object.entries(rawProjects).map(([id, p]) => ({ id, name: appearances[id]?.name || p.name || id, path: p.rootPaths?.[0] || "" }));
    projects.sort((a, b) => (projectOrder.indexOf("codex:project:" + a.id) < 0 ? 1e9 : projectOrder.indexOf("codex:project:" + a.id)) - (projectOrder.indexOf("codex:project:" + b.id) < 0 ? 1e9 : projectOrder.indexOf("codex:project:" + b.id)));
    const resolveProject = (id, row, old) => assignments[id]?.projectId || nativeToLegacy.get(row?.project_id) || row?.project_id || projects.find((p) => p.path === (row?.cwd || old?.cwd))?.id || null;
    const missing = [];
    const threads = [...new Set(pins)].flatMap((id, index) => {
      const row = lookup.get(id, "local");
      const old = fallback.get(id);
      if (old?.archived) return [];
      const title = row?.display_title || old?.name;
      if (!title) {
        missing.push(id);
        return [];
      }
      const projectId = resolveProject(id, row, old);
      return [{ id, kind: "codex", hostId: "local", title, projectId, nativeIndex: index + 1 }];
    });
    const snapshot = { threads, projects, projectAliases: Object.fromEntries(nativeToLegacy), syncedAt: (/* @__PURE__ */ new Date()).toISOString(), source: "codex-local-readonly", missingCount: missing.length, scope: "local", account };
    const prefix = "codex:thread:local:";
    if (getProjectThreadKeys) {
      const pinnedIds = new Set(threads.map((t) => t.id));
      const threadProjects = Object.fromEntries(threads.map((t) => [prefix + t.id, t.projectId]));
      const projectRow = catalog.prepare("SELECT project_id,cwd FROM local_thread_catalog WHERE thread_id=? AND host_id=?");
      const legacyLocation = legacy.prepare("SELECT cwd FROM threads WHERE id=? AND archived=0");
      for (const key of new Set(projectThreadKeys)) {
        if (!key.startsWith(prefix)) continue;
        const id = key.slice(prefix.length);
        if (!id || pinnedIds.has(id)) continue;
        const row = projectRow.get(id, "local");
        threadProjects[key] = resolveProject(id, row, row?.cwd ? null : legacyLocation.get(id));
      }
      snapshot.threadProjects = threadProjects;
    }
    if (typeof requestedThreadKey === "string" && requestedThreadKey.startsWith(prefix)) {
      const id = requestedThreadKey.slice(prefix.length);
      if (id && !pins.includes(id)) {
        const old = legacy.prepare("SELECT archived FROM threads WHERE id=?").get(id);
        if (!old?.archived && (old || catalog.prepare("SELECT 1 FROM local_thread_catalog WHERE thread_id=? AND host_id=?").get(id, "local"))) snapshot.editableThreadKey = requestedThreadKey;
      }
    }
    return snapshot;
  } finally {
    catalog.close();
    legacy.close();
  }
}

// server/store.mjs
import { readFile as readFile2, writeFile, mkdir, rename } from "node:fs/promises";
import path2 from "node:path";
import { fileURLToPath } from "node:url";

// src/model.mjs
var PALETTE = [
  "#62A1FF",
  "#8C87FF",
  "#B47BFA",
  "#EF79E5",
  "#FF79A9",
  "#FF746F",
  "#FFA153",
  "#FFD059",
  "#E0EE69",
  "#A7E85D",
  "#69DA83",
  "#4FDCB4",
  "#44DDD9",
  "#56D4FA",
  "#F2B68B",
  "#A9C1E1"
];
var MODES = ["all", "project", "custom"];
var emptyPreferences = () => ({ version: 1, mode: "all", colors: {}, threadColorModes: {}, recentColors: [], inheritance: {}, groups: [], assignments: {}, order: [] });
var threadKey = (t) => `${t.kind || "codex"}:thread:${t.hostId || "local"}:${t.id}`;
var projectKey = (id) => `project:${id}`;
function applyColorEdit(prefs, op) {
  if (op.value !== null && (typeof op.value !== "string" || !/^#[0-9a-f]{6}$/i.test(op.value))) {
    throw new Error("\u8BF7\u8F93\u5165\u516D\u4F4D\u5341\u516D\u8FDB\u5236\u989C\u8272");
  }
  const color = op.value?.toUpperCase();
  if (op.type === "preset-color") {
    if (!color || !Number.isInteger(op.slot) || op.slot < 0 || op.slot >= PALETTE.length) throw new Error("\u65E0\u6548\u7684\u9884\u8BBE\u8272\u683C");
    const palette = [...prefs.presetColors ?? PALETTE];
    palette[op.slot] = color;
    prefs.presetColors = palette;
    return;
  }
  const isProject = op.key.startsWith("project:");
  if (op.source !== void 0 && (isProject || color || !["default", "project"].includes(op.source))) throw new Error("\u65E0\u6548\u7684\u989C\u8272\u6765\u6E90");
  if (color) prefs.colors[op.key] = color;
  else delete prefs.colors[op.key];
  if (isProject) {
    if (typeof op.inherit === "boolean") prefs.inheritance[op.key.slice(8)] = op.inherit;
  } else if (op.source || prefs.threadColorModes?.[op.key]) {
    prefs.threadColorModes = { ...prefs.threadColorModes };
    if (op.source) prefs.threadColorModes[op.key] = op.source;
    else delete prefs.threadColorModes[op.key];
  }
  if (color) {
    prefs.recentColors = [color, ...(prefs.recentColors ?? []).filter((item) => item !== color)].slice(0, 6);
  }
}
function applyOperation(previous, op, snapshot) {
  const p = structuredClone(previous);
  const currentKeys = new Set(snapshot.threads.map(threadKey));
  const projectIds = new Set(snapshot.projects.map((x) => x.id));
  const assert = (ok, msg) => {
    if (!ok) throw new Error(msg);
  };
  const validName = (name) => typeof name === "string" && name.trim().length > 0 && name.trim().length <= 40;
  switch (op.type) {
    case "mode":
      assert(MODES.includes(op.value), "\u65E0\u6548\u7684\u5C55\u793A\u65B9\u5F0F");
      p.mode = op.value;
      break;
    case "preset-color":
      applyColorEdit(p, op);
      break;
    case "color": {
      assert(currentKeys.has(op.key) || typeof op.key === "string" && op.key === snapshot.editableThreadKey || [...projectIds].some((id) => projectKey(id) === op.key), "\u6761\u76EE\u5DF2\u79FB\u51FA\u6392\u884C\u699C\uFF0C\u8BF7\u5237\u65B0");
      applyColorEdit(p, op);
      break;
    }
    case "group-add":
      assert(validName(op.name), "\u5206\u7EC4\u540D\u9700\u8981 1 \u81F3 40 \u4E2A\u5B57\u7B26");
      assert(p.groups.length < 30, "\u6700\u591A\u652F\u6301 30 \u4E2A\u5206\u7EC4");
      assert(!p.groups.some((g) => g.name === op.name.trim()), "\u5DF2\u5B58\u5728\u540C\u540D\u5206\u7EC4");
      p.groups.push({ id: op.id || crypto.randomUUID(), name: op.name.trim() });
      break;
    case "group-rename": {
      assert(validName(op.name), "\u5206\u7EC4\u540D\u9700\u8981 1 \u81F3 40 \u4E2A\u5B57\u7B26");
      const g = p.groups.find((x) => x.id === op.id);
      assert(g, "\u5206\u7EC4\u4E0D\u5B58\u5728");
      assert(!p.groups.some((x) => x.id !== op.id && x.name === op.name.trim()), "\u5DF2\u5B58\u5728\u540C\u540D\u5206\u7EC4");
      g.name = op.name.trim();
      break;
    }
    case "group-remove":
      p.groups = p.groups.filter((g) => g.id !== op.id);
      for (const key of Object.keys(p.assignments)) if (p.assignments[key] === op.id) delete p.assignments[key];
      break;
    case "assign":
      assert(currentKeys.has(op.key), "\u4F1A\u8BDD\u5DF2\u53D6\u6D88\u7F6E\u9876");
      assert(op.groupId === null || p.groups.some((g) => g.id === op.groupId), "\u5206\u7EC4\u4E0D\u5B58\u5728");
      if (op.groupId === null) delete p.assignments[op.key];
      else p.assignments[op.key] = op.groupId;
      break;
    case "order":
      assert(Array.isArray(op.keys) && op.keys.length === currentKeys.size && new Set(op.keys).size === currentKeys.size && op.keys.every((k) => currentKeys.has(k)), "\u7F6E\u9876\u5217\u8868\u5DF2\u53D8\u5316\uFF0C\u8BF7\u5237\u65B0\u540E\u91CD\u65B0\u6392\u5E8F");
      p.order = [...op.keys];
      break;
    case "native-order":
      p.order = [];
      break;
    default:
      throw new Error("\u672A\u77E5\u64CD\u4F5C");
  }
  return p;
}

// server/store.mjs
var PreferenceStore = class {
  constructor(directory = process.env.PLUGIN_DATA || process.env.PRISM_DATA_DIR || path2.resolve(path2.dirname(fileURLToPath(import.meta.url)), "../data")) {
    this.directory = directory;
    this.queue = Promise.resolve();
  }
  filename(account) {
    if (!/^[a-zA-Z0-9_-]{1,128}$/.test(account)) throw new Error("\u65E0\u6548\u8D26\u6237\u6807\u8BC6");
    return path2.join(this.directory, `preferences-${account}.json`);
  }
  async read(account) {
    try {
      const data = JSON.parse(await readFile2(this.filename(account), "utf8"));
      if (data.version !== 1) throw new Error("\u4E0D\u652F\u6301\u7684\u504F\u597D\u7248\u672C");
      return { threadColorModes: {}, recentColors: [], ...data };
    } catch (e) {
      if (e.code === "ENOENT") return emptyPreferences();
      throw e;
    }
  }
  update(op, snapshot) {
    const action = this.queue.then(async () => {
      const result = applyOperation(await this.read(snapshot.account), op, snapshot);
      await mkdir(this.directory, { recursive: true, mode: 448 });
      const name = this.filename(snapshot.account);
      const temp = name + "." + crypto.randomUUID() + ".tmp";
      await writeFile(temp, JSON.stringify(result, null, 2), { mode: 384 });
      await rename(temp, name);
      return result;
    });
    this.queue = action.catch(() => {
    });
    return action;
  }
};

import { watch } from "node:fs";
import { readFile as readFile3 } from "node:fs/promises";
import path3 from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

function resolveLanguage(preference, preferred = []) {
  if (["zh-CN", "zh-TW", "en", "ja", "ko"].includes(preference)) return preference;
  for (const tag of preferred) {
    const [language, ...parts] = tag.trim().toLowerCase().replaceAll("_", "-").split("-");
    if (language === "zh") {
      for (const part of parts) {
        if (["hant", "tw", "hk", "mo"].includes(part)) return "zh-TW";
        if (part === "hans") break;
      }
      return "zh-CN";
    }
    if (["en", "ja", "ko"].includes(language)) return language;
  }
  return "en";
}

var run = promisify(execFile);
async function systemLanguages() {
  if (process.platform === "darwin") {
    for (const domain of ["com.zgccrui.CodexTweaks", "-g"]) {
      try {
        const { stdout } = await run("/usr/bin/defaults", ["read", domain, "AppleLanguages"], { timeout: 1500 });
        const tags = stdout.match(/[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]+)*/g);
        if (tags?.length) return tags;
      } catch {
      }
    }
  }
  return [Intl.DateTimeFormat().resolvedOptions().locale];
}
function hostLanguage(dataDirectory, onChange) {
  const dir = path3.resolve(dataDirectory, "../..");
  let current, previousPreference, timer, watcher, stopped = false, revision = 0;
  async function read() {
    const version = ++revision;
    let preference;
    try {
      preference = JSON.parse(await readFile3(path3.join(dir, "app-state.json"), "utf8")).language;
    } catch (error) {
      if (current && error.code !== "ENOENT") return current;
    }
    if (current && preference === previousPreference) return current;
    const auto = !preference || preference === "auto";
    const next = resolveLanguage(preference, auto ? await systemLanguages() : []);
    if (!stopped && version === revision) {
      const changed = current !== void 0 && next !== current;
      previousPreference = preference;
      current = next;
      if (changed) onChange();
    }
    return current ?? next;
  }
  const initial = read();
  try {
    watcher = watch(dir, { persistent: false }, (_, name) => {
      if (name && name !== "app-state.json") return;
      clearTimeout(timer);
      timer = setTimeout(() => {
        void read();
      }, 70);
    });
    watcher.on("error", () => watcher.close());
  } catch {
  }
  return { get: () => current ?? initial, close() {
    stopped = true;
    clearTimeout(timer);
    watcher?.close();
  } };
}

function sidebarSnapshot({ account, threads, projects, projectAliases, threadProjects }, preferences, language) {
  return {
    account,
    projectAliases,
    threadProjects,
    language,
    preferences: { ...preferences, mode: preferences.mode === "project" ? "project" : "all" },
    threads: threads.map(({ id, kind, hostId, projectId, nativeIndex }) => ({ id, kind, hostId, projectId, nativeIndex })),
    projects: projects.map(({ id, name }) => ({ id, name }))
  };
}
function activate({ rpc, dataDirectory }) {
  const store = new PreferenceStore(dataDirectory);
  const language = hostLanguage(dataDirectory, () => rpc.emit("changed", {}));
  async function readState(operation) {
    let preferences;
    const editKey = operation?.type === "color" ? operation.key : void 0;
    const current = await readCodexSnapshot(void 0, editKey, async (account) => {
      preferences = await store.read(account);
      const keys = Object.keys(preferences.threadColorModes).filter((key) => preferences.threadColorModes[key] === "project" && !preferences.colors[key]);
      if (editKey && operation.source === "project") keys.push(editKey);
      return keys;
    });
    return { current, preferences };
  }
  rpc.handle("snapshot", async () => {
    const { current, preferences } = await readState();
    return sidebarSnapshot(current, preferences, await language.get());
  });
  rpc.handle("update", async ({ account, operation, origin }) => {
    if (!["color", "preset-color"].includes(operation.type) && !(operation.type === "mode" && ["all", "project"].includes(operation.value))) {
      throw new Error("\u65E0\u6548\u7684\u4FA7\u680F\u8BBE\u7F6E");
    }
    const { current } = await readState(operation);
    if (current.account !== account) throw new Error("Codex \u8D26\u6237\u5DF2\u5207\u6362\uFF0C\u8BF7\u91CD\u65B0\u9009\u62E9");
    const preferences = await store.update(operation, current);
    rpc.emit("changed", { origin });
    return sidebarSnapshot(current, preferences, await language.get());
  });
  return language.close;
}
export {
  activate
};
