import { BUILD, PRESETS, BUILD_ERRORS } from '../data/build.js';
import { placePlan, presetPlan, recommend, autoBuild, rectangle, undo, copyRoom, validatePlan } from '../town/settlement.js';
import { $, openPanel, button, html, closePanel, notice } from './dom.js';
export class Builder {
  constructor(app){this.app=app;this.kind='wall';this.rotation=0;this.first=null;this.dragged=false;}
  menu(){
    const body=openPanel('한 칸씩, 불빛 아래');
    html(body,`<div class="resource">나무 ${this.app.meta.resources.wood} · 돌 ${this.app.meta.resources.stone}</div>`);
    const grid=html(body,'<div class="grid"></div>').firstChild;
    for(const [key,def]of Object.entries(BUILD))grid.append(button(`${def.name} · ${def.wood} / ${def.stone}`,()=>this.start(key)));
    html(body,'<div class="section-label">방 프리셋</div>');
    const row=html(body,'<div class="grid"></div>').firstChild;
    for(const [key,def]of Object.entries(PRESETS))row.append(button(def.name,()=>{this.preset=key;this.start('preset');const plan=recommend(this.app.meta,key);if(plan)this.app.renderer.preview(plan);}));
    const tools=html(body,'<div class="tabs" style="margin-top:12px"></div>').firstChild;
    tools.append(button('알아서 짓기',()=>{const result=autoBuild(this.app.meta);if(!result.ok)notice(BUILD_ERRORS[result.reason]);this.app.save();this.menu();}),button('사각형',()=>this.start('rectangle')),button('되돌리기',()=>{undo(this.app.meta);this.app.save();this.menu();}));
    if(this.app.meta.rooms.length)body.append(button('첫 방 복사',()=>{this.copy=this.app.meta.rooms[0];this.start('copy');}));
  }
  start(kind){this.kind=kind;this.first=null;this.app.buildMode=kind;closePanel();this.app.hud.signature='';
    $('context').replaceChildren(button('돌리기',()=>{this.rotation=(this.rotation+1)%4;}),button('되돌리기',()=>undo(this.app.meta)),button('건설 끝',()=>{this.app.buildMode=null;this.app.renderer.preview([]);$('context').replaceChildren();this.app.save();}));
  }
  pointer(phase,point,e){
    if(!point)return;
    const p={x:Math.floor(point.x),y:Math.floor(point.y)},rect=$('viewport').getBoundingClientRect();
    $('magnifier').style.cssText=`display:block;left:${Math.min(rect.width-78,Math.max(0,e.clientX-rect.left-38))}px;top:${Math.max(0,e.clientY-rect.top-85)}px`;
    let plan=this.plan(p),verdict=validatePlan(this.app.meta,plan);
    $('magnifier').textContent=verdict.ok?`${p.x} · ${p.y}
木${verdict.cost.wood} 石${verdict.cost.stone}`:BUILD_ERRORS[verdict.reason];
    this.app.renderer.preview(plan,verdict.ok);
    if(this.kind==='rectangle'){
      if(phase==='down'){this.down=p;this.dragged=false;}
      if(phase==='move' && this.down && (p.x!==this.down.x || p.y!==this.down.y)){this.dragged=true;this.first=this.down;}
      if(phase==='up'){
        if(!this.first){this.first=p;return;}
        plan=rectangle(this.first,p);if(plan.length){this.commit(plan);this.first=null;}
      }
    }else if(phase==='up')this.commit(plan);
  }
  plan(p){
    if(this.kind==='preset')return presetPlan(this.preset,p.x,p.y,this.rotation);
    if(this.kind==='copy')return copyRoom(this.app.meta,this.copy,p.x,p.y,this.rotation);
    if(this.kind==='rectangle')return this.first?rectangle(this.first,p):[];
    return [{...p,kind:this.kind}];
  }
  commit(plan){const result=placePlan(this.app.meta,plan);if(!result.ok)notice(BUILD_ERRORS[result.reason]);else{this.app.renderer.preview([]);this.app.save();}}
}
