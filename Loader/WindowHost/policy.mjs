// Only these packaged services may be registered by a verified Codex main window.
const services = new Map([
  ["prism", { entry: "prism/backend.js", methods: ["snapshot", "update"] }],
  ["custom-background", { entry: "custom-background/src/node.js", methods: ["network.request", "image.upload", "image.read", "image.action"] }],
]);
export function builtinEntry(id) {
  const service = services.get(id);
  return service ? new URL("../BundledPlugins/" + service.entry, import.meta.url) : null;
}
export function permittedMethod(id, method) {
  return services.get(id)?.methods.includes(method) === true;
}
export function mainPage(raw) {
  try {
    const u = new URL(raw);
    return u.protocol === "app:" && u.host === "-" && !u.username && !u.password &&
      u.pathname === "/index.html" && !/avatar-overlay/i.test(decodeURIComponent(u.href));
  } catch { return false; }
}
export function verifiedTarget(t) {
  if (t?.type !== "page" || !mainPage(t.url) || typeof t.id !== "string" || !/^[A-Za-z0-9-]+$/.test(t.id)) return false;
  return t.webSocketDebuggerUrl === "ws://127.0.0.1:9335/devtools/page/" + t.id;
}
export function summarize(packages, sessions, serviceErrors) {
  const confirmed = new Set();
  const windows = Object.create(null);
  const failures = new Map();
  for (const [id, reason] of serviceErrors) failures.set(id, [reason]);
  for (const session of sessions) {
    if (!session.result) continue;
    const { mounted, errors } = session.result;
    windows[session.id] = mounted;
    for (const id of mounted) confirmed.add(id);
    for (const [id, reason] of Object.entries(errors)) {
      const messages = failures.get(id) ?? [];
      messages.push(session.id + ": " + reason);
      failures.set(id, messages);
    }
  }
  return {
    windows, mounted: packages.map(p => p.id).filter(id => confirmed.has(id)),
    errors: Object.fromEntries([...failures].map(([id, messages]) => [id, messages.join("\n")])),
  };
}
