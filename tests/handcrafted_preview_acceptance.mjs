import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const html = fs.readFileSync(new URL('docs/art/handcrafted-stages/preview.html', root), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
let draws = 0;
const buttons = [];
const context = new Proxy({drawImage(){ draws++; }}, {get(target,key){return target[key] ?? (()=>{});}});
const elements = {
  canvas: {getContext:()=>context}, '#name':{}, '#design':{}, '#markers':{checked:true},
  '#asset-status':{}, '#tabs':{append(button){buttons.push(button);}}
};
const sandbox = vm.createContext({Image:class {},document:{
  querySelector:s=>elements[s], querySelectorAll:()=>buttons,
  createElement:tag=>tag==='canvas'?{width:0,height:0,getContext:()=>new Proxy({}, {get:()=>()=>{}})}:{setAttribute(){}}
}});
vm.runInContext(script,sandbox);
const expected=JSON.parse(fs.readFileSync(new URL('data/content/handcrafted_rooms.json', root),'utf8'));
assert.deepEqual(JSON.parse(vm.runInContext('JSON.stringify(content)',sandbox)),expected);
assert.equal(buttons.length,3);
assert.equal(draws,0,'fallback before image load');
vm.runInContext('atlas.onload()',sandbox);
for(let i=0;i<3;i++){
  draws=0; buttons[i].onclick();
  const walls=expected.templates[i].rows.join('').split('').filter(c=>c==='#').length;
  assert.equal(draws,64+walls,'64 textured floor cells plus blockers');
  assert.equal(elements['#name'].textContent,expected.templates[i].name);
  elements['#markers'].checked=false; elements['#markers'].onchange();
  assert.equal(draws,2*(64+walls),'overlay toggle preserves terrain');
}
assert.equal(vm.runInContext('[...tileCache.values()].every(t=>t.width===64 && t.height===64)',sandbox),true);
for(let i=0;i<3;i++)assert.equal(vm.runInContext(`new Set(Array.from({length:64},(_,n)=>floorVariant(n%8,Math.floor(n/8),${i}))).size`,sandbox),4);
vm.runInContext('atlas.onerror()',sandbox);
assert.match(elements['#asset-status'].textContent,/불러오지 못/);
console.log('HANDCRAFTED_PREVIEW PASS: data, three themes, 64 tiles, overlays, load fallback');
