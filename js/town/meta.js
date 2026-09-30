import { HERO_NAME } from '../data/lines.js';
import { B } from '../data/balance.js';
export const SAVE_VERSION=1;
export function newMeta(seed=1) {
  return {version:SAVE_VERSION,seed,heroName:HERO_NAME,generation:1,memories:[],graves:[],residents:[],cleared:[],warehouse:[],
    resources:{...B.startingResources},buildings:[],blueprints:[],rooms:[],day:1,clock:0,
    time:0,light:B.baseLight,mood:60,events:[],relationships:{},tutorialDone:false,
    ending:null,visitor:null,visitorDay:0,undo:[],revision:0,firstFire:true,expedition:[],selected:[],nextId:1};
}
export function migrate(raw) {
  if(!raw || raw.version!==SAVE_VERSION)return newMeta();
  const meta={...newMeta(raw.seed),...raw};
  meta.events=[];meta.undo=[];meta.expedition=[];return meta;
}
export function encode(meta) {
  return JSON.stringify({...meta,events:[],undo:[],expedition:[]});
}
export function decode(text) {
  try{return migrate(JSON.parse(text));}catch{return newMeta();}
}
