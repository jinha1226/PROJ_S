// 동작이 바뀌지 않았는지 확인하는 비교 도구 (리팩터링용).
// 두 페이지에 같은 Math.random·Date.now를 넣고 같은 각본(정착지 → 원정 → 전투 → 보스층 → 귀환 → 영혼석 24종)을 돌려
// 시점마다 게임 상태를 JSON으로 비교한다. 기능을 바꾼 뒤에는 당연히 달라진다 — 옮기기만 한 정리에 쓴다.
// 사용: node tools/equivalence.mjs versions/v3.html index.html
import { chromium } from 'playwright';
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const [FA = 'versions/v3.html', FB = 'index.html'] = process.argv.slice(2);
const serve = (root) => new Promise((r) => { const s = http.createServer((q, res) => { const p = path.join(root, decodeURIComponent(new URL(q.url, 'http://x').pathname)); if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; } res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : 'text/html; charset=utf-8' }); fs.createReadStream(p).pipe(res); }); s.listen(0, () => r(s)); });
const INIT = `(() => { let a = 777; Math.random = function () { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; Date.now = () => 1790000000000; try { localStorage.clear(); } catch (_) {} })();`;
const SCENARIO = () => {
  const g = window.__game, { UI, Anim } = g, snaps = [];
  const mk = (seed) => { let a = seed; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const drain = () => { let n = 0; while (Anim.active && n++ < 2000) Anim.step(1000); };
  const G = () => g.G;
  const snapG = (tag) => { const s = G(); snaps.push([tag, JSON.stringify({ zone: s.zone, zf: s.zf, floor: s.floor, over: s.over, tile: Array.from(s.tile), surf: Array.from(s.surf), fire: Array.from(s.fire), cloud: Array.from(s.cloud), seen: Array.from(s.seen), ents: s.ents.map((e) => [e.id, e.type, e.x, e.y, e.hp, e.max, e.alive, e.awake, e.name, JSON.stringify(e.st), e.cast && e.cast.tiles, e.charge, e.aim, e.freed]), inv: s.inv, slots: s.slots, sbag: s.sbag, stats: s.stats, cd: s.cd, loot: s.loot, items: [...s.items], stones: [...s.stones], weps: [...s.weps], mats: s.mats && [...s.mats], p: [s.player.hp, s.player.shield, JSON.stringify(s.player.st)] })]); };
  const snapM = (tag) => { const M = g.META; snaps.push([tag, JSON.stringify({ npcs: M.npcs.map((n) => [n.name, n.job, n.t, n.mood, n.rel && Object.values(n.rel)]), mats: M.mats, items: M.items, cleared: M.cleared, weapons: M.weapons, armors: M.armors, hero: M.hero && [M.hero.name, M.hero.hp, M.hero.max, M.hero.wpn, M.hero.slots], fallen: M.fallen, recipes: M.recipes, visits: M.visits, newNpcs: M.newNpcs.map((n) => n.name), closed: M.closed })]); };
  let rng = mk(42); const reseed = (s) => { Math.random = mk(s); };
  reseed(1); UI.start(); snapM('town-first');
  document.querySelector('#sheet').classList.add('hidden');
  const M = g.META; M.hero = g.newHero(); for (const id of ['r_fire', 'r_bleed', 'r_extra', 'g_counter', 'p_wet', 'p_shield']) g.addStone.call ? null : null;
  reseed(2); g.enterDungeon(1); snapG('d1-start');
  for (const id of ['r_fire', 'r_bleed', 'g_counter', 'p_wet', 'p_shield', 'g_push']) g.addStone(id);
  const D8 = [[0, -1], [1, 0], [0, 1], [-1, 0], [1, -1], [1, 1], [-1, 1], [-1, -1]];
  const play = (n, tag) => {
    for (const e of G().ents) if (!e.ally) e.awake = true;
    for (let t = 0; t < n; t++) {
      const s = G(), p = s.player; if (s.over || g.Game.mode !== 'dungeon') break;
      if (p.st.frozen || p.st.stun) { g.act(() => { if (p.st.frozen) p.st.frozen--; if (p.st.stun) p.st.stun--; return true; }); drain(); continue; }
      const r = rng();
      if (r < 0.18) { const sk = ['push', 'fire', 'bolt', 'frost', 'venom'].filter((k) => s.cd[k] === 0); if (sk.length) { UI.skillBtn(sk[Math.floor(rng() * sk.length)]); const v = [...UI.valid].sort((a, b) => a - b); if (v.length && UI.mode === 'target') { const i = v[Math.floor(rng() * v.length)]; UI.tapTarget(i % s.W, (i / s.W) | 0); UI.tapTarget(i % s.W, (i / s.W) | 0); } else UI.exitTarget(); drain(); continue; } }
      if (r < 0.24 && s.inv.length) { const q = s.inv[Math.floor(rng() * s.inv.length)]; if (q.k !== 'recall') { UI.useFromBag(q.k); if (UI.mode === 'target') { const v = [...UI.valid].sort((a, b) => a - b); if (v.length) { const i = v[Math.floor(rng() * v.length)]; UI.tapTarget(i % s.W, (i / s.W) | 0); UI.tapTarget(i % s.W, (i / s.W) | 0); } else UI.exitTarget(); } drain(); continue; } }
      if (r < 0.32) { UI.waitBtn(); drain(); continue; }
      const foes = s.ents.filter((e) => e.alive && e !== p && !e.ally).sort((a, b) => Math.max(Math.abs(a.x - p.x), Math.abs(a.y - p.y)) - Math.max(Math.abs(b.x - p.x), Math.abs(b.y - p.y)) || a.id - b.id);
      let d = null;
      if (foes.length && rng() < 0.7) { d = [Math.sign(foes[0].x - p.x), Math.sign(foes[0].y - p.y)]; if (s.tile[(p.y + d[1]) * s.W + p.x + d[0]] === 0) d = null; }
      if (!d) { const o = D8.filter(([dx, dy]) => s.tile[(p.y + dy) * s.W + p.x + dx] !== 0); d = o[Math.floor(rng() * o.length)]; }
      if (d) UI.tapTile(p.x + d[0], p.y + d[1]); drain();
      if (s.player.hp < 8 && !s.over) { s.player.hp = s.player.max; }
    }
    snapG(tag);
  };
  play(150, 'd1-150');
  { const s = G(), p = s.player; p.x = s.stairs % s.W; p.y = (s.stairs / s.W) | 0; s.tile[s.stairs] = 4; reseed(3); g.descend(); snapG('d2-start'); }
  play(150, 'd2-150');
  { const s = G(), p = s.player; p.x = s.stairs % s.W; p.y = (s.stairs / s.W) | 0; s.tile[s.stairs] = 4; g.descend(); snapG('boss-start'); }
  play(120, 'boss-120');
  reseed(4); g.returnToTown('recall'); snapM('town-return');
  // 영혼석 24종 아레나: 젖은·출혈 적 둘, 한 종씩
  reseed(5); g.META.hero.hp = g.META.hero.max; g.enterDungeon(1);
  for (const id of Object.keys(g.STONE)) {
    const s = G(), cx = 15, cy = 15, p = s.player;
    for (let y = 0; y < s.H; y++) for (let x = 0; x < s.W; x++) { const i = y * s.W + x; s.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? 1 : 0; s.surf[i] = (x === cx + 2 && Math.abs(y - cy) <= 1) ? 1 : (x === cx - 1 && y === cy + 2) ? 3 : 0; s.fire[i] = 0; s.cloud[i] = 0; }
    p.x = cx; p.y = cy; p.hp = 20; p.shield = 0; p.alive = true; s.over = false;
    const mk = (x, y, type) => ({ id: s.nextId++, type, x, y, hp: 14, max: 14, atk: 3, st: { wet: 3, frozen: 0, burn: 0, poison: 2, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 3, frac: 0, vital: 1 }, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: 'T', elem: 'bolt' });
    s.ents = [p, mk(cx + 1, cy, 'goblin'), mk(cx + 2, cy + 1, 'goblin'), mk(cx - 2, cy - 2, 'archer')];
    s.slots.forEach((q) => { q.stone = null; q.color = null; q.cd = 0; q.gTurn = -1; });
    g.addStone(id); g.addStone('r_extra'); g.addStone('g_counter'); g.computeFOV();
    const c = g.STONE[id].color;
    for (let k = 0; k < 3; k++) { if (c === 'purple') g.act(() => g.playerWait()); else if (s.ents[1].alive) g.act(() => { g.playerMove(1, 0); return true; }); else g.act(() => true); drain(); }
    snapG('stone-' + id);
  }
  return snaps;
};
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const run = async (root, file) => {
  const s = await serve(root), page = await browser.newPage({ viewport: { width: 390, height: 844 } }), errs = [];
  page.on('pageerror', (e) => errs.push(e.message));
  await page.addInitScript(INIT);
  await page.goto(`http://127.0.0.1:${s.address().port}/${file}`);
  await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
  const snaps = await page.evaluate(SCENARIO);
  await page.close(); s.close();
  return { snaps, errs };
};
const A = await run(ROOT, FA), B = await run(ROOT, FB);
let same = 0;
for (let i = 0; i < A.snaps.length; i++) { const [t, a] = A.snaps[i], b = B.snaps[i] && B.snaps[i][1]; const ok = a === b; if (ok) same++; console.log(`${ok ? 'SAME' : 'DIFF'}  ${t}  (${a.length} bytes)`); if (!ok) { let k = 0; while (a[k] === b[k]) k++; console.log('   원본: …' + a.slice(Math.max(0, k - 80), k + 80)); console.log('   정리: …' + (b || '').slice(Math.max(0, k - 80), k + 80)); } }
for (const [t, a] of A.snaps) { const o = JSON.parse(a); if (o.stats) console.log("  ", t, "turns", o.stats.turns, "kills", o.stats.kills, "combos", o.stats.combos, "stones", o.stats.chains, "over", o.over, "alive", o.ents.filter((e) => e[6]).length); }
const allSame = same === A.snaps.length && B.snaps.length === A.snaps.length;
console.log(`${same}/${A.snaps.length} 동일 · 오류 원본 ${A.errs.length} / 정리본 ${B.errs.length}`, A.errs.concat(B.errs).slice(0, 3));
await browser.close();
process.exit(allSame && !A.errs.length && !B.errs.length ? 0 : 1);
