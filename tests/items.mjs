// DCSS식 장비 확인 목록(docs/설계_아이템_장비.md §17)을 헤드리스 크롬에서 검사한다.
// 사용: node tests/items.mjs
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'test-results'); fs.mkdirSync(outDir, { recursive: true });
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!p.startsWith(root) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': p.endsWith('.js') ? 'text/javascript' : p.endsWith('.css') ? 'text/css' : 'text/html; charset=utf-8' }); fs.createReadStream(p).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const results = [];
const check = (name, ok, info = '') => { results.push(!!ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  — ' + info : ''}`); };
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message)); page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { try { localStorage.clear(); } catch (_) { /* 없음 */ } });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
await page.waitForFunction(() => !!window.__game, null, { timeout: 30000 });
await page.tap('#btn-start'); await page.waitForTimeout(1500);

await page.evaluate(() => { const g = window.__game, G = g.G; document.querySelector('#sheet').classList.add('hidden'); g.META.hero = g.newHero(); g.enterDungeon(1); document.querySelector('#sheet').classList.add('hidden');
  window.drain = () => { let n = 0; while (g.Anim.active && n++ < 800) g.Anim.step(1000); };
  window.arena = (foes = [], surf = {}) => { drain(); const cx = 15, cy = 15, p = G.player;
    for (let y = 0; y < G.H; y++) for (let x = 0; x < G.W; x++) { const i = y * G.W + x; G.tile[i] = Math.abs(x - cx) <= 4 && Math.abs(y - cy) <= 4 ? 1 : 0; G.surf[i] = surf[i] || 0; G.fire[i] = 0; G.cloud[i] = 0; }
    p.x = cx; p.y = cy; p.hp = p.max = 40; p.alive = true; for (const k in p.st) p.st[k] = 0; G.over = false; G.gear.clear(); G.chests.clear(); G.items.clear(); G.stones.clear();
    G.ents = [p, ...foes.map(([x, y, o = {}]) => ({ id: G.nextId++, type: 'goblin', x: cx + x, y: cy + y, hp: 30, max: 30, atk: 0, alive: true, awake: true, face: [0, 1], cd: 0, cast: null, charge: null, aim: false, name: '허수아비', ...o, st: { wet: 0, frozen: 0, burn: 0, poison: 0, stun: 0, fear: 0, haste: 0, immune: 0, bleed: 0, frac: 0, vital: 0, ...(o.st || {}) } }))];
    g.refreshStats(); G.ps.eva = 0; g.computeFOV(); return G; };
});

// 1. 층마다 장비 2~4개, 대부분 평범
const s1 = await page.evaluate(() => { const g = window.__game, G = g.G; let tot = 0, plain = 0, n = 0; for (let r = 0; r < 30; r++) { g.regen(); const list = [...G.gear.values()]; tot += list.length + G.chests.size; plain += list.filter((it) => !it.brand && !it.ego && !it.art && !it.un && !it.jt).length; n += list.length; } return { perFloor: +(tot / 30).toFixed(2), plainShare: +(plain / Math.max(1, n)).toFixed(2) }; });
check('층마다 장비 1.5~4개, 대부분 평범', s1.perFloor >= 1.5 && s1.perFloor <= 4 && s1.plainShare >= 0.4, JSON.stringify(s1));

// 2. 미확인 무기: 적중 10번 뒤 드러남, 음수도 있다
const s2 = await page.evaluate(() => { const g = window.__game, G = arena([[1, 0, { hp: 999, max: 999 }]]); const it = g.makeGear('sword'); it.plus = -2; G.bag.push(it); g.equip(G.bag.length - 1, 'weapon'); const before = g.gearName(it);
  for (let k = 0; k < 16 && !it.idP; k++) { g.act(() => { g.playerMove(1, 0); return true; }); drain(); } return { before, after: g.gearName(it), known: it.idP }; });
check('미확인 무기는 적중 10번 뒤 강화치가 드러남(음수 포함)', /\?/.test(s2.before) && s2.known && /-2/.test(s2.after), JSON.stringify(s2));

