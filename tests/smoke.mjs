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
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.png': 'image/png' };
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
  // 이전 버전도 뜨는지만 본다
  for (const f of ['versions/v1.html', 'versions/v2.html', 'versions/v3.html']) {
    const before = errors.length, p = await openPage(f);
    check(`${f} 로드`, errors.length === before, errors.slice(before).join(' | '));
    await p.close();
  }

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

  // 무작위 200턴 (연출은 즉시 소화)
  const play = await page.evaluate(() => {
    const g = window.__game, { G, UI, Anim } = g, D8 = [[0, -1], [1, 0], [0, 1], [-1, 0], [1, -1], [1, 1], [-1, 1], [-1, -1]];
    const drain = () => { let n = 0; while (Anim.active && n++ < 800) Anim.step(1000); };
    const ids = Object.keys(g.STONE); for (let k = 0; k < 6; k++) g.addStone(ids[(k * 5) % ids.length]);
    let turns = 0;
    for (let t = 0; t < 200 && !G.over && g.Game.mode === 'dungeon'; t++) {
      const p = G.player;
      if (p.st.frozen || p.st.stun) { g.act(() => { if (p.st.frozen) p.st.frozen--; if (p.st.stun) p.st.stun--; return true; }); drain(); continue; }
      const r = Math.random();
      if (r < 0.25) { const ks = [0, 1, 2, 3, 4, 5].filter((k) => G.slots[k].stone && !G.slots[k].cd); if (ks.length) { const k = ks[t % ks.length]; UI.stoneBtn(k); if (UI.pend && UI.pend.self) UI.stoneBtn(k); else { const v = [...UI.valid]; if (v.length && UI.mode === 'target') { const i = v[t % v.length]; UI.tapTarget(i % G.W, (i / G.W) | 0); UI.tapTarget(i % G.W, (i / G.W) | 0); } else UI.exitTarget(); } drain(); turns++; continue; } }
      if (r < 0.3) { UI.waitBtn(); drain(); turns++; continue; }
      const o = D8.filter(([dx, dy]) => G.tile[(p.y + dy) * G.W + p.x + dx] !== 0), [dx, dy] = o[Math.floor(Math.random() * o.length)];
      UI.tapTile(p.x + dx, p.y + dy); drain(); turns++;
    }
    return { turns, over: G.over };
  });
  check('무작위 200턴', play.turns > 50 || play.over, JSON.stringify(play));

  // 영혼석 24종이 각각 발동하는지
  const stones = await page.evaluate(() => {
    const g = window.__game, { G, Anim } = g, out = {};
    const drain = () => { let n = 0; while (Anim.active && n++ < 800) Anim.step(1000); };
    let fired = []; const on = g.View.on.bind(g.View); g.View.on = (t, d2) => { if (t === 'stone') fired.push(d2.id); return on(t, d2); };
    for (const id of Object.keys(g.STONE)) {
      const cx = 15, cy = 15, p = G.player;
      for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? 1 : 0; G.surf[i] = 0; G.fire[i] = 0; G.cloud[i] = 0; }
      p.x = cx; p.y = cy; p.hp = 20; p.shield = 0; p.alive = true; G.over = false; for (const k in p.st) p.st[k] = 0; G.auras = {};
      const mk = (x, y) => ({ id: G.nextId++, type: 'goblin', x, y, hp: 30, max: 30, atk: 2, st: { wet: 3, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 3, frac: 0, vital: 0 }, alive: true, awake: true, face: [0, 1], cd: 0, name: 'T' });
      G.ents = [p, mk(cx + 1, cy), mk(cx - 2, cy - 2)];
      G.slots.forEach((q) => { q.stone = null; q.color = null; q.cd = 0; });
      g.addStone(id); g.computeFOV();
      if (G.ps) { G.ps.eva = 0; G.ps.block = 0; }
      fired = [];
      const T = g.STONE[id].tgt.t, at = T === 'empty' ? [cx, cy + 1] : T === 'self' || T === 'around' || T === 'sight' ? [] : [cx + 1, cy];
      drain(); // 앞 단계(무작위 200턴)의 연출이 남아 있으면 act가 무시된다
      let ok = false; g.act(() => (ok = g.useStone(0, ...at))); drain();
      out[id] = ok && fired.includes(id) && G.slots[0].cd >= 0;
    }
    g.View.on = on;
    return Object.entries(out).filter(([, v]) => !v).map(([k]) => k);
  });
  check('영혼석 스킬 24종 사용', stones.length === 0, stones.length ? '안 터짐: ' + stones.join(',') : '');

  // 보스 층 → 처치 → 귀환
  await page.evaluate(() => { const g = window.__game; g.returnToTown('recall'); });
  await page.waitForTimeout(1500);
  const boss = await page.evaluate(() => {
    const g = window.__game, G = g.G, M = g.META;
    document.querySelector('#sheet').classList.add('hidden');
    if (!M.hero) M.hero = g.newHero();
        g.enterDungeon(1);
    G.zf = 2; const p = G.player; p.x = G.stairs % G.W; p.y = (G.stairs / G.W) | 0; G.tile[G.stairs] = 4; g.descend();
    const b = G.ents.find((e) => e.boss);
    if (!b) return { ok: false, why: 'no boss' };
    b.hp = 1; b.awake = true;
    // 무기로 마지막 한 대
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const x = b.x + dx, y = b.y + dy; if (G.tile[y * G.W + x] === 1 && !G.ents.some((e) => e.alive && e.x === x && e.y === y)) { p.x = x; p.y = y; break; } }
    g.computeFOV();
    g.act(() => { g.playerMove(Math.sign(b.x - p.x), Math.sign(b.y - p.y)); return true; });
    let n = 0; while (g.Anim.active && n++ < 800) g.Anim.step(1000);
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
