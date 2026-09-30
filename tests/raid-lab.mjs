import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
const check = (name, yes) => { if (!yes) throw new Error(name + (errors.length ? `: ${errors.join(' / ')}` : '')); console.log('PASS', name); };
try {
  await page.goto(`http://127.0.0.1:${server.address().port}/raid-lab.html`);
  await page.waitForFunction(() => !!window.__raidLab, null, { timeout: 30000 });
  check('모바일 레이드 실험실 로드', await page.locator('.party .member').count() === 5 && await page.locator('#stage canvas').count() > 0);
  // A도 배속: 유닛 사이 기다림과 연출이 함께 빨라진다
  await page.locator('#speed').click(); // 1× → 2×
  const fast = await page.evaluate(() => { const b = window.__raidLab.battle; b.pace = 300; return { speed: b.speed, ms: b.takePace(), scale: window.__raidLab.view.baseScale }; });
  check('A 턴제 2배속', fast.speed === 2 && fast.ms === 150 && fast.scale === 2);
  await page.locator('[data-mode="B"]').click();
  check('B는 일시 정지로 시작', await page.evaluate(() => window.__raidLab.battle.paused));
  await page.locator('#pause').click();
  const auto = await page.evaluate(() => { const b = window.__raidLab.battle; b.boss.x = 6; b.boss.y = 8; b.bossAct(); return b.paused && !!b.tele; });
  check('B 기믹 예고에서 자동 멈춤', auto);
  await page.locator('[data-mode="C"]').click();
  await page.locator('#pause').click();
  const before = await page.evaluate(() => window.__raidLab.battle.hero.x);
  const box = await page.locator('#joystick').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 35, box.y + box.height / 2, { steps: 6 });
  await page.waitForTimeout(350);
  await page.mouse.up();
  check('C 조이스틱으로 연속 이동', await page.evaluate(() => window.__raidLab.battle.hero.x) > before);
  // C는 동료도 매 프레임 조금씩 걷는다(0.6초마다 뚝 옮기지 않는다)
  const walk = await page.evaluate(() => new Promise((done) => {
    const b = window.__raidLab.battle, u = b.party[2]; let last = u.x, moved = 0, jump = 0, n = 0;
    const f = () => { const d = Math.abs(u.x - last); if (d > 0.001) moved++; jump = Math.max(jump, d); last = u.x; if (++n < 40) requestAnimationFrame(f); else done({ moved, jump }); };
    requestAnimationFrame(f);
  }));
  check('C 동료가 끊기지 않고 걷는다', walk.moved >= 12 && walk.jump < 0.25);
  // D: 탭하면 박자를 기다리지 않고 바로 걷는다. 기믹은 처음 볼 때만 멈춘다
  await page.locator('[data-mode="D"]').click();
  await page.locator('#pause').click();
  const d = await page.evaluate(() => {
    const b = window.__raidLab.battle, x0 = b.hero.x;
    b.direct({ x: x0 + 3, y: b.hero.y });
    b.tick(0.016); // 한 프레임 만에(동료 박자 0.6초를 기다리지 않고) 한 칸
    const stepped = b.hero.x > x0;
    b.boss.x = 6; b.boss.y = 8; b.bossActs = 0; b.bossAct(); const first = b.paused;
    b.tele = null; b.setPause(false); b.bossActs = 0; b.bossAct();
    return { stepped, first, second: b.paused };
  });
  check('D 탭하면 바로 걷고 처음 보는 기믹만 멈춘다', d.stepped && d.first && !d.second);
  // E: 손을 떼면 시간이 멈추고, 조이스틱에 손을 대고 있는 동안만 흐른다. 닿은 적은 저절로 벤다
  await page.locator('[data-mode="E"]').click();
  await page.waitForTimeout(400);
  const still = await page.evaluate(() => ({ t: window.__raidLab.battle.elapsed, frozen: document.querySelector('#app').classList.contains('frozen') }));
  await page.evaluate(() => { const b = window.__raidLab.battle; b.hero.x = b.boss.x - 1.2; b.hero.y = b.boss.y; });
  const joy = await page.locator('#joystick').boundingBox();
  await page.mouse.move(joy.x + joy.width / 2, joy.y + joy.height / 2);
  await page.mouse.down();
  await page.waitForFunction(() => window.__raidLab.battle.boss.hp < 120, null, { timeout: 8000 });
  await page.mouse.up();
  await page.waitForFunction(() => window.__raidLab.view.dio.timeScale === 0, null, { timeout: 5000 }); // 손을 떼면 짧게 느려지다 멈춘다
  const t1 = await page.evaluate(() => window.__raidLab.battle.elapsed);
  await page.waitForTimeout(500);
  const t2 = await page.evaluate(() => window.__raidLab.battle.elapsed);
  check('E 손을 떼면 멈추고 대고 있으면 흐르며 저절로 벤다', still.t < 0.05 && still.frozen && t1 > 0.2 && t2 === t1);
  await page.evaluate(() => { const b = window.__raidLab.battle; b.damage(b.boss, 120, '검증'); });
  await page.waitForSelector('#save');
  await page.locator('#fun').selectOption('4');
  await page.locator('#memo').fill('조작 비교');
  await page.locator('#save').click();
  await page.locator('#compare-now').click();
  const record = await page.evaluate(() => JSON.parse(localStorage.getItem('torch-raid-lab-v1')).at(-1));
  check('결과 평가 저장과 비교 표', record.fun === 4 && record.memo === '조작 비교' && await page.locator('table').count() === 1);
  check('페이지 오류 없음', errors.length === 0);
} finally { await browser.close(); await new Promise((resolve) => server.close(resolve)); }
