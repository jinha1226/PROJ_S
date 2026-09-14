// Shared 64px preview renderer. Equipment is a complete preset, not modular layers yet.
const CharacterArt=(()=>{
 const sheets={},cache=new Map();let notify=()=>{};
 const specs={base:{file:'hero-base-source.png',x:[185,476,756,1044],feet:[306,608,898,1186],scale:40/240},
 equipped:{file:'hero-equipped-source.png',x:[176,484,786,1083],feet:[294,596,902,1204],scale:40/260}};
 const sequences={idle:[0],walk:[1,0,2,0],attack:[0,0,3,3,0,0]};
 function frame(action,tick){const sequence=sequences[action]||sequences.idle;return sequence[((tick%sequence.length)+sequence.length)%sequence.length];}
 function get(variant,direction,pose){
  const image=sheets[variant],spec=specs[variant];if(!image||!image.complete||!image.naturalWidth)return null;
  const key=`${variant}:${direction}:${pose}`;if(cache.has(key))return cache.get(key);
  const tile=document.createElement('canvas');tile.width=64;tile.height=64;const ctx=tile.getContext('2d');ctx.imageSmoothingEnabled=false;
  const w=image.naturalWidth/4,h=image.naturalHeight/4,x=pose*w,y=direction*h,s=spec.scale;
  ctx.drawImage(image,x,y,w,h,32-(spec.x[pose]-x)*s,56-(spec.feet[direction]-y)*s,w*s,h*s);
  cache.set(key,tile);return tile;
 }
 function draw(ctx,variant,direction,pose,x,y,scale=1){const tile=get(variant,direction,pose);if(!tile)return false;ctx.imageSmoothingEnabled=false;ctx.drawImage(tile,Math.round(x-32*scale),Math.round(y-56*scale),64*scale,64*scale);return true;}
 function load(callback=()=>{}){notify=callback;for(const [key,spec] of Object.entries(specs)){if(sheets[key])continue;const image=new Image();sheets[key]=image;image.onload=()=>{cache.clear();notify();};image.onerror=()=>notify();image.src=spec.file;}}
 return {load,get,draw,frame,sequences,get ready(){return Object.values(sheets).length===2&&Object.values(sheets).every(i=>i.complete&&i.naturalWidth>0);}};
})();
