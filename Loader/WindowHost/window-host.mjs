// Packpier window host: connects the loader to Codex's local DevTools endpoint,
// injects the first-party renderer bundle, and bridges it to the packages' Node entries.
import { readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { builtinEntry, permittedMethod, mainPage, verifiedTarget, summarize } from "./policy.mjs";

const run = promisify(execFile);
const verifier = fileURLToPath(new URL("../../Helpers/packpier-codex-loader", import.meta.url));
async function listenerOwner() {
  try {
    const { stdout } = await run(verifier, ["--verify-codex-listener"], { timeout: 2500 });
    const pid = stdout.trim();
    return /^[1-9][0-9]*$/.test(pid) ? pid : null;
  } catch { return null; }
}
import readline from "node:readline";

const VERSION = "packpier-window-5";
const args = process.argv.slice(2);
const option = name => {
  const index = args.indexOf("--" + name);
  return index >= 0 ? args[index + 1] : undefined;
};
const PORT = 9335;
const BUNDLE = option("bundle");
const HOST_VERSION = option("host-version") ?? "packpier";

let bundleCode = "";
let state = { enabled: false, packages: [] };
let lastReport = "";
let shuttingDown = false;

const handlers = new Map();          // "packageID|method" -> function
const services = new Map();          // packageID -> { directory, dataDirectory, cleanup, rpc }
const sessions = new Map();          // webSocketDebuggerUrl -> PageSession
const errors = new Map();            // packageID -> message

function log(message) {
  process.stderr.write(`[packpier-host] ${message}\n`);
}

function report(extra = {}) {
  let kind = "disabled";
  if (state.enabled) {
    if (![...sessions.values()].some(session => session.confirmed)) kind = portOpen ? "waitingForPage" : "waitingForCDP";
    else kind = "connected";
  }
  const data = {
    kind,
    version: HOST_VERSION,
    ...summarize(state.packages, state.enabled ? sessions.values() : [], errors),
    ...extra,
  };
  const line = JSON.stringify({ event: "windowState", data });
  if (line === lastReport) return;
  lastReport = line;
  process.stdout.write(line + "\n");
}

let owner = null;
let portOpen = false;

/* ----------------------------- page state ----------------------------- */

function pageState() {
  return {
    enabled: state.enabled,
    packages: state.packages.map(({ id }) => ({ id })),
    disabledPackageIDs: [],
  };
}

/* ------------------------------ CDP client ---------------------------- */

class PageSession {
  constructor(target, pid) {
    this.id = target.id;
    this.url = target.webSocketDebuggerUrl;
    this.pid = pid;
    this.confirmed = false;
    this.result = null;
    this.contexts = new Map();
    this.mainFrame = null;
    this.pending = new Map();
    this.sequence = 0;
    this.closed = false;
    this.ready = this.open();
  }

  open() {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(this.url);
      this.socket = socket;
      socket.addEventListener("message", event => this.receive(event));
      socket.addEventListener("close", () => {
        this.closed = true;
        for (const { reject: fail } of this.pending.values()) fail(new Error("Codex page closed"));
        this.pending.clear();
        if (sessions.get(this.url) === this) sessions.delete(this.url);
        report();
      });
      socket.addEventListener("error", () => { /* close follows */ });
      socket.addEventListener("open", async () => {
        if (await listenerOwner() === this.pid && !this.closed) resolve();
        else { this.socket.close(); reject(new Error("Codex listener ownership changed")); }
      });
      setTimeout(() => { if (socket.readyState !== WebSocket.OPEN) reject(new Error("Codex page timed out")); }, 5000);
    });
  }

  receive(event) {
    let message;
    try { message = JSON.parse(event.data); } catch { return; }
    if (message.id && this.pending.has(message.id)) {
      const entry = this.pending.get(message.id);
      this.pending.delete(message.id);
      clearTimeout(entry.timer);
      if (message.error) entry.reject(new Error(message.error.message ?? "CDP error"));
      else entry.resolve(message.result ?? {});
      return;
    }
    const params = message.params ?? {};
    if (message.method === "Runtime.executionContextCreated") {
      const c = params.context;
      if (c?.origin === "app://-" && c.auxData?.isDefault)
        this.contexts.set(c.id, { frame: c.auxData.frameId, unique: c.uniqueId });
    } else if (message.method === "Runtime.executionContextDestroyed") {
      this.contexts.delete(params.executionContextId);
    } else if (message.method === "Runtime.executionContextsCleared" ||
               (message.method === "Page.frameNavigated" && !params.frame?.parentId)) {
      this.mainFrame = null;
      this.confirmed = false;
      this.result = null;
      if (message.method === "Runtime.executionContextsCleared") this.contexts.clear();
      report();
    } else if (message.method === "Runtime.bindingCalled" && params.name === "__packpierRpc" &&
               this.isMainContext(params.executionContextId)) {
      this.handleCall(params.payload, this.contexts.get(params.executionContextId).unique);
    }
  }

  isMainContext(id) {
    const context = this.contexts.get(id);
    return state.enabled && !this.closed && sessions.get(this.url) === this &&
      this.pid === owner && this.mainFrame && context?.frame === this.mainFrame && context.unique;
  }

  closeEffects() {
    if (this.closed || !this.mainFrame || this.pid !== owner) return Promise.resolve();
    const main = [...this.contexts.values()].find(context => context.frame === this.mainFrame && context.unique);
    return main ? this.evaluate("globalThis.__PACKPIER__?.close()", main.unique).catch(() => {}) : Promise.resolve();
  }

  send(method, params = {}, timeout = 15000) {
    if (this.closed) return Promise.reject(new Error("Codex page closed"));
    const id = ++this.sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP ${method} timed out`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  evaluate(expression, uniqueContextId) {
    return this.send("Runtime.evaluate", { expression, uniqueContextId, returnByValue: true, awaitPromise: true });
  }

  async handleCall(payload, context) {
    if (typeof payload !== "string" || payload.length > 131072) return;
    let request;
    try { request = JSON.parse(payload); } catch { return; }
    if (!request || !Number.isSafeInteger(request.id) || !state.packages.some(p => p.id === request.plugin) ||
        !permittedMethod(request.plugin, request.method)) return;
    const key = request.plugin + "|" + request.method;
    try {
      const handler = handlers.get(key);
      if (!handler) throw new Error(`No Packpier service for ${key}`);
      const value = await handler(request.parameters ?? {});
      await this.evaluate(`globalThis.__packpierResolve(${JSON.stringify(String(request.id))}, true, ${JSON.stringify(value ?? null)})`, context);
    } catch (error) {
      const message = String(error?.message ?? error);
      try {
        await this.evaluate(`globalThis.__packpierResolve(${JSON.stringify(String(request.id))}, false, ${JSON.stringify({ message })})`, context);
      } catch {}
    }
  }
}

async function listTargets() {
  portOpen = false;
  owner = await listenerOwner();
  if (!owner) return [];
  try {
    const response = await fetch(`http://127.0.0.1:${PORT}/json/list`, {
      signal: AbortSignal.timeout(2000), redirect: "error",
    });
    if (!response.ok) return [];
    const targets = await response.json();
    portOpen = true;
    return Array.isArray(targets) ? targets.filter(verifiedTarget) : [];
  } catch {
    portOpen = false;
    return [];
  }
}

