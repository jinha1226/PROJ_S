// No Godot invocation: content contracts and a JS mirror of projection/layout only.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const root = new URL('../', import.meta.url);
const read = p => fs.readFileSync(new URL(p, root), 'utf8');
const data = p => JSON.parse(read('data/content/' + p + '.json'));
const items = data('items').definitions;
const catalog = data('item_catalog').definitions;
const parts = data('monster_abilities').definitions;
const drops = data('species_drop_tables').tables;
const byId = new Map(items.map(r => [r.definition_id, r]));
assert.equal(byId.size, items.length);
assert.equal(parts.length, 22);
assert.equal(new Set(parts.map(r => r.essence_id)).size, 22);
for (const part of parts) {
  const item = byId.get(part.essence_id);
  assert.equal(item.category, 'CONSUMABLE');
  assert.equal(item.use_kind, 'NONE');
  assert.equal(item.stack_limit, 1);
  assert(!catalog.some(r => r.definition_id === item.definition_id && r.family === 'FOOD'));
  assert(drops.find(r => r.species_id === part.species_id).rolls.some(r => r.definition_id === item.definition_id));
}
for (const table of drops) {
  assert.equal(new Set(table.rolls.map(r => r.roll_id)).size, table.rolls.length);
  assert.deepEqual(table.rolls.map(r => r.roll_id), table.rolls.map(r => r.roll_id).sort());
  for (const roll of table.rolls) {
    assert(byId.has(roll.definition_id));
    assert(roll.chance_per_1000 >= 0 && roll.chance_per_1000 <= 1000);
    assert(roll.min_quantity > 0 && roll.max_quantity >= roll.min_quantity);
  }
  const meat = table.rolls.find(r => r.definition_id.startsWith('FOOD_MONSTER_'));
  if (table.species_id === 'stone_golem') { assert(!meat); continue; }
  assert.equal(meat.chance_per_1000, 450);
  assert.equal(byId.get(meat.definition_id).use_kind, 'EAT');
  assert.equal(catalog.find(r => r.definition_id === meat.definition_id).effect_power, 20);
}
assert.equal(items.filter(r => r.definition_id.startsWith('FOOD_MONSTER_')).length, 21);
// Independent numerical mirror; does not execute GDScript or test touch dispatch.
let roundTrips = 0;
for (const [w,h] of [[360,480],[390,520],[430,600],[800,360]]) {
  for (const n of [9,13,17]) for (let x=0; x<n; x++) for (let y=0; y<n; y++) {
    const half = Math.min(w/(n*1.35),h/n);
    const a=x+0.5-n/2,b=y+0.5-n/2;
    const px=(a-b)*half+w/2,py=(a+b)*half*0.5+h/2;
    const u=(px-w/2)/half,v=(py-h/2)/half;
    assert(Math.abs(v+u*0.5+n/2-(x+0.5))<1e-9);
    assert(Math.abs(v-u*0.5+n/2-(y+0.5))<1e-9);
    roundTrips++;
  }
}
// Mirror authoritative fixed rooms, route clearances and new obstacle rules.
const rooms=[[2,18,12,13],[15,3,16,16],[15,29,16,16],[34,16,12,17]];
const routes=[[[5,24],[10,24],[10,11],[40,11],[42,24]],[[5,24],[10,24],[10,37],[40,37],[42,24]],[[23,11],[23,24],[23,37]]];
const centers=[[8,27],[27,7],[27,41],[42,29],[9,25],[19,8],[20,40],[13,11],[25,13],[19,35],[27,38],[36,24],[5,24],[42,24],[23,24],[8,24]];
const key=(x,y)=>y*48+x;
const square=(p,r,fn)=>{for(let y=p[1]-r;y<=p[1]+r;y++)for(let x=p[0]-r;x<=p[0]+r;x++)fn(x,y);};
for(let seed=0;seed<100;seed++){
  const t=Array(48*48).fill('wall'),safe=new Set();
  for(const [x,y,w,h] of rooms)for(let j=y;j<y+h;j++)for(let i=x;i<x+w;i++)t[key(i,j)]='floor';
  for(const route of routes)for(let i=1;i<route.length;i++){
    let [x,y]=route[i-1];const [ex,ey]=route[i];
    while(true){square([x,y],1,(a,b)=>{t[key(a,b)]='floor';safe.add(key(a,b));});if(x===ex&&y===ey)break;x+=Math.sign(ex-x);y+=Math.sign(ey-y);}
  }
  for(const p of centers)square(p,2,(x,y)=>safe.add(key(x,y)));
  for(const p of centers.slice(7,12))square(p,2,(x,y)=>{t[key(x,y)]='floor';});
  for(const p of [...centers.slice(0,7),...centers.slice(12,14),[5,24]])square(p,1,(x,y)=>{t[key(x,y)]='floor';});
  let obstacles=0;
  for(const [i,[x,y,w,h]] of rooms.entries()){
    for(let b=y+3;b<y+h-2;b+=5)for(let a=x+3;a<x+w-2;a+=5){
      if(safe.has(key(a,b)))continue;
      t[key(a,b)]='wall';obstacles++;
      if((a*13+b*7+seed)%3===0&&!safe.has(key(a+1,b)))t[key(a+1,b)]='wall';
      for(const [c,d] of [[a,b+1],[a-1,b]])if(!safe.has(key(c,d)))t[key(c,d)]='rubble';
    }
    if(i===2)for(let b=y+2;b<y+7;b++)for(let a=x+2;a<x+7;a++)if(!safe.has(key(a,b))&&t[key(a,b)]!=='wall')t[key(a,b)]='water';
  }
  assert(obstacles>0);assert(t.includes('rubble'));assert(t.includes('water'));
  const seen=new Set([key(5,24)]),queue=[[5,24]];
  for(let i=0;i<queue.length;i++){const [x,y]=queue[i];for(const [a,b] of [[x+1,y],[x-1,y],[x,y+1],[x,y-1]])if(a>=0&&b>=0&&a<48&&b<48&&!seen.has(key(a,b))&&t[key(a,b)]!=='wall'){seen.add(key(a,b));queue.push([a,b]);}}
  for(const [x,y] of centers)assert(seen.has(key(x,y)),`seed ${seed}: unreachable ${x},${y}`);
  // Protected centers may extend into original walls; only routes promise floor.
  for(const route of routes)for(let i=1;i<route.length;i++){
    let [x,y]=route[i-1];const [ex,ey]=route[i];
    while(true){square([x,y],1,(a,b)=>assert.notEqual(t[key(a,b)],'wall'));if(x===ex&&y===ey)break;x+=Math.sign(ex-x);y+=Math.sign(ey-y);}
  }
}
const knowledge=read('sim/abilities/mutation_knowledge.gd');
assert(knowledge.includes('result["effect_preview"]={}'));
assert(knowledge.includes('party.monster_meat_eaten'));
assert(read('playtest/party_encounter_sandbox.gd').includes('GridScript.GRAPHICS_MODE_TACTICAL'));
for(const p of ['playtest/tactical_board_layer.gd','playtest/tactical_board_projection.gd','playtest/tactical_terrain_layout.gd','playtest/ordinary_food_service.gd','sim/abilities/mutation_knowledge.gd']){
  for(const [,ref] of read(p).matchAll(/preload\("res:\/\/([^"\n]+)"\)/g))assert(fs.existsSync(new URL(ref,root)),ref);
}
console.log(`PASS: 22 special parts, 21 meats, drop references, ${roundTrips} projection round trips, 100 layout mirrors, knowledge/default-view source guards. Godot NOT run.`);
