import assert from "node:assert/strict";
import { builtinEntry, verifiedTarget, permittedMethod, summarize } from "../Loader/WindowHost/policy.mjs";
import { activate } from "../Plugins/CustomBackground/src/node.js";

const target = { type: "page", id: "A1", url: "app://-/index.html", webSocketDebuggerUrl: "ws://127.0.0.1:9335/devtools/page/A1" };
assert.ok(verifiedTarget(target));
for (const overrides of [
  { url: "app://-/index.html.extra" }, { type: "other" }, { url: "app://-/index.html?view=avatar-overlay" },
  { webSocketDebuggerUrl: "ws://localhost:9335/devtools/page/A1" }, { id: "B2" },
]) assert.equal(verifiedTarget({ ...target, ...overrides }), false);
assert.match(builtinEntry("prism").pathname, /\/BundledPlugins\/prism\/backend\.js$/);
assert.equal(builtinEntry("p-sign"), null);
assert.equal(permittedMethod("p-sign", "update"), false);
assert.equal(permittedMethod("prism", "image.action"), false);
assert.equal(permittedMethod("prism", "snapshot"), true);
const plan = [{id:"prism"}, {id:"p-sign"}];
const one = {id:"W1", result:{mounted:["p-sign"],errors:{prism:"failed"}}};
const two = {id:"W2", result:{mounted:["prism"],errors:{}}};
const both = summarize(plan, [one, two], new Map());
assert.deepEqual(both.mounted, ["prism","p-sign"]);
assert.equal(both.errors.prism, "W1: failed");
assert.deepEqual(both.windows.W1, ["p-sign"]);
assert.deepEqual(summarize(plan, [two], new Map()).errors, {});
assert.deepEqual(summarize(plan, [], new Map()).mounted, []);

const handlers = new Map();
activate({rpc:{handle:(name, fn) => handlers.set(name, fn)}});
const lookup = handlers.get("network.request");
const oldFetch = globalThis.fetch;
try {
  let hits = 0;
  globalThis.fetch = async () => { hits++; return {status:302, url:"https://t.alcy.cc/pc", headers:new Headers({location:"https://other.invalid/image"})}; };
  await assert.rejects(lookup({url:"https://other.invalid", method:"GET", responseType:"json"}), /Unsupported/);
  assert.equal(hits, 0);
  await assert.rejects(lookup({url:"https://t.alcy.cc/pc", method:"HEAD", responseType:"none"}), /Unsupported/);
  assert.equal(hits, 1);
} finally { globalThis.fetch = oldFetch; }
console.log("PASS bundled entries, main-window restrictions, service scopes, redirect checks and multi-window reports");
