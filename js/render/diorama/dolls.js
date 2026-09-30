import * as THREE from 'three';
import { ENEMIES } from '../../data/enemies.js';
import { ROLES } from '../../data/roles.js';
import { WEAPONS } from '../../data/weapons.js';
import { ELEMENT_COLORS } from '../../data/terrain.js';
export function materials() {
  const steps=new Uint8Array([75,155,255]);
  const gradient=new THREE.DataTexture(steps,3,1,THREE.RedFormat);
  gradient.minFilter=gradient.magFilter=THREE.NearestFilter;gradient.needsUpdate=true;
  const cache=new Map();
  return color=>{
    if(!cache.has(color))cache.set(color,new THREE.MeshToonMaterial({color,gradientMap:gradient}));
    return cache.get(color);
  };
}
export function part(geometry,material,x,y,z,scale=[1,1,1],outline=true) {
  const mesh=new THREE.Mesh(geometry,material);mesh.position.set(x,y,z);mesh.scale.set(...scale);mesh.castShadow=true;mesh.receiveShadow=true;
  if(outline){const edge=new THREE.Mesh(geometry,new THREE.MeshBasicMaterial({color:'#242639',side:THREE.BackSide}));edge.scale.setScalar(1.055);mesh.add(edge);}
  return mesh;
}
export function createDoll(u,mat) {
  const doll=new THREE.Group();
  const sphere=new THREE.SphereGeometry(1,12,8),box=new THREE.BoxGeometry(1,1,1);
  const color=ENEMIES[u.kind]?.color || ROLES[u.role]?.color || '#dd9563';
  const skin=mat(u.team==='foe'?color:'#f6d5b3');
  const body=mat(color);const dark=mat('#3d4054');
  const torso=part(sphere,body,0,0.45,0,[0.26,0.29,0.2]);doll.add(torso);
  const head=part(sphere,skin,0,0.88,0,[0.31,0.3,0.28]);doll.add(head);
  for(const x of [-0.1,0.1])doll.add(part(sphere,dark,x,0.9,0.251,[0.027,0.037,0.018],false));
  const legs=[];
  for(const x of [-0.13,0.13]){const leg=part(sphere,dark,x,0.14,0.025,[0.11,0.15,0.14]);legs.push(leg);doll.add(leg);}
  for(const x of [-0.32,0.32])doll.add(part(sphere,skin,x,0.5,0,[0.09,0.15,0.1]));
  const gear=new THREE.Group();doll.add(gear);
  const ring=new THREE.Mesh(new THREE.RingGeometry(0.31,0.37,32),new THREE.MeshBasicMaterial({color:ROLES[u.role]?.color||'#edbc78',transparent:true,opacity:0.75,side:THREE.DoubleSide}));
  ring.rotation.x=-Math.PI/2;ring.position.y=0.035;doll.add(ring);ring.visible=u.team!=='foe';
  if(u.kind==='rat'){torso.scale.set(0.35,0.18,0.3);head.position.y=0.52;head.scale.set(0.23,0.2,0.24);for(const x of [-0.19,0.19])doll.add(part(sphere,body,x,0.66,0,[0.12,0.12,0.06]));}
  if(u.kind==='boar'){torso.scale.set(0.38,0.24,0.3);head.position.y=0.67;}
  if(['chief','keeper'].includes(u.kind))doll.scale.setScalar(1.55);
  const hp=new THREE.Group();hp.position.set(0,1.4,0);
  const backing=new THREE.Mesh(new THREE.PlaneGeometry(0.7,0.065),new THREE.MeshBasicMaterial({color:'#302c42'}));
  const bar=new THREE.Mesh(new THREE.PlaneGeometry(0.66,0.035),new THREE.MeshBasicMaterial({color:u.team==='foe'?'#e98c8b':'#b8d9a1'}));bar.position.z=0.005;
  hp.add(backing,bar);doll.add(hp);
  return {doll,torso,head,legs,gear,bar,hp,ring,signature:'',unit:u.id,hit:0,swing:0,sphere,box};
}
export function updateGear(model,u,mat) {
  const signature=JSON.stringify([u.weapon,u.gear,u.role]);if(signature===model.signature)return;
  model.signature=signature;
  while(model.gear.children.length)model.gear.remove(model.gear.children[0]);
  const weapon=WEAPONS[u.weapon],color=ELEMENT_COLORS[u.gear.weapon?.brand]||'#d7dce2';
  const blade=weapon.shape==='projectile'?part(model.box,mat('#ab7c56'),0.38,0.6,0.16,[0.08,0.55,0.05]):
    part(model.box,mat(color),0.38,0.59,0.23,[weapon.form==='blunt'?0.22:0.08,weapon.reach*0.4,weapon.form==='blunt'?0.16:0.04]);
  blade.rotation.x=-0.5;model.gear.add(blade);
  if(u.gear.shield)model.gear.add(part(model.sphere,mat('#ac9671'),-0.38,0.5,0.15,[0.06,0.25,0.23]));
  if(u.gear.head)model.gear.add(part(model.sphere,mat('#a0acbd'),0,1,0,[0.325,0.2,0.29]));
  if(u.gear.body && u.gear.body.base!=='cloth')model.gear.add(part(model.sphere,mat(u.gear.body.base==='leather'?'#886545':'#96a6b9'),0,0.44,0,[0.29,0.27,0.215]));
  if(u.gear.cloak)model.gear.add(part(model.box,mat('#9986b0'),0,0.45,-0.23,[0.44,0.5,0.05]));
  if(u.ctrl==='player'){
    model.gear.add(part(model.box,mat('#ae7447'),-0.33,0.65,0.2,[0.045,0.5,0.045]));
    const flame=part(model.sphere,mat('#ffbd66'),-0.33,0.96,0.2,[0.07,0.13,0.07],false);model.gear.add(flame);
  }
}