async function ensureSessions() {
  const targets = await listTargets();
  const live = new Set();
  for (const target of targets) {
    live.add(target.webSocketDebuggerUrl);
    const prior = sessions.get(target.webSocketDebuggerUrl);
    if (prior && prior.pid !== owner) { prior.socket.close(); sessions.delete(prior.url); }
    if (!sessions.has(target.webSocketDebuggerUrl)) {
      const session = new PageSession(target, owner);
      sessions.set(target.webSocketDebuggerUrl, session);
      session.ready.catch(error => {
        log("page connect failed: " + error.message);
        if (sessions.get(session.url) === session) sessions.delete(session.url);
        session.socket.close();
      });
    }
  }
  for (const url of [...sessions.keys()]) {
    if (!live.has(url)) { sessions.get(url)?.socket?.close(); sessions.delete(url); }
  }
}

async function injectAll() {
  if (!bundleCode) return;
  for (const session of [...sessions.values()]) {
    try {
      await session.ready;
      await session.send("Page.enable", {}, 5000);
      await session.send("Runtime.enable", {}, 5000);
      const { frameTree } = await session.send("Page.getFrameTree", {}, 5000);
      if (!mainPage(frameTree?.frame?.url)) throw new Error("Unverified main window");
      session.mainFrame = frameTree.frame.id;
      const context = [...session.contexts.keys()].find(id => session.isMainContext(id));
      if (context === undefined) throw new Error("Waiting for a verified window context");
      const unique = session.contexts.get(context).unique;
      await session.send("Runtime.addBinding", { name: "__packpierRpc" }, 5000);
      const expression = `(() => {
        const state = ${JSON.stringify(pageState())};
        if (globalThis.__PACKPIER__ && globalThis.__PACKPIER__.version === ${JSON.stringify(VERSION)}) {
          return globalThis.__PACKPIER__.apply(state);
        }
        globalThis.__PACKPIER__?.close();
        ${bundleCode}
        const result = globalThis.__PACKPIER__.apply(state);
        return { mounted: result.mounted, errors: result.errors };
      })()`;
      const reply = await session.evaluate(expression, unique);
      if (reply.exceptionDetails) throw new Error(reply.exceptionDetails.text || "Window activation failed");
      const result = reply.result?.value;
      if (!Array.isArray(result?.mounted) || !session.isMainContext(context)) throw new Error("Unconfirmed window state");
      const wanted = state.packages.map(p => p.id);
      const problems = Object.fromEntries(Object.entries(result.errors ?? {}).filter(([id]) => wanted.includes(id)));
      if (result.errors?.runtime) for (const id of wanted) problems[id] = String(result.errors.runtime);
      session.result = { mounted: wanted.filter(id => result.mounted.includes(id)), errors: problems };
      session.confirmed = true;
    } catch (error) {
      session.mainFrame = null;
      session.confirmed = false;
      session.result = { mounted: [], errors: Object.fromEntries(state.packages.map(p => [p.id, error.message])) };
      log("inject failed: " + error.message);
    }
  }
  report();
}

