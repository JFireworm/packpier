// Renderer-side transport. Image bytes only cross the host bridge in bounded messages.
const chunkSize = 30 * 1024;
const maxBytes = 48 * 1024 * 1024;
const mime = {jpg:"image/jpeg",png:"image/png",webp:"image/webp",gif:"image/gif",avif:"image/avif",heic:"image/heic",tif:"image/tiff",bmp:"image/bmp"};

async function uploadAndRun(node, action, source) {
  const response = await fetch(source, { credentials: "omit", cache: "force-cache", referrerPolicy: "no-referrer" });
  if (!response.ok) throw Error("Image request failed (" + response.status + ")");
  const blob = await response.blob();
  if (!blob.size || blob.size > maxBytes) throw Error("Invalid image size (maximum 48 MiB)");
  const upload = crypto.randomUUID();
  try {
    for (let offset=0; offset<blob.size; offset+=chunkSize) {
      const bytes = new Uint8Array(await blob.slice(offset, offset+chunkSize).arrayBuffer());
      await node.invoke("image.upload", {id:upload, offset, data:btoa(String.fromCharCode(...bytes))});
    }
    return await node.invoke("image.action", {action, upload});
  } finally {
    await node.invoke("image.upload", {id:upload, cancel:true}).catch(() => {});
  }
}

export async function runImageAction(node, action, source, file, builtIn) {
  if (file) {
    const saved = await node.invoke("image.action", {action, file});
    if (!saved.missing) return saved;
  }
  if (!builtIn) return uploadAndRun(node, action, source);
  // Fetch the original in Node so typical online photos never cross the renderer bridge.
  return node.invoke("image.action", {action, source});
}

export async function localImageURL(node, file) {
  const parts = [];
  let offset = 0;
  let size;
  do {
    const part = await node.invoke("image.read", {file, offset});
    if (!Number.isSafeInteger(part.size) || part.size < 1 || part.size > maxBytes ||
        (size && size !== part.size)) throw Error("Invalid local image");
    size = part.size;
    const raw = atob(part.data);
    if (!raw.length || raw.length > chunkSize || offset + raw.length > size) throw Error("Incomplete local image");
    parts.push(Uint8Array.from(raw, c => c.charCodeAt(0)));
    offset += raw.length;
  } while (offset < size);
  return URL.createObjectURL(new Blob(parts, {type:mime[file.split(".").pop()]}));
}
