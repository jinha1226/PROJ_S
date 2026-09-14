import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const root=new URL('../docs/art/handcrafted-stages/rigged-hero/',import.meta.url);
const manifest=JSON.parse(fs.readFileSync(new URL('manifest.json',root),'utf8'));
const sandbox={};vm.runInNewContext(fs.readFileSync(new URL('manifest.js',root),'utf8'),sandbox);
assert.deepEqual(JSON.parse(JSON.stringify(sandbox.RiggedHeroManifest)),manifest);
assert.equal(manifest.frames.length,72);assert.equal(new Set(manifest.frames.map(f=>f.file)).size,72);
assert.deepEqual(manifest.frame_size,[64,64]);assert.ok(Math.abs(manifest.anchor[0]-32)<.01);
for(let d=0;d<4;d++)for(let pose=0;pose<9;pose++){
 const pair=manifest.frames.filter(f=>f.direction===d&&f.frame===pose);assert.equal(pair.length,2);
 assert.deepEqual(pair[0].joints,pair[1].joints,'same actual joint positions for equipment variants');
 assert.ok(pair[0].joints.flat(2).every(Number.isFinite));
}
const hashes=new Map();
for(const row of manifest.frames){const png=fs.readFileSync(new URL(row.file,root));assert.equal(png.readUInt32BE(16),64);assert.equal(png.readUInt32BE(20),64);assert.equal(png[25],6);hashes.set(row.file,crypto.createHash('sha256').update(png).digest('hex'));}
for(const variant of manifest.variants)for(let d=0;d<4;d++){
 assert.ok(new Set(Array.from({length:9},(_,f)=>hashes.get(`${variant}-${d}-${f}.png`))).size>=7,'poses produce distinct raster images');
}
assert.equal(new Set([0,1,2,3].map(d=>hashes.get(`base-${d}-0.png`))).size,4);
console.log('RIGGED_HERO_ASSETS PASS: 72 RGBA64 frames, paired skeletons, distinct directions/poses, offline manifest parity');
