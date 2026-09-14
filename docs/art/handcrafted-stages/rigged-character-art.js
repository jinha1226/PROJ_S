// Every PNG is rendered from the SAME Blender armature, mesh and material set.
const CharacterArt=(()=>{
 const manifest=globalThis.RiggedHeroManifest,images=new Map(),rows=new Map();let started=false;
 const sequences=manifest.actions;
 const key=(variant,direction,pose)=>`${variant}:${direction}:${pose}`;
 function frame(action,tick){const sequence=sequences[action]||sequences.idle;return sequence[((tick%sequence.length)+sequence.length)%sequence.length];}
 function get(variant,direction,pose){const image=images.get(key(variant,direction,pose));return image?.complete&&image.naturalWidth===64?image:null;}
 function draw(ctx,variant,direction,pose,x,y,scale=1){const image=get(variant,direction,pose);if(!image)return false;ctx.imageSmoothingEnabled=false;ctx.drawImage(image,Math.round(x-manifest.anchor[0]*scale),Math.round(y-manifest.anchor[1]*scale),64*scale,64*scale);return true;}
 function drawSkeleton(ctx,variant,direction,pose,x,y,scale=1){
  const row=rows.get(key(variant,direction,pose));if(!row)return;
  const point=p=>[x+(p[0]-manifest.anchor[0])*scale,y+(p[1]-manifest.anchor[1])*scale];
  ctx.save();ctx.strokeStyle='#ffe293';ctx.fillStyle='#79ead0';ctx.lineWidth=1.5;
  for(const [head,tail] of row.joints){const a=point(head),b=point(tail);ctx.beginPath();ctx.moveTo(...a);ctx.lineTo(...b);ctx.stroke();ctx.fillRect(a[0]-2,a[1]-2,4,4);}ctx.restore();
 }
 function load(callback=()=>{}){if(started)return;started=true;for(const row of manifest.frames){const id=key(row.variant,row.direction,row.frame),image=new Image();rows.set(id,row);images.set(id,image);image.onload=callback;image.onerror=callback;image.src='rigged-hero/'+row.file;}}
 return {load,get,draw,drawSkeleton,frame,sequences,poseNames:['정지','보행 1','보행 2','보행 3','보행 4','공격 준비','타격','후속 동작','복귀'],get ready(){return images.size===72&&[...images.values()].every(i=>i.complete&&i.naturalWidth===64&&i.naturalHeight===64);}};
})();
