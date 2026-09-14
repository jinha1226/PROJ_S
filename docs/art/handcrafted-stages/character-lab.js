const CharacterLab=(()=>{
 let direction=1,tick=0,playing=false,last=0,request=0;
 const names=['↗ NE · 뒤/오른쪽','↘ SE · 앞/오른쪽','↙ SW · 앞/왼쪽','↖ NW · 뒤/왼쪽'];
 const poses=[];
 function action(){return document.querySelector('#action').value;}
 function draw(){
  const pose=CharacterArt.frame(action(),tick);
  for(const variant of ['base','equipped']){
   const canvas=document.querySelector('#'+variant),ctx=canvas.getContext('2d');ctx.clearRect(0,0,320,270);
   ctx.fillStyle='#33444b';ctx.beginPath();ctx.moveTo(160,158);ctx.lineTo(264,210);ctx.lineTo(160,262);ctx.lineTo(56,210);ctx.closePath();ctx.fill();
   ctx.fillStyle='#111b21';ctx.beginPath();ctx.ellipse(160,213,33,10,0,0,Math.PI*2);ctx.fill();
   CharacterArt.draw(ctx,variant,direction,pose,160,213,3);
   if(document.querySelector('#anchors').checked){ctx.strokeStyle='#e8c781';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(151,213);ctx.lineTo(169,213);ctx.moveTo(160,208);ctx.lineTo(160,218);ctx.stroke();}
  }
  for(let p=0;p<4;p++){const ctx=poses[p].getContext('2d');ctx.clearRect(0,0,128,128);CharacterArt.draw(ctx,'base',direction,p,64,112,2);}
  document.querySelector('#status').textContent=CharacterArt.ready?`${names[direction]} · ${action()} · 재생 단계 ${tick%CharacterArt.sequences[action()].length+1} / 원본 포즈 ${pose+1} · 64×64`:'일부 에셋 로딩 중/실패 — HTML 옆의 원본 PNG를 확인하세요.';
  document.querySelector('#play').textContent=playing?'일시정지':'재생';
  document.querySelectorAll('#directions button').forEach((b,i)=>b.setAttribute('aria-pressed',i===direction));
 }
 function loop(now){request=0;if(!playing||document.hidden)return;if(now-last>=1000/Number(document.querySelector('#speed').value)){tick++;last=now;draw();}request=requestAnimationFrame(loop);}
 function start(){if(playing&&!request&&!document.hidden){last=performance.now();request=requestAnimationFrame(loop);}}
 function setDirection(i){direction=i;draw();}
 for(let i=0;i<4;i++){const b=document.createElement('button');b.textContent=names[i];b.onclick=()=>setDirection(i);document.querySelector('#directions').append(b);}
 for(const name of ['정지','보행 A','보행 B','타격']){const figure=document.createElement('figure'),canvas=document.createElement('canvas'),caption=document.createElement('figcaption');canvas.width=128;canvas.height=128;caption.textContent=name;figure.append(canvas,caption);document.querySelector('#poses').append(figure);poses.push(canvas);}
 document.querySelector('#play').onclick=()=>{playing=!playing;if(!playing&&request){cancelAnimationFrame(request);request=0;}draw();start();};
 document.querySelector('#step').onclick=()=>{playing=false;if(request)cancelAnimationFrame(request);request=0;tick++;draw();};
 document.querySelector('#action').onchange=()=>{tick=0;draw();};document.querySelector('#anchors').onchange=draw;
 document.addEventListener('visibilitychange',()=>{if(document.hidden&&request){cancelAnimationFrame(request);request=0;}else start();});
 CharacterArt.load(draw);draw();
 return {draw,setDirection,get state(){return {direction,tick,playing,pose:CharacterArt.frame(action(),tick),action:action()};}};
})();