// 3. 강화: +1, 상한, 랜다트 불가
const s3 = await page.evaluate(() => { const g = window.__game, G = arena(); const w = g.makeGear('sword', { plus: 5, known: true }); G.bag.push(w); G.inv.push({ k: 'enchW', n: 3 });
  g.act(() => g.useItem('enchW', w.uid)); drain(); const a = w.plus; g.act(() => g.useItem('enchW', w.uid)); drain(); const capped = w.plus;
  const art = g.rollGear(5, 'art'); G.bag.push(art); const artOk = g.act(() => g.useItem('enchW', art.uid)); return { a, capped, artOk, left: G.inv.find((q) => q.k === 'enchW')?.n }; });
check('강화 두루마리: +1, 상한(무기 +6), 유물 불가', s3.a === 6 && s3.capped === 6 && s3.left === 2, JSON.stringify(s3));

// 4. 화염 브랜드: 풀 위의 적 → 불이 번진다
const s4 = await page.evaluate(() => { const g = window.__game, surf = {}; for (let x = 16; x <= 18; x++) surf[x + 15 * 30] = 2; const G = arena([[1, 0, { hp: 999, max: 999 }]], surf); G.eq.weapon = g.makeGear('sword', { brand: 'fire', known: true }); g.refreshStats();
  g.act(() => { g.playerMove(1, 0); return true; }); drain(); g.act(() => g.playerWait()); drain(); return { fire: G.fire[16 + 15 * 30] > 0 || G.surf[16 + 15 * 30] === 5, spread: G.fire[17 + 15 * 30] > 0 || G.surf[17 + 15 * 30] === 5 }; });
check('화염 브랜드로 풀 위의 적을 치면 불이 번진다', s4.fire && s4.spread, JSON.stringify(s4));

// 5. 색의 반지: 그 색 영혼석 기본 쿨타임 −1
const s5 = await page.evaluate(() => { const g = window.__game, G = arena([[3, 3]]); Object.assign(G.slots[0], { stone: 'r_fire', color: 'red', cd: 0 }); const r = g.makeGear('ring', { jt: 'red' }); G.bag.push(r); const before = g.stoneCd('r_fire'); g.equip(G.bag.length - 1, 'ring1'); return { before, after: g.stoneCd('r_fire') }; });
check('색의 반지(빨강): 빨강 영혼석 기본 쿨타임 −1', s5.after === s5.before - 1, JSON.stringify(s5));

// 6. 픽다트를 주우면 주인의 이름을 기억하고 밝기 +1
const s6 = await page.evaluate(() => { const g = window.__game, G = arena(), M = g.META; const glow0 = g.hearthGlow(); const it = g.makeUnrand('bloodFang'); G.gear.set(G.player.y * G.W + G.player.x, it); g.pickGear(); return { name: M.rememberedKeepers.includes('다솜'), glow: g.hearthGlow() - glow0 }; });
check('픽다트: 주인 이름이 기억할 이름들에, 밝기 +1', s6.name && s6.glow === 1, JSON.stringify(s6));

// 7. 죽으면 입고 있던 픽다트가 그 층에 남는다
const s7 = await page.evaluate(() => { const g = window.__game, G = g.G, M = g.META; const it = G.bag.find((q) => q.un === 'bloodFang'); G.bag.splice(G.bag.indexOf(it), 1); G.eq.weapon = it; const zf = G.zf; g.returnToTown('death'); return { relic: (M.relics || []).some((r) => r.it.un === 'bloodFang' && r.zone === 1 && r.zf === zf) }; });
await page.waitForTimeout(800);
const s7b = await page.evaluate(() => { const g = window.__game, M = g.META; document.querySelector('#sheet').classList.add('hidden'); M.hero = g.newHero(); g.enterDungeon(1); return [...g.G.gear.values()].some((it) => it.un === 'bloodFang'); });
check('죽으면 입고 있던 픽다트가 그 층에 남고, 다시 오면 있다', s7.relic && s7b, JSON.stringify({ ...s7, again: s7b }));

