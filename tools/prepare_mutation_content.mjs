// Emits an apply_patch patch; does not write project files. Idempotent content update.
import fs from 'node:fs';
const root = new URL('../', import.meta.url).pathname;
const paths = ['data/content/items.json', 'data/content/item_catalog.json', 'data/content/species_drop_tables.json', 'data/content/monster_abilities.json'];
const old = paths.map(p => fs.readFileSync(root + p, 'utf8'));
const [items, foodCatalog, drops, abilities] = old.map(JSON.parse);
const names = {goblin:'고블린',kobold:'코볼트',wolf:'늑대',boar:'멧돼지',beetle:'딱정벌레',slime:'슬라임',bat:'박쥐',fire_lizard:'화염 도마뱀',frost_spider:'서리 거미',electric_eel:'전기 뱀장어',viper:'독사',troll:'트롤',stone_golem:'돌 골렘',shadow_beast:'그림자 짐승',leech:'거머리',aberration:'변이체',dcss_rat:'쥐',dcss_river_rat:'강쥐',dcss_gnoll:'놀',dcss_orc:'오크',dcss_hobgoblin:'홉고블린',dcss_frilled_lizard:'주름목 도마뱀'};
const organs = {goblin:'눈',kobold:'손가락',wolf:'뒷다리 힘줄',boar:'가죽',beetle:'갑각',slime:'핵',bat:'귀',fire_lizard:'화염샘',frost_spider:'실샘',electric_eel:'발전 기관',viper:'독샘',troll:'심장',stone_golem:'석핵',shadow_beast:'눈',leech:'흡반',aberration:'안구',dcss_rat:'귀',dcss_river_rat:'독니',dcss_gnoll:'다리 힘줄',dcss_orc:'눈',dcss_hobgoblin:'가죽',dcss_frilled_lizard:'색소샘'};
const added = {dcss_rat:'ECHO_SENSE',dcss_river_rat:'VENOM_FANG',dcss_gnoll:'HUNTER_LEAP',dcss_orc:'PREDATOR_NERVE',dcss_hobgoblin:'HIDE_PLATING',dcss_frilled_lizard:'SHADOW_VEIL'};
for (const [species, ability] of Object.entries(added)) {
  if (abilities.definitions.some(r=>r.species_id===species)) continue;
  const base=abilities.definitions.find(r=>r.ability_id===ability);
  abilities.definitions.push({...base,species_id:species,essence_id:'ORGAN_'+species.toUpperCase()});
}
const template=items.definitions.find(r=>r.definition_id==='FOOD_RATION');
for (const row of abilities.definitions) {
  const label=names[row.species_id]+'의 '+organs[row.species_id];
  let item=items.definitions.find(r=>r.definition_id===row.essence_id);
  if (!item) {item={...template,definition_id:row.essence_id,stack_limit:1,use_kind:'NONE'};items.definitions.push(item);}
  item.label=label;item.category='CONSUMABLE';item.use_kind='NONE';
  const table=drops.tables.find(t=>t.species_id===row.species_id);
  if (!table.rolls.some(r=>r.definition_id===row.essence_id)) table.rolls.push({roll_id:'ORGAN_'+row.species_id.toUpperCase(),definition_id:row.essence_id,chance_per_1000:200,min_quantity:1,max_quantity:1});
}
for (const table of drops.tables) {
  const species=table.species_id;
  if (species==='stone_golem') continue; // Inorganic body: special core only.
  const id='FOOD_MONSTER_'+species.toUpperCase();
  if (!items.definitions.some(r=>r.definition_id===id)) items.definitions.push({...template,definition_id:id,label:names[species]+' 고기'});
  if (!foodCatalog.definitions.some(r=>r.definition_id===id)) foodCatalog.definitions.push({definition_id:id,family:'FOOD',tier:1,min_depth:1,buy_price:4,sell_price:1,effect_kind:'NUTRITION',effect_power:20});
  if (!table.rolls.some(r=>r.definition_id===id)) table.rolls.push({roll_id:'MEAT_'+species.toUpperCase(),definition_id:id,chance_per_1000:450,min_quantity:1,max_quantity:1});
}
for(const table of drops.tables)table.rolls.sort((a,b)=>a.roll_id<b.roll_id?-1:a.roll_id>b.roll_id?1:0);
let patch='*** Begin Patch\n';
for (const [i,value] of [items,foodCatalog,drops,abilities].entries()) {
  if(JSON.stringify(value)===JSON.stringify(JSON.parse(old[i])))continue;
  const next=JSON.stringify(value,null,2)+'\n';
  if(next===old[i])continue;
  patch+='*** Update File: '+root+paths[i]+'\n@@\n'+old[i].trimEnd().split('\n').map(l=>'-'+l).join('\n')+'\n'+next.trimEnd().split('\n').map(l=>'+'+l).join('\n')+'\n';
}
process.stdout.write(patch+'*** End Patch\n');
