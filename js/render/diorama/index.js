import * as THREE from 'three';
import { TERRAIN, ELEMENT_COLORS } from '../../data/terrain.js';
import { BUILD } from '../../data/build.js';
import { B } from '../../data/balance.js';
import { cellKey, clamp } from '../../util/math.js';
import { materials, part, createDoll, updateGear } from './dolls.js';
import { createEffects, drawTelegraphs } from './effects.js';
export class Diorama {
  mount(el) {
    this.el=el;this.renderer=new THREE.WebGLRenderer({antialias:true,alpha:false,powerPreference:'high-performance'});
    this.renderer.setPixelRatio(Math.min(devicePixelRatio,1.75));this.renderer.shadowMap.enabled=true;
    this.renderer.shadowMap.type=THREE.PCFSoftShadowMap;this.renderer.outputColorSpace=THREE.SRGBColorSpace;
    this.renderer.toneMapping=THREE.ACESFilmicToneMapping;this.renderer.toneMappingExposure=1.3;
    this.el.append(this.renderer.domElement);this.renderer.domElement.setAttribute('aria-label','등불지기의 세계');
    this.scene=new THREE.Scene();this.scene.background=new THREE.Color('#172031');
    this.camera=new THREE.PerspectiveCamera(38,1,0.1,100);this.yaw=0;this.zoom=15;this.tilt=0;
    this.follow=new THREE.Vector3(10,0,10);this.intro=0;
    this.mat=materials();this.ground=new THREE.Group();this.scene.add(this.ground);
    this.dolls=new Map();this.props=new THREE.Group();this.scene.add(this.props);
    this.tells=new THREE.Group();this.scene.add(this.tells);
    this.ambient=new THREE.HemisphereLight('#9caed4','#242733',2);this.scene.add(this.ambient);
    this.sun=new THREE.DirectionalLight('#ffc98a',3);this.sun.position.set(4,15,8);this.sun.castShadow=true;
    this.sun.shadow.mapSize.set(1024,1024);this.sun.shadow.camera.left=-16;this.sun.shadow.camera.right=16;this.sun.shadow.camera.top=16;this.sun.shadow.camera.bottom=-16;
    this.scene.add(this.sun);
    this.torch=new THREE.PointLight('#ffa54b',18,9,2);this.torch.position.set(10,1.8,10);this.scene.add(this.torch);
    this.effects=createEffects(this.scene);this.revision=-1;this.frozen=false;
    this.ray=new THREE.Raycaster();this.plane=new THREE.Plane(new THREE.Vector3(0,1,0),0);
    this.resize();
  }
  resize() {const r=this.el.getBoundingClientRect();this.renderer.setSize(r.width,r.height);this.camera.aspect=r.width/r.height;this.camera.updateProjectionMatrix();}
  clearGround() {
    while(this.ground.children.length){const c=this.ground.children[0];if(c.isInstancedMesh){c.geometry.dispose();c.material.dispose();}this.ground.remove(c);}
    while(this.props.children.length)this.props.remove(this.props.children[0]);
  }
  setDungeon(w) {this.mode='dungeon';this.world=w;this.town=null;this.revision=-1;this.intro=0;this.scene.background.set('#141c2a');this.ambient.intensity=1.1;this.sun.intensity=0.8;this.follow.set(3.5,0,3.5);this.clearDolls();}
  setTown(m) {this.mode='town';this.town=m;this.world=null;this.revision=-1;this.intro=1.2;this.scene.background.set('#242d31');this.ambient.intensity=2;this.sun.intensity=3;this.follow.set(10,0,10);this.clearDolls();}
  clearDolls() {for(const m of this.dolls.values())this.scene.remove(m.doll);this.dolls.clear();}
  instance(tiles,kind,color,height=0.08) {
    if(!tiles.length)return;
    const mesh=new THREE.InstancedMesh(new THREE.BoxGeometry(0.98,height,0.98),new THREE.MeshToonMaterial({color}),tiles.length);
    const dummy=new THREE.Object3D();
    tiles.forEach((t,i)=>{dummy.position.set(t.x+0.5,height/2-0.08,t.y+0.5);dummy.updateMatrix();mesh.setMatrixAt(i,dummy.matrix);});
    if(kind==='wall'){mesh.material.transparent=true;mesh.material.opacity=0.65;}mesh.castShadow=height>0.5;mesh.receiveShadow=true;mesh.userData.kind=kind;this.ground.add(mesh);
  }
  rebuild() {
    this.clearGround();
    if(this.mode==='dungeon'){
      for(const [kind,def]of Object.entries(TERRAIN)) {
        const tiles=Object.values(this.world.tiles).filter(t=>this.world.explored.has(cellKey(t.x,t.y)) && t.kind===kind && !(kind==='door' && t.open));
        this.instance(tiles,kind,def.color,kind==='wall'?0.85:kind==='door'?0.65:0.1);
      }
      // Open doors retain a walkable floor.
      this.instance(Object.values(this.world.tiles).filter(t=>this.world.explored.has(cellKey(t.x,t.y)) && t.kind==='door' && t.open),'floor',TERRAIN.floor.color);
      for(const lamp of this.world.lamps.filter(l=>this.world.explored.has(cellKey(l.x,l.y)))){const prop=part(new THREE.CylinderGeometry(0.12,0.16,0.3,8),this.mat(lamp.used?'#615647':'#ffd592'),lamp.x,0.15,lamp.y);this.props.add(prop);}
      const exit=this.world.exit;
      for(let i=0;i<(this.world.explored.has(cellKey(exit.x,exit.y))?4:0);i++)this.props.add(part(new THREE.BoxGeometry(0.8,0.12,0.16),this.mat('#b5b4c5'),exit.x,0.08+i*0.05,exit.y-0.3+i*0.16));
      for(const item of this.world.loot.filter(i=>this.world.explored.has(cellKey(i.x,i.y))))this.props.add(part(new THREE.SphereGeometry(0.12,8,6),this.mat(item.gear.owner?'#ffce69':'#99cddb'),item.x,0.18,item.y));
    }else{
      const tiles=[];
      for(let y=0;y<B.townSize;y++)for(let x=0;x<B.townSize;x++)if(Math.hypot(x-10,y-10)<=this.town.light)tiles.push({x,y});
      this.instance(tiles,'floor','#71856c',0.13);
      for(const b of [...this.town.buildings,...this.town.blueprints]){
        const def=BUILD[b.kind];const blueprint=this.town.blueprints.includes(b);
        const heights={wall:0.9,door:0.75,bed:0.25,anvil:0.4,stove:0.5,table:0.35,training:0.65,farm:0.05,floor:0.06};
        const prop=part(new THREE.BoxGeometry(0.88,heights[b.kind],0.88),this.mat(blueprint?'#a1bcc0':def.color),b.x+0.5,heights[b.kind]/2,b.y+0.5);
        if(blueprint){prop.material=prop.material.clone();prop.material.transparent=true;prop.material.opacity=0.4;}
        this.props.add(prop);
      }
      for(let i=0;i<7;i++){const angle=i*Math.PI*2/7;this.props.add(part(new THREE.SphereGeometry(0.2,8,6),this.mat('#b9ac96'),10.5+Math.cos(angle)*0.5,0.15,10.5+Math.sin(angle)*0.5));}
      this.fire=part(new THREE.SphereGeometry(0.3,10,8),this.mat('#ffba61'),10.5,0.45,10.5,[1,1.7,1],false);this.props.add(this.fire);
      const border=new THREE.Mesh(new THREE.RingGeometry(this.town.light,this.town.light+0.07,96),new THREE.MeshBasicMaterial({color:'#e6c885',transparent:true,opacity:0.25,side:THREE.DoubleSide}));border.rotation.x=-Math.PI/2;border.position.set(10.5,0.03,10.5);this.props.add(border);
    }
  }
  frame(state,alpha,dt) {
    const w=this.world,m=this.town;
    const rev=w?`${w.revision}:${w.explored.size}:${w.loot.length}:${w.lamps.filter(l=>l.used).length}`:`${m.revision}:${Math.floor(m.light*5)}`;
    if(this.revision!==rev){this.revision=rev;this.rebuild();}
    const units=w?w.units:m.residents.filter(r=>!m.expedition.includes(r.id)).map(r=>({...r,team:'party',ctrl:'ai',kind:'resident',alive:true,hp:r.injury>0?35:100,maxHP:100,weapon:'mace',gear:{},prevX:r.x,prevY:r.y,facing:0,statuses:{}}));
    const ids=new Set();
    for(const u of units){
      ids.add(u.id);let model=this.dolls.get(u.id);
      if(!model){model=createDoll(u,this.mat);this.dolls.set(u.id,model);this.scene.add(model.doll);}
      updateGear(model,u,this.mat);
      const seen=!w || u.team==='party' || w.visibleEnemies.includes(u.id);
      model.doll.visible=seen && u.alive;
      const x=u.prevX+(u.x-u.prevX)*alpha,y=u.prevY+(u.y-u.prevY)*alpha;
      model.doll.position.set(x,0,y);model.doll.rotation.y=-u.facing+Math.PI/2;
      const walking=Math.hypot(u.x-u.prevX,u.y-u.prevY)>0.001;
      const stride=walking?Math.sin((w?.time||m.time)*14)*0.22:0;
      model.legs[0].rotation.x=stride;model.legs[1].rotation.x=-stride;
      model.torso.scale.y=0.29+(walking?Math.abs(stride)*0.08:0);
      model.hit=Math.max(0,model.hit-dt);model.swing=Math.max(0,model.swing-dt);
      model.head.scale.y=0.3-model.hit*0.4;model.gear.rotation.y=Math.sin(model.swing*16)*0.4;
      model.bar.scale.x=u.hp/u.maxHP;model.bar.position.x=-0.33*(1-u.hp/u.maxHP);
      model.hp.quaternion.copy(this.camera.quaternion);model.hp.visible=!!w && u.hp<u.maxHP;
      model.ring.material.color.set(u.id===w?.units.find(p=>p.ctrl==='player')?.target?'#fff0a5':u.windup?'#ff9a68':'#ddbd80');
    }
    for(const [id,model]of this.dolls)if(!ids.has(id)){this.scene.remove(model.doll);this.dolls.delete(id);}
    const hero=w?.units.find(u=>u.ctrl==='player');
    if(hero){this.follow.lerp(new THREE.Vector3(hero.x,0,hero.y),Math.min(1,dt*8));this.torch.position.set(hero.x,1.8,hero.y);this.torch.intensity=w.torch>0?18:0;}
    else{this.torch.position.set(10.5,1.5,10.5);this.torch.intensity=24;if(this.fire)this.fire.scale.y=1.7+Math.sin(m.time*6)*0.08;}
    this.intro=Math.max(0,this.intro-dt);
    const zoom=this.zoom+this.intro*7;
    const angle=this.tilt?Math.PI/4:Math.PI/2.35;
    const shake=this.effects.shake*Math.sin(performance.now()*0.13);
    this.camera.position.set(this.follow.x+Math.sin(this.yaw)*zoom*Math.cos(angle)+shake,zoom*Math.sin(angle),this.follow.z+Math.cos(this.yaw)*zoom*Math.cos(angle));
    this.camera.lookAt(this.follow.x,0,this.follow.z);
    drawTelegraphs(this.tells,w?.telegraphs||[],w?.time||0);
    this.effects.frame(dt);this.renderer.render(this.scene,this.camera);
  }
  onEvents(events) {this.effects.onEvents(events);for(const e of events){const m=this.dolls.get(e.unit);if(m){if(e.type==='hit')m.hit=0.22;if(e.type==='swung')m.swing=0.3;}}}
  setFrozen(value) {this.frozen=value;this.el.classList.toggle('frozen',value);}
  pick(x,y) {
    const rect=this.renderer.domElement.getBoundingClientRect();
    this.ray.setFromCamera(new THREE.Vector2((x-rect.left)/rect.width*2-1,-(y-rect.top)/rect.height*2+1),this.camera);
    const point=new THREE.Vector3();if(!this.ray.ray.intersectPlane(this.plane,point))return null;
    const unit=this.world?.units.find(u=>u.alive && this.world.visibleEnemies.includes(u.id) && Math.hypot(point.x-u.x,point.z-u.y)<0.6);
    return {x:point.x,y:point.z,unit:unit?.id};
  }
  preview(plan,valid=true) {
    if(!this.ghost){this.ghost=new THREE.Group();this.scene.add(this.ghost);}
    while(this.ghost.children.length){const c=this.ghost.children[0];c.geometry.dispose();c.material.dispose();this.ghost.remove(c);}
    for(const p of plan){const mesh=new THREE.Mesh(new THREE.BoxGeometry(0.92,0.08,0.92),new THREE.MeshBasicMaterial({color:valid?'#ffe4a0':'#ed8f8f',transparent:true,opacity:0.55}));mesh.position.set(p.x+0.5,0.2,p.y+0.5);this.ghost.add(mesh);}
  }
  rotate(amount) {this.yaw+=amount;}
  magnify(amount) {this.zoom=clamp(this.zoom*amount,8,26);}
  toggleView() {this.tilt=1-this.tilt;}
  project(x,y,z=1) {const p=new THREE.Vector3(x,z,y).project(this.camera),r=this.el.getBoundingClientRect();return {x:(p.x+1)/2*r.width,y:(1-p.y)/2*r.height};}
}
