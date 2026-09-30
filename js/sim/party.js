import { B } from '../data/balance.js';
import { ROLES } from '../data/roles.js';
import { createUnit } from './unit.js';
import { createGear, recalculate } from './gear.js';
export function addCompanion(w,resident) {
  const role=ROLES[resident.role];
  const u=createUnit(`u${w.nextId++}`,{name:resident.name,ctrl:'ai',role:resident.role,residentId:resident.id,stance:resident.stance});
  u.weapon=role.weapon;u.gear.weapon=createGear(w,role.weapon,{known:true});recalculate(u);
  u.gear.body=createGear(w,'leather',{known:true});recalculate(u);w.units.push(u);return u;
}
export function setCommand(w,command) {w.command=command;w.emit('commanded',{command});}
export function partyCapacity(meta) {return Math.min(5,meta.cleared.length+1);}
export function checkDefeat(w) {
  const party=w.units.filter(u=>u.team==='party');
  if(party.every(u=>!u.alive)){w.lost=true;w.emit('defeated',{});}
}
