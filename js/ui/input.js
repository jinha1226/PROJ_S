import { setInput, selectTarget, walkTo } from '../sim/world.js';
import { useItem } from '../sim/items.js';
import { $ } from './dom.js';
export function bindInput(app) {
  const view=$('viewport'),pointers=new Map(),keys=new Set();let origin=null,touch=null,gesture=null;
  const compute=()=>{
    if(!app.world || app.mode!=='dungeon')return;
    const x=Number(keys.has('d')||keys.has('ArrowRight'))-Number(keys.has('a')||keys.has('ArrowLeft'));
    const y=Number(keys.has('s')||keys.has('ArrowDown'))-Number(keys.has('w')||keys.has('ArrowUp'));
    const a=app.renderer.yaw;setInput(app.world,x*Math.cos(a)+y*Math.sin(a),y*Math.cos(a)-x*Math.sin(a));
    app.held=keys.has(' ')||!!x||!!y;
  };
  window.addEventListener('keydown',e=>{if(['INPUT','SELECT','TEXTAREA'].includes(e.target.tagName)||$('panel').open)return;if([' ','ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.key))e.preventDefault();keys.add(e.key);compute();});
  window.addEventListener('keyup',e=>{keys.delete(e.key);compute();});
  const release=()=>{keys.clear();pointers.clear();origin=null;touch=null;gesture=null;app.held=false;if(app.world)setInput(app.world,0,0);$('joystick').style.display='none';};
  window.addEventListener('blur',release);document.addEventListener('visibilitychange',release);$('panel').addEventListener('close',release);
  function pair(){return [...pointers.values()].slice(0,2);}
  function metrics(){const [a,b]=pair();return {distance:Math.hypot(a.x-b.x,a.y-b.y),angle:Math.atan2(b.y-a.y,b.x-a.x)};}
  view.addEventListener('pointerdown',e=>{
    if(e.target.closest('button'))return;
    view.setPointerCapture(e.pointerId);pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
    if(pointers.size===2){gesture=metrics();origin=null;app.held=false;if(app.world)setInput(app.world,0,0);$('joystick').style.display='none';return;}
    touch={id:e.pointerId,x:e.clientX,y:e.clientY,moved:false};
    const rect=view.getBoundingClientRect();
    if(app.buildMode){app.buildPointer('down',app.renderer.pick(e.clientX,e.clientY),e);return;}
    if(app.mode==='dungeon' && !app.selectedItem && e.clientY>rect.top+rect.height*0.5){
      origin={x:e.clientX,y:e.clientY};app.held=true;
      if(app.world){app.world.autoPath=[];app.world.exploring=false;}
      $('joystick').style.cssText=`display:block;left:${e.clientX-rect.left-39}px;top:${e.clientY-rect.top-39}px`;
    }
  });
  view.addEventListener('pointermove',e=>{
    if(!pointers.has(e.pointerId))return;pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
    if(pointers.size>=2 && gesture){const next=metrics();app.renderer.rotate(next.angle-gesture.angle);app.renderer.magnify(gesture.distance/Math.max(1,next.distance));gesture=next;return;}
    if(touch && Math.hypot(e.clientX-touch.x,e.clientY-touch.y)>7)touch.moved=true;
    if(app.buildMode){app.buildPointer('move',app.renderer.pick(e.clientX,e.clientY),e);return;}
    if(origin && app.world){const dx=(e.clientX-origin.x)/33,dy=(e.clientY-origin.y)/33,a=app.renderer.yaw;setInput(app.world,dx*Math.cos(a)+dy*Math.sin(a),dy*Math.cos(a)-dx*Math.sin(a));const d=Math.max(1,Math.hypot(dx,dy));$('joystick').firstElementChild.style.transform=`translate(${dx/d*25}px,${dy/d*25}px)`;}
  });
  function end(e,cancel=false){
    const point=app.renderer.pick(e.clientX,e.clientY),wasGesture=!!gesture;
    pointers.delete(e.pointerId);if(pointers.size<2)gesture=null;
    if(app.buildMode && !cancel && !wasGesture)app.buildPointer('up',point,e);
    else if(!cancel && !wasGesture && touch && !touch.moved && point && app.world && app.mode==='dungeon'){
      const hero=app.world.units.find(u=>u.ctrl==='player');
      if(app.selectedItem){useItem(app.world,hero,app.selectedItem,point);app.selectedItem=null;}
      else if(point.unit)selectTarget(app.world,point.unit);
      else if(!origin)walkTo(app.world,point);
    }
    origin=null;touch=null;app.held=false;if(app.world)setInput(app.world,0,0);$('joystick').style.display='none';$('magnifier').style.display='none';
  }
  view.addEventListener('pointerup',e=>end(e));view.addEventListener('pointercancel',e=>end(e,true));
  view.addEventListener('lostpointercapture',()=>{if(!pointers.size){origin=null;app.held=false;if(app.world)setInput(app.world,0,0);}});
  view.addEventListener('wheel',e=>{e.preventDefault();app.renderer.magnify(e.deltaY>0?1.08:0.92);},{passive:false});
  return release;
}
