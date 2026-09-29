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
