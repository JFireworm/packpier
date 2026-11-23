import { createHash, randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { link, mkdir, mkdtemp, open, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);
const maxBytes = 48 * 1024 * 1024;
const chunkSize = 30 * 1024;
const favoriteName = /^[a-f0-9]{64}\.(png|jpg|webp|gif|avif|heic|tif|bmp)$/;
const pasteImage = `
ObjC.import('AppKit');
function run(args) {
  const data = $.NSData.dataWithContentsOfFile(args[0]);
  const image = $.NSImage.alloc.initWithData(data);
  if (!image.isValid) throw Error('Image could not be decoded');
  const tiff = image.TIFFRepresentation;
  const board = $.NSPasteboard.generalPasteboard;
  board.clearContents;
  if (!board.setDataForType(data, 'public.png')) throw Error('Pasteboard rejected PNG');
  if (tiff && tiff.length) board.setDataForType(tiff, 'public.tiff');
}`;

function extension(bytes) {
  const ascii = (a,b) => bytes.toString("ascii", a, b);
  if (bytes.subarray(0,8).equals(Buffer.from("89504e470d0a1a0a","hex"))) return "png";
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return "jpg";
  if (ascii(0,4) === "RIFF" && ascii(8,12) === "WEBP") return "webp";
  if (/^GIF8[79]a$/.test(ascii(0,6))) return "gif";
  if (ascii(4,8) === "ftyp") {
    if (/avif|avis/.test(ascii(8,32))) return "avif";
    if (/heic|heix|mif1/.test(ascii(8,32))) return "heic";
  }
  if (bytes.subarray(0,4).toString("hex").match(/^(49492a00|4d4d002a)$/)) return "tif";
  if (ascii(0,2) === "BM") return "bmp";
  throw Error("Unsupported image format");
}

async function fetchBuiltIn(source) {
  const url = new URL(source);
  if (url.username || url.password || !(url.origin === "https://tc.alcy.cc" ||
      (url.origin === "https://t.alcy.cc" && /^\/pic\/pc\/[^/]+\.(webp|png|jpe?g|avif)$/i.test(url.pathname)))) {
    throw Error("Unsupported built-in image URL");
  }
  const res = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(15000) });
  if (!res.ok || !res.body) throw Error("Image request failed (" + res.status + ")");
  const parts = [];
  let size = 0;
  for await (const part of res.body) {
    size += part.length;
    if (size > maxBytes) throw Error("Image exceeds 48 MiB");
    parts.push(part);
  }
  return Buffer.concat(parts, size);
}

// Publish only after the whole file exists. Concurrent saves never overwrite a user file.
async function publish(directory, name, bytes, deduplicate) {
  await mkdir(directory, { recursive: true });
  const temp = join(directory, ".packpier-" + randomUUID());
  await writeFile(temp, bytes, { flag: "wx", mode: 0o600 }).catch(async error => {
    if (error.code !== "EEXIST") await rm(temp, { force: true });
    throw error;
  });
  try {
    const path = join(directory, name);
    try { await link(temp, path); }
    catch (error) { if (!deduplicate || error.code !== "EEXIST") throw error; }
    return name;
  } finally { await rm(temp, { force: true }); }
}

async function copyImage(bytes, ext) {
  const dir = await mkdtemp(join(tmpdir(), "packpier-image-"));
  try {
    const source = join(dir, "image." + ext);
    const png = join(dir, "image.png");
    await writeFile(source, bytes, { mode: 0o600 });
    if (ext !== "png") await run("/usr/bin/sips", ["-s", "format", "png", source, "--out", png], { timeout: 15000 });
    await run("/usr/bin/osascript", ["-l", "JavaScript", "-e", pasteImage, png], { timeout: 15000 });
  } finally { await rm(dir, { recursive: true, force: true }); }
}

export function registerImageFiles(rpc, home = homedir()) {
  const favorites = join(home, "Pictures", "Packpier", "收藏");
  const downloads = join(home, "Downloads");
  const uploads = new Map();

  async function openFavorite(name) {
    if (!favoriteName.test(name)) throw Error("Invalid favorite name");
    const file = await open(join(favorites, name), constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const stat = await file.stat();
      if (!stat.isFile() || stat.size === 0 || stat.size > maxBytes) throw Error("Invalid favorite file");
      return { file, size: stat.size };
    } catch (error) { await file.close(); throw error; }
  }

  // Keep both directions below the loader's JSON message limits.
  rpc.handle("image.upload", ({ id, offset, data, cancel }) => {
    for (const [key, item] of uploads) if (Date.now() - item.time > 60000) uploads.delete(key);
    if (!/^[a-f0-9-]{36}$/.test(id)) throw Error("Invalid image transfer");
    if (cancel) { uploads.delete(id); return {}; }
    if (offset === 0 && !uploads.has(id) && uploads.size < 3) uploads.set(id, { parts: [], size: 0 });
    const item = uploads.get(id);
    if (!item || offset !== item.size || typeof data !== "string" || data.length > chunkSize * 4 / 3) throw Error("Invalid image chunk");
    const chunk = Buffer.from(data, "base64");
    if (!chunk.length || item.size + chunk.length > maxBytes) throw Error("Invalid image size");
    item.parts.push(chunk); item.size += chunk.length; item.time = Date.now();
    return {};
  });

  rpc.handle("image.read", async ({ file: name, offset }) => {
    if (!Number.isSafeInteger(offset) || offset < 0) throw Error("Invalid image offset");
    const { file, size } = await openFavorite(name);
    try {
      if (offset >= size) throw Error("Invalid image offset");
      const part = Buffer.alloc(Math.min(chunkSize, size - offset));
      const { bytesRead } = await file.read(part, 0, part.length, offset);
      if (!bytesRead) throw Error("Incomplete image file");
      return { size, data: part.subarray(0, bytesRead).toString("base64") };
    } finally { await file.close(); }
  });

  rpc.handle("image.action", async ({ action, file: name, source, upload }) => {
    if (!["favorite","save","copy"].includes(action)) throw Error("Unknown image action");
    let bytes;
    if (name) {
      const saved = await openFavorite(name).catch(error => {
        if (error.code !== "ENOENT") throw error;
        return null;
      });
      if (!saved) return { missing: true };
      try { bytes = await saved.file.readFile(); } finally { await saved.file.close(); }
    } else if (upload) {
      const item = uploads.get(upload);
      if (!item) throw Error("Image transfer expired");
      uploads.delete(upload);
      bytes = Buffer.concat(item.parts, item.size);
    } else {
      bytes = await fetchBuiltIn(source);
    }
    const ext = extension(bytes);
    if (action === "copy") { await copyImage(bytes, ext); return { copied: true }; }
    if (action === "favorite") {
      const hash = createHash("sha256").update(bytes).digest("hex");
      return { file: await publish(favorites, hash + "." + ext, bytes, true) };
    }
    const date = new Date().toISOString().replace(/[:.]/g,"-");
    const filename = "Packpier-" + date + "-" + randomUUID().slice(0,8) + "." + ext;
    return { file: await publish(downloads, filename, bytes, false) };
  });
}
