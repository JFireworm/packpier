import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdtemp, readFile, readdir, rm, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { registerImageFiles } from "./image-files.js";

test("favorites and downloads keep original bytes, support offline use, and avoid overwrites", async t => {
  const home = await mkdtemp(join(tmpdir(), "packpier-bg-test-"));
  t.after(() => rm(home, { recursive: true, force: true }));
  const rpc = new Map();
  registerImageFiles({ handle: (name, fn) => rpc.set(name, fn) }, home);
  const image = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+nc5kAAAAASUVORK5CYII=", "base64");
  async function favorite() {
    const id = randomUUID();
    rpc.get("image.upload")({ id, offset: 0, data: image.toString("base64") });
    return (await rpc.get("image.action")({action:"favorite", upload:id})).file;
  }
  const [file, duplicate] = await Promise.all([favorite(), favorite()]);
  assert.equal(file, duplicate);
  const dir = join(home,"Pictures","Packpier","收藏");
  assert.deepEqual(await readdir(dir), [file]);
  assert.deepEqual(await readFile(join(dir,file)), image);
  const part = await rpc.get("image.read")({file,offset:1});
  assert.deepEqual(Buffer.from(part.data,"base64"), image.subarray(1));
  const saves = await Promise.all([1,2].map(() => rpc.get("image.action")({action:"save", file})));
  assert.notEqual(saves[0].file, saves[1].file);
  for (const save of saves) assert.deepEqual(await readFile(join(home,"Downloads",save.file)), image);
  await assert.rejects(rpc.get("image.read")({file:"../elsewhere",offset:0}), /Invalid favorite/);
  await unlink(join(dir,file));
  assert.deepEqual(await rpc.get("image.action")({action:"save",file}),{missing:true});
});
