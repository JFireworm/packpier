import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

const app = new URL("../build/Packpier.app/Contents/", import.meta.url);
assert.equal(process.execPath, fileURLToPath(new URL("Helpers/node", app)));
const { activate } = await import(new URL("Resources/BundledPlugins/prism/backend.js", app));
const root = await mkdtemp(path.join(tmpdir(), "prism-packaged-runtime-"));
let close;
try {
  process.env.PRISM_CODEX_HOME = root;
  const dataDirectory = path.join(root, "node-data", "prism");
  await mkdir(dataDirectory, { recursive: true });
  await mkdir(path.join(root, "sqlite"));
  await writeFile(path.join(root, "app-state.json"), JSON.stringify({ language: "en" }));
  await writeFile(path.join(root, ".codex-global-state.json"), JSON.stringify({
    "electron-renderer-content-owner": "fixture",
    "electron-owner-atoms:fixture": { "app-server-pinned-thread-order-v1": ["sample"] },
    "local-projects": { demo: { name: "Demo", rootPaths: ["/fixture"] } }
  }));
  const catalog = new DatabaseSync(path.join(root, "sqlite", "codex.db"));
  catalog.exec("CREATE TABLE local_thread_catalog(thread_id, host_id, display_title, cwd, project_id)");
  catalog.prepare("INSERT INTO local_thread_catalog VALUES(?,?,?,?,?)")
    .run("sample", "local", "Example", "/fixture", "demo");
  catalog.close();
  const legacy = new DatabaseSync(path.join(root, "state_5.sqlite"));
  legacy.exec("CREATE TABLE threads(id, name, cwd, archived)");
  legacy.close();
  const handlers = new Map();
  close = activate({ dataDirectory, rpc: {
    handle: (method, fn) => handlers.set(method, fn), emit: () => {}
  } });
  const snapshot = await handlers.get("snapshot")();
  assert.equal(snapshot.account, "fixture");
  assert.deepEqual(snapshot.threads.map(({ id, projectId, nativeIndex }) => [id, projectId, nativeIndex]),
    [["sample", "demo", 1]]);
  console.log("PASS packaged Prism reads a synthetic pinned chat and project using bundled SQLite");
} finally {
  close?.();
  await rm(root, { recursive: true, force: true });
}