/* ---------------------------- node services --------------------------- */

async function startServices(packages) {
  const wanted = new Map(packages.filter(p => builtinEntry(p.id)).map(p => [p.id, p]));
  for (const [id, service] of [...services]) {
    const next = wanted.get(id);
    if (!next || next.dataDirectory !== service.dataDirectory) {
      try { await service.cleanup?.(); } catch {}
      services.delete(id);
      for (const key of [...handlers.keys()]) if (key.startsWith(id + "|")) handlers.delete(key);
    }
  }
  for (const [id, pkg] of wanted) {
    if (services.has(id)) continue;
    try {
      const rpc = createRPC(id);
      const module = await import(builtinEntry(id).href);
      const cleanup = await module.activate({ rpc, dataDirectory: pkg.dataDirectory });
      services.set(id, { dataDirectory: pkg.dataDirectory, cleanup, rpc });
    } catch (error) {
      errors.set(id, String(error?.message ?? error));
      log(`service ${id} failed: ${error?.message ?? error}`);
    }
  }
}

function createRPC(id) {
  return {
    handle(method, fn) { if (permittedMethod(id, method)) handlers.set(id + "|" + method, fn); },
    emit(name, payload) {
      for (const session of [...sessions.values()]) {
        const context = [...session.contexts.keys()].find(key => session.isMainContext(key));
        if (context === undefined) continue;
        session.evaluate(`globalThis.__packpierEvent && globalThis.__packpierEvent(${JSON.stringify(id)}, ${JSON.stringify(name)}, ${JSON.stringify(payload ?? null)})`, session.contexts.get(context).unique).catch(() => {});
      }
    },
  };
}

/* ------------------------------- main loop ---------------------------- */

async function apply(input) {
  state = {
    enabled: input.enabled === true,
    packages: Array.isArray(input.packages) ? input.packages : [],
  };
  errors.clear();
  if (!state.enabled) {
    for (const service of services.values()) { try { await service.cleanup?.(); } catch {} }
    services.clear();
    handlers.clear();
    await Promise.allSettled([...sessions.values()].map(session => session.closeEffects()));
    for (const session of sessions.values()) session.socket.close();
    sessions.clear();
    report();
    return;
  }
  await startServices(state.packages);
  await ensureSessions();
  await injectAll();
}

let syncing = false;
let pendingPlan;
async function refresh(plan) {
  if (plan) pendingPlan = plan;
  if (syncing || shuttingDown) return;
  syncing = true;
  try {
    do {
      const next = pendingPlan;
      pendingPlan = undefined;
      if (next) await apply(next);
      else if (state.enabled) { await ensureSessions(); await injectAll(); }
    } while (pendingPlan && !shuttingDown);
  } finally { syncing = false; }
}

async function main() {
  try {
    bundleCode = await readFile(BUNDLE, "utf8");
  } catch (error) {
    log("cannot read renderer bundle: " + error.message);
    bundleCode = "";
  }
  const lines = readline.createInterface({ input: process.stdin });
  lines.on("line", line => {
    let message;
    try { message = JSON.parse(line); } catch { return; }
    if (message.type === "sync") {
      refresh(message).catch(error => log("sync failed: " + error.message));
    } else if (message.type === "shutdown") {
      shutdown();
    }
  });
  lines.on("close", shutdown);
  setInterval(() => {
    if (shuttingDown || !state.enabled) return;
    refresh().catch(error => log("refresh failed: " + error.message));
  }, 2000);
  report();
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  const done = () => process.exit(0);
  state.enabled = false;
  Promise.allSettled([
    ...[...sessions.values()].map(session => session.closeEffects()),
    ...[...services.values()].map(service => service.cleanup?.()),
  ]).finally(done);
  setTimeout(done, 500);
}

main().catch(error => { log("fatal: " + error.message); process.exit(1); });
