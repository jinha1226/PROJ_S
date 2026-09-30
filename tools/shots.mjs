// 그래픽 확인용 스크린샷(헤드리스): node tools/shots.mjs [이름 접두사]
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'), out = path.join(root, 'test-results'), pre = process.argv[2] || 'look';
fs.mkdirSync(out, { recursive: true });
const server = http.createServer((req, res) => { const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname)); if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; } res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : 'text/html; charset=utf-8' }); fs.createReadStream(p).pipe(res); });
await new Promise((r) => server.listen(0, r));
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, hasTouch: true });
const errors = []; page.on('pageerror', (e) => errors.push(e.message)); page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { try { localStorage.clear(); } catch (_) { /* 없음 */ } });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html?seed=7`);
await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
await page.screenshot({ path: path.join(out, `${pre}-title.png`) });
await page.tap('#btn-start'); await page.waitForTimeout(2500);
await page.evaluate(() => { document.querySelector('#sheet').classList.add('hidden'); const g = window.__game, M = g.META; M.fallen.push({ name: '아린', gen: 1, zone: 1, zf: 2, kills: 4 }); M.lit[0] = true; g.Town.build(); g.Town.renderHud(); });
await page.waitForTimeout(2500);
await page.screenshot({ path: path.join(out, `${pre}-town.png`) });
await page.evaluate(() => { const r = window.__game.View.dio.rig; r.zoomT = 0.55; r.pitchT = r.QUARTER; });
await page.waitForTimeout(2000);
await page.screenshot({ path: path.join(out, `${pre}-townclose.png`) });
await page.evaluate(() => { const r = window.__game.View.dio.rig; r.zoomT = 1.7; r.pitchT = r.TOP; });
await page.waitForTimeout(2000);
await page.screenshot({ path: path.join(out, `${pre}-townfar.png`) });
await page.evaluate(() => { const r = window.__game.View.dio.rig; r.zoomT = 1; });
await page.evaluate(() => { const g = window.__game; g.META.hero = g.newHero(); g.enterDungeon(1); const G = g.G, p = G.player;
  // 주인공 옆에 적 몇
  const spots = [[2, 0, 'goblin'], [-2, 1, 'archer'], [1, -2, 'mage'], [3, 2, 'charger']]; for (const [dx, dy, t] of spots) { const x = p.x + dx, y = p.y + dy; if (G.tile[y * G.W + x] !== 1) continue; const e = { id: G.nextId++, type: t, x, y, hp: 8, max: 8, atk: 2, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0 }, alive: true, awake: true, face: [0, 1], cd: 0, name: t, elem: 'fire' }; G.ents.push(e); }
  g.computeFOV(); g.View.buildFloor(); g.UI.syncAll(); });
await page.waitForTimeout(2500);
await page.screenshot({ path: path.join(out, `${pre}-dungeon.png`) });
await page.evaluate(() => { const r = window.__game.View.dio.rig; r.zoomT = 0.5; r.pitchT = r.QUARTER; document.querySelector('#floorcard').classList.remove('on'); });
await page.waitForTimeout(2000);
await page.screenshot({ path: path.join(out, `${pre}-close.png`) });
console.log(errors.length ? errors.slice(0, 5).join('\n') : 'ok');
await browser.close(); server.close();
