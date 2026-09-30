// 헤드리스 크롬으로 index.html(과 이전 버전)을 열어 핵심 흐름이 오류 없이 도는지 본다.
// 사용: node tests/smoke.mjs   (CI: GitHub Actions)
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'test-results');
fs.mkdirSync(outDir, { recursive: true });
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TYPES[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;

const results = [];
const check = (name, ok, info = '') => { results.push({ name, ok: !!ok, info }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  — ' + info : ''}`); };

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const errors = [];
async function openPage(file) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, hasTouch: true });
  page.on('pageerror', (e) => errors.push(`${file}: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`${file} console: ${m.text()}`); });
  await page.goto(`${base}/${file}`);
  await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
  await page.waitForTimeout(1500);
  return page;
}

try {
  { const p = await openPage('dungeon.html'); check('dungeon.html 주소에서 최신 게임 로드', new URL(p.url()).pathname === '/index.html'); await p.close(); }

  const page = await openPage('index.html');
  await page.screenshot({ path: path.join(outDir, '0-title.png') });
  check('타이틀 화면', await page.isVisible('#btn-start'));

  await page.tap('#btn-start');
  await page.waitForTimeout(2500);
  check('정착지 진입', (await page.evaluate(() => window.__game.Game.mode)) === 'town');
  await page.screenshot({ path: path.join(outDir, '1-town.png') });

  await page.evaluate(() => { document.querySelector('#sheet').classList.add('hidden'); window.__game.Town.busy = false; window.__game.Town.gate(); });
  await page.tap('#btn-depart');
  await page.waitForTimeout(3000);
  const d = await page.evaluate(() => ({ mode: window.__game.Game.mode, ents: window.__game.G.ents.length, zone: window.__game.G.zone }));
  check('원정 출발 → 던전', d.mode === 'dungeon' && d.ents > 1, JSON.stringify(d));
  await page.screenshot({ path: path.join(outDir, '2-dungeon.png') });
  const hud = await page.evaluate(() => {
    const g = window.__game, { G, UI } = g, before = G.torch;
    const C = g.clock; C.setIntent(null, true); for (let k = 0; k < 6; k++) C.step(); C.setIntent(null, false); // 옛 1턴 = 걸음 박자 0.3초
    const burn = before - G.torch;
    G.torch = 40; G.lamps.set(G.player.y * G.W + G.player.x, '이솔');
    const known = (g.META.rememberedKeepers || []).length;
    UI.syncAll(); UI.ctxBtn();
    const lamp = G.torch === 80 && !G.lamps.has(G.player.y * G.W + G.player.x) && g.META.rememberedKeepers.length === known + 1;
    G.torch = before; g.META.hero.torch = before; UI.syncAll();
    return { burn, lamp, souls: getComputedStyle(document.querySelector('#souls')).display, quick: document.querySelectorAll('#quick .qs').length, actions: document.querySelectorAll('#actions button').length };
  });
  check('모바일 HUD 퀵슬롯 6 · 영혼석 칸 꺼짐 · 5개 행동', hud.souls === 'none' && hud.quick === 6 && hud.actions === 5, JSON.stringify(hud));
  check('횃불 소모와 등잔 보충', hud.burn === 0.5 && hud.lamp, JSON.stringify(hud));

  // 무작위 걷기 30초(600틱): 조이스틱 방향을 20틱마다 바꾼다
  const play = await page.evaluate(() => {
    const g = window.__game, { G } = g, C = g.clock;
    let ticks = 0, dir = [1, 0];
    for (let t = 0; t < 600 && !G.over && g.Game.mode === 'dungeon'; t++) {
      if (t % 20 === 0) { const a = Math.random() * Math.PI * 2; dir = [Math.cos(a), Math.sin(a)]; }
      C.setIntent(dir, false); C.step(); ticks++;
    }
    C.setIntent(null, false);
    return { ticks, turns: G.stats.turns, over: G.over };
  });
  check('무작위 걷기 30초', play.turns >= 90 || play.over, JSON.stringify(play));


  // 보스 층 → 처치 → 귀환
  await page.evaluate(() => { const g = window.__game; g.returnToTown('recall'); });
  await page.waitForTimeout(1500);
  const boss = await page.evaluate(() => {
    const g = window.__game, G = g.G, M = g.META;
    document.querySelector('#sheet').classList.add('hidden');
    if (!M.hero) M.hero = g.newHero();
        g.enterDungeon(1);
    G.zf = 4; const p = G.player; p.x = G.stairs % G.W; p.y = (G.stairs / G.W) | 0; G.tile[G.stairs] = 4; g.descend(); // 구역 = 5층: 4층에서 내려가면 보스층
    const b = G.ents.find((e) => e.boss);
    if (!b) return { ok: false, why: 'no boss' };
    b.hp = 1; b.awake = true;
    // 무기로 마지막 한 대
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const x = b.x + dx, y = b.y + dy; if (G.tile[y * G.W + x] === 1 && !G.ents.some((e) => e.alive && e.x === x && e.y === y)) { p.x = x; p.y = y; break; } }
    g.computeFOV();
    g.clock.initClock(); g.clock.setIntent(null, true); for (let k = 0; k < 30 && b.alive; k++) g.clock.step(); g.clock.setIntent(null, false); // 닿은 적을 저절로 친다
    const open = G.exitOpen;
    p.x = G.stairs % G.W; p.y = (G.stairs / G.W) | 0; g.descend();
    return { ok: open, mode: g.Game.mode, cleared: M.cleared[0] };
  });
  await page.waitForTimeout(4000);
  check('보스 처치 → 귀환', boss.ok && boss.mode === 'town' && boss.cleared, JSON.stringify(boss));
  await page.screenshot({ path: path.join(outDir, '3-return.png') });
  await page.close();
} catch (e) {
  check('예외 없이 완료', false, String(e && e.stack || e));
}
check('페이지 오류 없음', errors.length === 0, errors.slice(0, 5).join(' | '));
await browser.close();
server.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} 통과`);
process.exit(failed.length ? 1 : 0);
