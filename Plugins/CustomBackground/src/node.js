import { registerImageFiles } from "./image-files.js";

function requestTimeout(milliseconds) {
  const controller = new AbortController();
  const timeout = Math.max(1, Math.min(Number(milliseconds) || 10000, 60000));
  const timer = setTimeout(() => controller.abort(new Error("request timeout")), timeout);
  return { controller, clear: () => clearTimeout(timer) };
}

export function activate({ rpc }) {
  registerImageFiles(rpc);
  rpc.handle("network.request", async (parameters = {}) => {
    const url = new URL(parameters.url);
    const method = parameters.method;
    const responseType = parameters.responseType;
    const lookup = url.origin === "https://t.alcy.cc" && !url.username && !url.password &&
      ((url.pathname === "/pc" && method === "HEAD" && responseType === "none") ||
       (url.pathname === "/json" && method === "GET" && responseType === "json"));
    if (!lookup) throw new Error("Unsupported built-in image lookup");

    const timeout = requestTimeout(parameters.timeoutMs);
    try {
      const options = { method, redirect: "manual", signal: timeout.controller.signal,
                        headers: { "user-agent": "Packpier/custom-background" } };
      let response = await fetch(url, options);
      for (let index = 0; response.status >= 300 && response.status < 400; index++) {
        const location = response.headers.get("location");
        await response.body?.cancel();
        if (method !== "HEAD" || !location || index >= 3) throw new Error("Unexpected provider redirect");
        const next = new URL(location, response.url);
        if (next.username || next.password || !(next.origin === "https://tc.alcy.cc" ||
            (next.origin === "https://t.alcy.cc" && /^\/pic\/pc\/[^/]+\.(webp|png|jpe?g|avif)$/i.test(next.pathname)))) {
          throw new Error("Unsupported image redirect");
        }
        response = await fetch(next, options);
      }
      const contentType = response.headers.get("content-type") ?? "";
      let body = null;
      if (responseType === "json" && response.ok) {
        const chunks = [];
        let length = 0;
        for await (const chunk of response.body) {
          length += chunk.length;
          if (length > 65536) throw new Error("Provider response too large");
          chunks.push(chunk);
        }
        body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      }
      return {
        ok: response.ok,
        status: response.status,
        finalUrl: response.url,
        contentType,
        body,
      };
    } finally {
      timeout.clear();
    }
  });
}
