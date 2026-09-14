import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const root=new URL('../docs/art/handcrafted-stages/',import.meta.url),images=[],draws=[];
const context={imageSmoothingEnabled:true,drawImage(...args){draws.push(args);}};
const sandbox=vm.createContext({Image:class{constructor(){this.complete=false;this.naturalWidth=0;images.push(this);}},document:{createElement:()=>({getContext:()=>context})}});
vm.runInContext(fs.readFileSync(new URL('character-art.js',root),'utf8'),sandbox);
const run=s=>vm.runInContext(s,sandbox);
run('CharacterArt.load()');assert.equal(run('CharacterArt.ready'),false);
for(const image of images){const file=fs.readFileSync(new URL(image.src,root));assert.equal(file.readUInt8(25),6,'RGBA PNG');image.naturalWidth=file.readUInt32BE(16);image.naturalHeight=file.readUInt32BE(20);image.complete=true;image.onload();}
assert.equal(run('CharacterArt.ready'),true);
for(const variant of ['base','equipped'])for(let d=0;d<4;d++)for(let pose=0;pose<4;pose++){
 const frame=run(`CharacterArt.get('${variant}',${d},${pose})`);
 assert.equal(frame.width,64);assert.equal(frame.height,64);
 assert.strictEqual(frame,run(`CharacterArt.get('${variant}',${d},${pose})`),'cached frame');
}
assert.equal(draws.length,32,'each source frame sampled once');
for(const args of draws){assert.ok(args.slice(1).every(Number.isFinite),'finite crop and projection');const [image,x,y,w,h]=args;assert.ok(x>=0&&y>=0&&x+w<=image.naturalWidth+.01&&y+h<=image.naturalHeight+.01,'crop within source');}
for(const [action,expected] of Object.entries({idle:[0,0,0,0],walk:[1,0,2,0],attack:[0,0,3,3]}))assert.deepEqual(JSON.parse(run(`JSON.stringify(Array.from({length:4},(_,n)=>CharacterArt.frame('${action}',n)))`)),expected);
console.log('CHARACTER_PREVIEW PASS: RGBA assets, 32 aligned 64px cached frames, crop bounds, animation sequences');
