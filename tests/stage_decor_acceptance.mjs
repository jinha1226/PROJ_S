import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const root=new URL('../docs/art/handcrafted-stages/',import.meta.url);
const html=fs.readFileSync(new URL('preview.html',root),'utf8');
const images=[],tabs=[],links=[];
const pen=new Proxy({}, {get:(o,k)=>o[k]??(()=>{}),set:(o,k,v)=>(o[k]=v,true)});
const nodes={canvas:{width:900,height:630,getContext:()=>pen,addEventListener(){},getBoundingClientRect:()=>({left:0,top:0,width:450,height:315})},
 '#tabs':{append:b=>tabs.push(b)},'#room-links':{append:b=>links.push(b)},'#name':{},'#design':{},'#markers':{checked:true},
 '#edge-mode':{value:'theme'},'#chest-toggle':{},'#door-toggle':{},'#room-state':{},'#asset-status':{}};
const sandbox=vm.createContext({Image:class{constructor(){images.push(this);}},document:{
 querySelector:s=>nodes[s],querySelectorAll:s=>s==='#tabs button'?tabs:s==='#room-links button'?links:[],
 createElement:tag=>tag==='canvas'?{getContext:()=>pen}:{dataset:{},setAttribute(){}}
}});
const run=s=>vm.runInContext(s,sandbox);
run(fs.readFileSync(new URL('stage-decor.js',root),'utf8'));
run(html.match(/<script>([\s\S]*?)<\/script>/)[1]);
images.forEach(i=>i.onload());
assert.equal(run('StageDecor.ready'),true);
assert.equal(links.length,4);
nodes['#chest-toggle'].onclick();assert.equal(run('StageDecor.state().chest'),true);
run('StageDecor.go("E"); StageDecor.go("W")');
assert.equal(run('StageDecor.state().chest'),true,'room state preserved on return');
assert.equal(run('JSON.stringify(StageDecor.coord)'),'[1,1]');
nodes['#edge-mode'].value='door';nodes['#edge-mode'].onchange();nodes['#door-toggle'].onclick();
assert.equal(run('StageDecor.go("N")'),false,'closed door opens before transition');
assert.equal(run('JSON.stringify(StageDecor.coord)'),'[1,1]');
assert.equal(run('StageDecor.state().doorsClosed'),false);
assert.equal(run('StageDecor.go("N")'),true);
assert.equal(run('StageDecor.go("N")'),false,'no room beyond 3x3');
run('StageDecor.go("W")');
assert.equal(run('JSON.stringify(StageDecor.coord)'),'[0,0]');
assert.equal(run('StageDecor.links().length'),2);
assert.equal(links.filter(b=>b.disabled).length,2);
nodes['#edge-mode'].value='door';run('StageDecor.go("E"); StageDecor.go("S")');
assert.equal(run('StageDecor.pick(project(3,0)[0]+23,project(3,0)[1]-11.5-40)'),true,'projected doorway face is clickable');
assert.equal(run('JSON.stringify(StageDecor.coord)'),'[1,0]');
run('StageDecor.go("W")');
// All three styles and both edge modes must render, without mutating map rows.
const before=run('JSON.stringify(content)');
for(const mode of ['theme','door','open'])for(let i=0;i<3;i++){nodes['#edge-mode'].value=mode;run(`render(${i})`);}
assert.equal(run('JSON.stringify(content)'),before);
nodes['#edge-mode'].value='open';
run('StageDecor.go("E"); StageDecor.go("S")');
assert.equal(run('JSON.stringify(StageDecor.coord)'),'[1,1]');
assert.equal(run('StageDecor.pick(...project(3,-1))'),true,'canvas exit hit target');
assert.equal(run('JSON.stringify(StageDecor.coord)'),'[1,0]');
images[0].onerror();assert.equal(run('StageDecor.ready'),false,'prop failure fallback');
console.log('STAGE_DECOR PASS: props, chest persistence, closed doors, reciprocal transitions, bounds, touch target, modes, fallback');
