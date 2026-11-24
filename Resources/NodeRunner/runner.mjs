import readline from "node:readline";
import { Console } from "node:console";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";

// stdout belongs to the protocol; ordinary plugin logging goes to stderr.
globalThis.console = new Console(process.stderr, process.stderr);
const handlers = new Map();
const send = message => process.stdout.write(JSON.stringify(message) + "\n");
let initialized = false;
let dispose;
async function handle(message) {
  if (message.type === "init") {
    if (initialized || !isAbsolute(message.entry) || !isAbsolute(message.dataDirectory)) {
      throw new Error("Invalid initialization");
    }
    if (Number(process.versions.node.split(".")[0]) < 22) throw new Error("Requires Node.js 22+");
    const module = await import(pathToFileURL(message.entry).href);
    const activate = module.activate ?? module.default?.activate ?? module.default;
    if (typeof activate !== "function") throw new Error("The Node entry must export activate");
    const rpc = {
      handle(name, listener) {
        if (typeof name !== "string" || !name || typeof listener !== "function" || handlers.has(name)) {
          throw new Error("Invalid or duplicate RPC method");
        }
        handlers.set(name, listener);
        return () => handlers.delete(name);
      },
      emit(name, payload) {
        if (typeof name !== "string" || !name) throw new Error("Missing event name");
        send({ type: "event", name, payload: payload ?? null });
      },
    };
    dispose = await activate({ dataDirectory: message.dataDirectory, rpc });
    initialized = true;
    return null;
  }
  const handler = handlers.get(message.method);
  if (message.type !== "call" || !initialized || !handler) throw new Error("Unknown plugin method");
  return await handler(message.parameters);
}

try {
  for await (const line of readline.createInterface({ input: process.stdin, crlfDelay: Infinity })) {
    let id = null;
    try {
      const message = JSON.parse(line);
      id = message.id ?? null;
      send({ type: "result", id, ok: true, value: (await handle(message)) ?? null });
    } catch (error) {
      send({ type: "result", id, ok: false, error: String(error?.message ?? error) });
    }
  }
} finally {
  if (typeof dispose === "function") await dispose();
}
