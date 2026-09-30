import * as THREE from 'three';
import { ELEMENT_COLORS } from '../../data/terrain.js';
export function createEffects(scene) {
  const geometry=new THREE.SphereGeometry(0.04,5,4);
  const mesh=new THREE.InstancedMesh(geometry,new THREE.MeshBasicMaterial({color:'#ffd98b'}),128);
  mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);scene.add(mesh);
  const particles=[],dummy=new THREE.Object3D();let shake=0;
  return {
    get shake(){return shake;},
    onEvents(events){
      for(const e of events)if(['hit','burst','lit','summoned','swung'].includes(e.type) && e.x!==undefined){
        if(e.type==='burst')shake=0.14;
        for(let i=0;i<(e.type==='burst'?18:5);i++){
          if(particles.length>=128)particles.shift();
          const angle=i*2.4;
          particles.push({x:e.x,y:e.y,z:0.5,vx:Math.cos(angle)*1.4,vy:Math.sin(angle)*1.4,vz:1+i%3*0.4,left:0.55,color:ELEMENT_COLORS[e.element]||'#ffe1a4'});
        }
      }
    },
    frame(dt){
      shake=Math.max(0,shake-dt);
      for(let i=particles.length-1;i>=0;i--){const p=particles[i];p.left-=dt;if(p.left<=0){particles.splice(i,1);continue;}p.x+=p.vx*dt;p.y+=p.vy*dt;p.z+=p.vz*dt;p.vz-=dt*4;}
      for(let i=0;i<particles.length;i++){
        const p=particles[i];dummy.position.set(p.x,p.z,p.y);dummy.scale.setScalar(p.left*2);dummy.updateMatrix();mesh.setMatrixAt(i,dummy.matrix);mesh.setColorAt(i,new THREE.Color(p.color));
      }
      mesh.count=particles.length;mesh.instanceMatrix.needsUpdate=true;if(mesh.instanceColor)mesh.instanceColor.needsUpdate=true;
    }
  };
}
export function drawTelegraphs(group,tells,time) {
  while(group.children.length){const child=group.children[0];child.geometry.dispose();child.material.dispose();group.remove(child);}
  for(const t of tells){
    const progress=Math.min(1,(time-t.start)/(t.end-t.start));
    const color=t.kind==='stack'?'#83cfeb':t.kind==='spread'?'#f195b6':'#ffb97b';
    const material=new THREE.MeshBasicMaterial({color,transparent:true,opacity:0.18+progress*0.55,side:THREE.DoubleSide,depthWrite:false});
    let geometry,mesh;
    if(t.shape==='line'){
      geometry=new THREE.PlaneGeometry(t.reach,t.width*2);
      mesh=new THREE.Mesh(geometry,material);mesh.rotation.x=-Math.PI/2;mesh.rotation.z=-t.angle;
      mesh.position.set(t.x+Math.cos(t.angle)*t.reach/2,0.045,t.y+Math.sin(t.angle)*t.reach/2);
    }else{
      const radius=t.radius||t.reach;
      geometry=t.shape==='fan'?new THREE.CircleGeometry(radius,40,-t.angle-t.arc/2,t.arc):new THREE.CircleGeometry(radius,40);
      mesh=new THREE.Mesh(geometry,material);mesh.rotation.x=-Math.PI/2;mesh.position.set(t.x,0.045,t.y);
      const ring=new THREE.Mesh(new THREE.RingGeometry(radius*0.93,radius,40),new THREE.MeshBasicMaterial({color,side:THREE.DoubleSide,transparent:true,opacity:0.9}));ring.rotation.x=-Math.PI/2;ring.position.set(t.x,0.052,t.y);group.add(ring);
    }
    group.add(mesh);
  }
}
