// HTML art review only. This small 3x3 graph is NOT the game's generated graph.
const StageDecor = (()=>{
 const sheet=new Image(), walls=new Image(), cache=new Map(), wallCache=new Map(), states=new Map();
 let ready=false, wallsReady=false, coord=[1,1], entry=null;
 const directions=[
  {id:'N',label:'북쪽',delta:[0,-1],cell:[3,0],out:[3,-1],axis:1},
  {id:'E',label:'동쪽',delta:[1,0],cell:[7,3],out:[8,3],axis:0},
  {id:'S',label:'남쪽',delta:[0,1],cell:[3,7],out:[3,8],axis:1},
  {id:'W',label:'서쪽',delta:[-1,0],cell:[0,3],out:[-1,3],axis:0}
 ];
 // Measured rectangles in the generated 1536x1024 atlas; no source edits.
 const rects=[[116,30,150,448],[480,50,190,438],[811,201,283,281],[1184,104,318,378],
 [36,531,307,415],[425,531,302,415],[800,531,300,415],[1187,531,306,415]];
 const key=()=>coord.join(',');
 const chestCell=index=>index===1?[3,6]:[3,4];
 function state(){if(!states.has(key()))states.set(key(),{chest:false,doorsClosed:false,theme:(coord[0]+coord[1]+1)%3});return states.get(key());}
 function links(){return directions.filter(d=>coord[0]+d.delta[0]>=0&&coord[0]+d.delta[0]<3&&coord[1]+d.delta[1]>=0&&coord[1]+d.delta[1]<3);}
 function doorMode(theme){const mode=document.querySelector('#edge-mode').value;return mode==='door'||mode==='theme'&&theme===0;}
 function sprite(id){
  if(cache.has(id))return cache.get(id);
  const tile=document.createElement('canvas');tile.width=64;tile.height=64;
  const p=tile.getContext('2d');p.imageSmoothingEnabled=false;
  const [x,y,w,h]=rects[id],scale=id===2||id===3?60/378:Math.min(60/w,60/h);
  p.drawImage(sheet,x,y,w,h,Math.round((64-w*scale)/2),Math.round(62-h*scale),Math.round(w*scale),Math.round(h*scale));
  cache.set(id,tile);return tile;
 }
 function prop(id,x,y,size=76,alpha=1){if(!ready)return;const [a,b]=project(x,y);ctx.save();ctx.globalAlpha=alpha;ctx.drawImage(sprite(id),a-size/2,b-size*62/64+8,size,size);ctx.restore();}
 function base(x,y,index,column){const d=diamond(x,y);poly(d,palettes[index][0]);if(artReady)texture(x,y,index,column);}
 function background(index){
  state().theme=index;
  if(index!==0)naturalBorder(index,false);
  for(const d of links()){
   base(...d.out,index,index===2?3:0);
   // Open passages have two visual lanes, but the canonical exit remains cell 3.
   if(!doorMode(index)){const [x,y]=d.out;base(x+(d.axis===1?1:0),y+(d.axis===0?1:0),index,3);}
  }
 }
 function cell(x,y,index){
  if(x===1&&y===1||x===6&&y===6)prop(index===0?1:0,x,y,index===0?66:60);
  const chest=chestCell(index);if(x===chest[0]&&y===chest[1])prop(state().chest?3:2,x,y,65);
 }
 function wallTile(column){
  if(wallCache.has(column))return wallCache.get(column);
  const tile=document.createElement('canvas');tile.width=64;tile.height=64;
  const p=tile.getContext('2d');p.imageSmoothingEnabled=false;
  // One boundary spans half the horizontal 64px diamond. Match its pixel density.
  const face=document.createElement('canvas');face.width=32;face.height=48;
  const f=face.getContext('2d');f.imageSmoothingEnabled=false;
  f.drawImage(walls,column*walls.naturalWidth/4,0,walls.naturalWidth/4,walls.naturalHeight,0,0,32,48);
  p.drawImage(face,0,0,32,48,0,0,64,64);
  wallCache.set(column,tile);return tile;
 }
 function wallFace(a,b,height,column,outward){
  // Project a frontal texture onto the actual boundary plane. No sprite facing guesses.
  const fullHeight=69;
  if(wallsReady){ctx.save();ctx.transform((b[0]-a[0])/64,(b[1]-a[1])/64,0,fullHeight/64,a[0],a[1]-fullHeight);
   const cut=64*(1-height/fullHeight);ctx.drawImage(wallTile(column),0,cut,64,64-cut,0,cut,64,64-cut);ctx.restore();
  }else poly([a,b,[b[0],b[1]-height],[a[0],a[1]-height]],'#4b5965');
  const topA=[a[0],a[1]-height],topB=[b[0],b[1]-height];
  poly([topA,topB,[topB[0]+outward[0],topB[1]+outward[1]],[topA[0]+outward[0],topA[1]+outward[1]]],'#6d7b87','#43505b');
 }
 function naturalBorder(index,front){
  for(const d of directions){
   const isFront=d.id==='S'||d.id==='E';if(isFront!==front)continue;
   for(let n=0;n<8;n++){
    const exit=links().includes(d)&&(n===3||n===4);
    const x=d.id==='W'?-1:d.id==='E'?8:n,y=d.id==='N'?-1:d.id==='S'?8:n;
    // Uneven earth apron, without a raised railing or a uniform wall height.
    if(n%3!==0||exit)base(x,y,index,index===2?3:1);
    if(!exit&&(index===1?n%2===0:n%3===1)&&artReady)texture(x,y,index,4,true);
   }
  }
 }
 function buttress(x,y){
  const [a,b]=project(x,y),h=79;
  const left=[a-10,b],front=[a,b+5],right=[a+10,b];
  wallFace(left,front,h,0,[0,0]);wallFace(front,right,h,0,[0,0]);
  poly([[a,b-5-h],[a+12,b-h],[a,b+6-h],[a-12,b-h]],'#85939b','#42525e');
  poly([[a-12,b-h+5],[a,b-h+11],[a+12,b-h+5],[a+12,b-h],[a,b-h+6],[a-12,b-h]],'#667784','#42525e');
 }
 function foreground(index){
  const connected=links(),door=doorMode(index);
  if(index!==0)naturalBorder(index,true);
  // Only the dungeon has a continuous built wall. Natural biomes keep irregular edges.
  for(const d of directions)for(let n=0;n<8;n++){
   const exit=connected.includes(d)&&n===3;
   if(index!==0&&!door)continue;
   if(connected.includes(d)&&!door&&(n===3||n===4))continue;
   const x=d.id==='W'?0:d.id==='E'?7:n,y=d.id==='N'?0:d.id==='S'?7:n;
   const points=diamond(x,y),pair=d.id==='N'?[0,1]:d.id==='E'?[1,2]:d.id==='S'?[2,3]:[3,0];
   const rear=d.id==='N'||d.id==='W';
   const a=points[pair[0]],b=points[pair[1]],center=project(x,y);
   const outward=[((a[0]+b[0])/2-center[0])*.3,((a[1]+b[1])/2-center[1])*.3];
   const h=rear?69:18;
   if(exit&&!rear&&!state().doorsClosed){
    // Cut-away front doorway: preserve jambs and an unobstructed threshold, no floating arch.
    const mix=t=>[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
    wallFace(a,mix(.18),h,0,outward);wallFace(mix(.82),b,h,0,outward);
   }else wallFace(a,b,h,exit?(state().doorsClosed?2:1):n%3===0?3:0,outward);
  }
  if(index===0||door){
   // Engaged masonry piers at the rear: depth and silhouette without blocking foreground cells.
   for(const p of [[-.5,-.5],[1.5,-.5],[5.5,-.5],[-.5,1.5],[-.5,5.5]])buttress(...p);
  }
  for(const d of connected){
   const [x,y]=d.out;
   const [a,b]=project(x,y);ctx.fillStyle='#aedbc9';ctx.font='12px sans-serif';ctx.textAlign='center';ctx.fillText(d.label,a,b+29);
  }
  if(entry){const [a,b]=project(...entry);ctx.strokeStyle='#eed291';ctx.lineWidth=2;ctx.strokeRect(a-6,b-6,12,12);}
  updateControls();
 }
 function go(id){
  const d=links().find(d=>d.id===id);if(!d)return false;
  if(doorMode(selected)&&state().doorsClosed){state().doorsClosed=false;render(selected);return false;}
  coord=[coord[0]+d.delta[0],coord[1]+d.delta[1]];
  entry=d.id==='N'?[3,7]:d.id==='S'?[3,0]:d.id==='E'?[0,3]:[7,3];
  render(state().theme);return true;
 }
 function toggleChest(){state().chest=!state().chest;render(selected);}
 function updateControls(){
  document.querySelector('#room-state').textContent=`연결 시연 구역 ${coord[0]+1},${coord[1]+1} / 3×3 · ${state().chest?'상자 열림':'상자 닫힘'}${ready?'':' · 소품 로딩 중/실패'}`;
  document.querySelector('#chest-toggle').textContent=state().chest?'상자 닫기':'상자 열기';
  document.querySelector('#door-toggle').textContent=state().doorsClosed?'문 열기':'문 닫기';
  document.querySelector('#door-toggle').disabled=!doorMode(selected);
  for(const button of document.querySelectorAll('#room-links button'))button.disabled=!links().some(d=>d.id===button.dataset.direction);
 }
 function pick(px,py){
  if(doorMode(selected))for(const d of links()){
   const points=diamond(...d.cell),pair=d.id==='N'?[0,1]:d.id==='E'?[1,2]:d.id==='S'?[2,3]:[3,0];
   const a=points[pair[0]],b=points[pair[1]],u=(px-a[0])/(b[0]-a[0]);
   const height=d.id==='N'||d.id==='W'?69:18,v=a[1]+u*(b[1]-a[1])-py;
   if(u>=0&&u<=1&&v>=0&&v<=height)return go(d.id);
  }
  for(const d of links())for(const p of [d.out,d.cell]){const [a,b]=project(...p);if(Math.abs(px-a)/46+Math.abs(py-b)/23<=1.25)return go(d.id);}
  const [a,b]=project(...chestCell(selected));if(Math.abs(px-a)<34&&py>b-58&&py<b+20){toggleChest();return true;}return false;
 }
 function init(){
  for(const d of directions){const button=document.createElement('button');button.type='button';button.textContent=d.label+' 구역';button.dataset.direction=d.id;button.onclick=()=>go(d.id);document.querySelector('#room-links').append(button);}
  document.querySelector('#edge-mode').onchange=()=>render(selected);
  document.querySelector('#chest-toggle').onclick=toggleChest;
  document.querySelector('#door-toggle').onclick=()=>{state().doorsClosed=!state().doorsClosed;render(selected);};
  canvas.addEventListener('click',e=>{const r=canvas.getBoundingClientRect();pick((e.clientX-r.left)*canvas.width/r.width,(e.clientY-r.top)*canvas.height/r.height);});
  sheet.onload=()=>{ready=true;render(selected);};sheet.onerror=()=>{ready=false;updateControls();};sheet.src='fantasy-props-pixel64-source.png';updateControls();
  walls.onload=()=>{wallsReady=true;wallCache.clear();render(selected);};walls.onerror=()=>{wallsReady=false;render(selected);};walls.src='dungeon-wall-faces-coarse64.png';
 }
 return {init,background,cell,foreground,go,pick,links,state,get coord(){return [...coord];},get ready(){return ready&&wallsReady;}};
})();