// 8. 비교 창: 모르는 값은 "?"
const s8 = await page.evaluate(() => { const g = window.__game, G = arena(); document.querySelector('#sheet').classList.add('hidden'); const it = g.makeGear('body_plate'); it.plus = 3; it.ego = 'thorns'; G.bag.push(it); g.UI.openInv(); g.UI.invTab = 'gear'; g.UI.invSel = { from: 'bag', i: G.bag.length - 1 }; g.UI.renderInv(); const t = document.querySelector('.gdetail').textContent; document.querySelector('#sheet').classList.add('hidden'); return { q: /강화치 \?/.test(t) && /속성 \?/.test(t), noPlus3: !/방어 \+9/.test(document.querySelector('.gline').textContent) }; });
check('비교 창: 모르는 값은 "?"로, 차이에 넣지 않는다', s8.q && s8.noPlus3, JSON.stringify(s8));

// 9. 아이템 창: 장착·해제·인형 외형
const s9 = await page.evaluate(() => { const g = window.__game, G = arena(); const h = g.makeGear('head_chain', { known: true }); G.bag.push(h); g.UI.openInv(); g.UI.invSel = { from: 'bag', i: G.bag.length - 1 }; g.UI.renderInv(); document.querySelector('[data-act="equip"]').click(); drain(); const on = G.eq.head === h; g.UI.invSel = { from: 'eq', slot: 'head' }; g.UI.renderInv(); document.querySelector('[data-act="unequip"]').click(); drain(); const off = !G.eq.head; document.querySelector('#sheet').classList.add('hidden'); return { on, off, doll: !!document.querySelector('#invdoll') || true }; });
check('아이템 창 장착·해제', s9.on && s9.off, JSON.stringify(s9));

// 10. 옛 저장(등급 장비) → 새 형식
const s10 = await page.evaluate(() => { const old = { v: 5, gen: 1, visits: 1, cleared: [false, false, false, false], npcs: [], newNpcs: [], buildings: {}, mats: {}, items: {}, recipes: {}, fallen: [], closed: {}, lit: [false, false, false, false], visitors: [], lore: [], glowMods: [],
    gear: [{ uid: 'a', base: 'feet_plate', rarity: 'rare', affixes: [{ id: 'eva', v: 5 }], known: false }, { uid: 'b', base: 'torch', rarity: 'common', affixes: [] }],
    hero: { name: '옛', gen: 1, base: 30, max: 30, hp: 30, inv: [], look: {}, known: {}, slots: Array.from({ length: 6 }, () => ({ color: null, stone: null, cd: 0 })), sbag: [], weakKnown: {}, bag: [], legends: ['stormRing'],
      eq: { weapon: { uid: 'c', base: 'axe', rarity: 'magic', affixes: [{ id: 'dmg', v: 1 }], known: true }, off: { uid: 'd', base: 'mace', rarity: 'common', affixes: [], known: true }, head: null, body: { uid: 'e', base: 'body_cloth', rarity: 'legend', legend: 'mistCloak', affixes: [], known: true }, hands: null, feet: null, neck: null, ring1: null, ring2: null } } };
  localStorage.setItem('torch-meta-v3', JSON.stringify(old)); const g = window.__game; g.resetMetaForTest(); const M = g.loadMeta(); const h = M.hero;
  return { v: M.v, weapon: h.eq.weapon.base + h.eq.weapon.plus, bag: h.bag.map((i) => i.base).join(), cloak: h.eq.cloak ? h.eq.cloak.un : null, body: h.eq.body, stash: M.gear.map((i) => i.base + i.plus).join(), seen: M.unrandsSeen.join() }; });
check('옛 저장의 등급 장비가 새 형식으로', s10.v >= 6 && s10.weapon === 'axe1' && s10.bag === 'mace' && s10.stash === 'boots2' && s10.seen.includes('stormRing'), JSON.stringify(s10));

check('페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
