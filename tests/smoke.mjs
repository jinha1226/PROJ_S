import { chromium, devices } from 'playwright';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { serve } from '../tools/serve.mjs';
await mkdir('test-results',{recursive:true});
const server=await serve(0),port=server.address().port;
const browser=await chromium.launch({headless:true,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try{
  for(const device of ['desktop','mobile']){
    const context=await browser.newContext(device==='mobile'?devices['iPhone 13']:{viewport:{width:1280,height:900}});
    const page=await context.newPage(),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',msg=>{if(msg.type()==='error' && !msg.text().includes('favicon'))errors.push(msg.text());});
    // Test the same CDN modules from the pinned npm copy; CI has no CDN dependency.
    await page.route('https://cdn.jsdelivr.net/npm/three@0.180.0/**',async route=>{
      const pathname=new URL(route.request().url()).pathname.split('three@0.180.0/')[1];
      const body=await readFile('node_modules/three/'+pathname);await route.fulfill({status:200,contentType:'text/javascript',body});
    });
    await page.goto(`http://127.0.0.1:${port}/?test=1`);
    await page.waitForFunction(()=>!!window.__game);
    await page.screenshot({path:`test-results/${device}-title.png`});
    await page.getByRole('button',{name:'불씨 품기',exact:true}).click();
    await page.waitForFunction(()=>window.__game.mode==='dungeon');
    const time=await page.evaluate(()=>window.__game.world.time);
    await page.waitForTimeout(250);assert.equal(await page.evaluate(()=>window.__game.world.time),time);
    if(device==='desktop'){
      await page.keyboard.down('d');await page.waitForTimeout(400);await page.keyboard.up('d');
      await page.keyboard.down(' ');await page.waitForTimeout(300);await page.keyboard.up(' ');
    }else{
      const box=await page.locator('#viewport').boundingBox();
      const touch=await context.newCDPSession(page),x=box.x+box.width/2,y=box.y+box.height*0.72;
      await touch.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
      await touch.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x+25,y}]});
      await page.waitForTimeout(400);
      await touch.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    }
    assert.ok(await page.evaluate(()=>window.__game.world.time)>time);
    await page.waitForTimeout(150);const frozen=await page.evaluate(()=>window.__game.world.time);await page.waitForTimeout(200);assert.equal(await page.evaluate(()=>window.__game.world.time),frozen);
    await page.getByRole('button',{name:'가방',exact:true}).click();await page.screenshot({path:`test-results/${device}-inventory.png`});
    await page.getByRole('button',{name:'닫기',exact:true}).click();
    await page.screenshot({path:`test-results/${device}-dungeon.png`});
    await page.getByRole('button',{name:'귀환',exact:true}).click();await page.waitForFunction(()=>window.__game.mode==='town');
    await page.getByRole('button',{name:'건설',exact:true}).click();await page.getByRole('button',{name:'알아서 짓기',exact:true}).click();
    assert.ok(await page.evaluate(()=>window.__game.meta.blueprints.length)>0);
    await page.getByRole('button',{name:'닫기',exact:true}).click();await page.screenshot({path:`test-results/${device}-town.png`});
    await page.reload();await page.waitForFunction(()=>!!window.__game);await page.getByRole('button',{name:'이어가기',exact:true}).click();assert.ok(await page.evaluate(()=>window.__game.meta.blueprints.length)>0);
    assert.deepEqual(errors,[],`${device} browser errors`);await context.close();console.log(`${device}: title, freeze, movement, inventory, return, building, save reload passed`);
  }
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
