// 정착지 건설 1단계 확인 목록(docs/설계_정착지_건설.md §11)을 헤드리스 크롬에서 검사한다.
// 사용: node tests/settlement.mjs
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
await page.tap('#btn-start');

// 10. 새 게임: 줌인 연출, 누르면 건너뛴다
const s10 = await page.evaluate(async () => { const g = window.__game, T = g.Town; await new Promise((r) => setTimeout(r, 300)); const on = !!T.intro, z0 = g.View.dio.rig.zoom; T.tap(10, 10); await new Promise((r) => setTimeout(r, 120)); return { on, z0: +z0.toFixed(2), skipped: !T.intro, z1: +g.View.dio.rig.zoom.toFixed(2) }; });
check('§11-10 들어올 때 줌인, 누르면 건너뛴다', s10.on && s10.z0 > 1.5 && s10.skipped && s10.z1 <= 1.05, JSON.stringify(s10));
await page.waitForFunction(() => !window.__game.Town.busy, null, { timeout: 30000 });
await page.evaluate(() => { document.querySelector('#sheet').classList.add('hidden'); document.querySelector('#screen').classList.add('hidden'); });

// 셀 → 화면 좌표, 넓은 빈 땅 만들기
await page.evaluate(() => {
  const g = window.__game, D = g.View.dio;
  window.scr = (x, y) => { const s = {}; D.labels.toScreen(new D.THREE.Vector3(x, 0, y), s); return s; };
  window.flat = () => { g.META.glowMods = [{ v: 40, why: '시험' }]; g.Town.applyGlow(); const S = g.META.settle; for (let i = 0; i < S.terr.length; i++) { const x = i % 40, y = (i / 40) | 0; if (Math.abs(x - 20) + Math.abs(y - 20) > 3 && S.terr[i] !== 1 && !S.furn.some((f) => f.x === x && f.y === y)) S.terr[i] = 1; } g.Settle.invalidate(); g.Town.refreshWorld(); };
  // 빈 4×4 자리(청사진 16칸이 모두 새로 놓이는 곳)
  window.freeRect = (skip = []) => { const Z = g.Settle; for (let r = 3; r < 10; r++) for (let y = 20 - r; y <= 20 + r; y++) for (let x = 20 - r; x <= 20 + r; x++) { if (skip.some(([a, b]) => Math.abs(a - x) < 6 && Math.abs(b - y) < 6)) continue; const c = Z.checkBps(Z.roomBps(x, y, x + 3, y + 3)); if (c.ok.length === 16 && !c.bad.length && !g.META.settle.floor.some((v, i) => v && i % 40 >= x && i % 40 <= x + 3 && ((i / 40) | 0) >= y && ((i / 40) | 0) <= y + 3)) return [x, y]; } return null; };
  window.look = (x, y) => { D.rig.focusT.set(x, 0, y); D.rig.zoom = D.rig.zoomT = 1; D.rig.snap(); D.rig.update(0.016); D.camera.updateMatrixWorld(); };
});

// 1. 40×40, 반경 = 6 + 밝기 ÷ 10, 빛 밖은 빨강(못 놓음)
const s1 = await page.evaluate(() => { const g = window.__game, S = g.META.settle, Z = g.Settle; flat(); const R = Z.radius(), glow = g.hearthGlow();
  const out = Z.checkBps([{ L: 'wall', k: 'wood', x: 20, y: 20 + R + 2 }]); let inn = { ok: [] }; for (let d = 2; d < R && !inn.ok.length; d++) for (const [x, y] of [[20 + d, 20], [20 - d, 20], [20, 20 + d], [20, 20 - d]]) if (!inn.ok.length) inn = Z.checkBps([{ L: 'wall', k: 'wood', x, y }]);
  return { W: S.W, H: S.H, n: S.terr.length, R, want: Math.min(20, 6 + Math.floor(glow / 10)), outWhy: out.bad[0] && out.bad[0].why, inOk: inn.ok.length }; });
const s1b = await page.evaluate(() => { const g = window.__game, M = g.META, Z = g.Settle, lit = M.lit.slice(), r0 = Z.radius(); M.lit = [true, false, false, false]; const r1 = Z.radius(); M.lit = lit; const D = g.View.dio; return { r0, r1, pitch: +D.rig.pitchT.toFixed(2), top: +D.rig.TOP.toFixed(2), yaw: D.rig.yawT % (Math.PI * 2) }; });
check('등불 조각 하나 = 빛 반경 +4칸 이상(밝기 +10 → +1, 조각 +3), 정착지는 탑뷰로 시작', s1b.r1 - s1b.r0 >= 4 && s1b.pitch === s1b.top && s1b.yaw === 0, JSON.stringify(s1b));
check('§11-1 40×40 맵, 반경 6 + 밝기÷10, 빛 밖은 못 짓는다', s1.W === 40 && s1.H === 40 && s1.n === 1600 && s1.R === s1.want && /빛/.test(s1.outWhy) && s1.inOk === 1, JSON.stringify(s1));

// 2. 방 그리기 4×4 → 벽·바닥·문 청사진 + 비용
await page.evaluate(() => { const g = window.__game; window.R0 = freeRect(); g.Town.enterBuild(); window.stages = [g.Town.bm.stage]; g.Town.buildAct('cat', 'room'); stages.push(g.Town.bm.stage, document.querySelectorAll('#buildbar .bitem').length); g.Town.buildAct('item', 'draw'); stages.push(g.Town.bm.stage, document.querySelectorAll('#buildbar .bdraw button').length); look(R0[0] + 1.5, R0[1] + 1.5); });
const a2 = await page.evaluate(() => [scr(R0[0], R0[1]), scr(R0[0] + 3, R0[1] + 3)]);
await page.touchscreen.tap(a2[0].x, a2[0].y); await page.waitForTimeout(80);
const mag = await page.evaluate(() => { const T = window.__game.Town, m = !document.querySelector('#mag').classList.contains('hidden'), first = document.querySelector('#bstat').textContent; T.bm.cur = { x: R0[0] + 3, y: R0[1] + 3 }; T.previewRect(); const cost = document.querySelector('#bstat').textContent; T.bm.cur = T.bm.start; T.previewRect(); return { mag: m, stat: first, cost, stages }; });
await page.touchscreen.tap(a2[1].x, a2[1].y); await page.waitForTimeout(80);
const s2 = await page.evaluate(() => { const S = window.__game.META.settle, [x0, y0] = R0, cells = []; for (let y = y0; y <= y0 + 3; y++) for (let x = x0; x <= x0 + 3; x++) cells.push(y * 40 + x);
  return { walls: cells.filter((i) => S.wall[i] === 1).length, doors: cells.filter((i) => S.wall[i] === 3).length, floors: cells.filter((i) => S.floor[i] === 2).length, left: S.bp.length, wood: S.stock.나무 }; });
check('§11-2 방 그리기 4×4: 벽 11 · 문 1 · 바닥 4, 그리는 동안 비용이 보이고 놓으면 지어진다', s2.walls === 11 && s2.doors === 1 && s2.floors === 4 && s2.left === 0 && s2.wood === 10 && /🪵나무 30/.test(mag.cost), JSON.stringify({ ...s2, cost: mag.cost }));
check('건설 화면은 한 단계씩: 분류 → 물건 → 그리기(버튼 두셋)', mag.stages[0] === 'cats' && mag.stages[1] === 'items' && mag.stages[2] >= 8 && mag.stages[3] === 'draw' && mag.stages[4] <= 4, JSON.stringify(mag.stages));
// 3. 두 번 탭 사각형 + 돋보기
check('§11-3 두 번 탭으로 사각형, 첫 탭에 돋보기', mag.mag && /끝 칸|칸/.test(mag.stat), JSON.stringify(mag));

// 8. 지으면 나무·돌이 준다 / 모자라면 이유 / 베기·캐기로 는다
const s8 = await page.evaluate(() => { const g = window.__game, S = g.META.settle, Z = g.Settle, w0 = 40;
  const built = S.wall.filter((v) => v).length, w1 = S.stock.나무;
  S.stock.나무 = 0; S.stock.돌 = 0; const R1 = freeRect([R0]); g.Town.place(Z.roomBps(R1[0], R1[1], R1[0] + 3, R1[1] + 3, 'wood', 'wood')); const toast = document.querySelector('#toast').textContent, left = S.bp.length, red = S.bp.length > 0;
  S.bp = []; const free = []; for (let i = 0; i < 1600 && free.length < 2; i++) { const x = i % 40, y = (i / 40) | 0; if (Z.checkBps([{ L: 'furn', k: 'chair', x, y }]).ok.length && !S.floor[i]) free.push(i); }
  S.terr[free[0]] = 4; S.terr[free[1]] = 5; for (const i of free) Z.cutArea(i % 40, (i / 40) | 0, i % 40, (i / 40) | 0); const r = { gained: { 나무: S.stock.나무, 돌: S.stock.돌 } };
  return { w0, w1, built, toast, left, red, gained: r.gained, wood: S.stock.나무, stone: S.stock.돌 }; });
check('§11-8 지으면 나무가 줄고, 모자라면 이유와 빨간 청사진, 베기·캐기로 는다', s8.built >= 12 && s8.w1 < s8.w0 && /모자라/.test(s8.toast) && s8.left > 0 && s8.red && s8.wood === 8 && s8.stone === 6, JSON.stringify(s8));

// 7. 닫힌 방 인식 + 가구로 종류, 제작은 방 조건
const s7 = await page.evaluate(() => { const g = window.__game, S = g.META.settle, Z = g.Settle; S.stock.나무 = 200; S.stock.돌 = 200; g.META.mats.광석 = 20; S.bp = []; g.Town.refreshWorld();
  const [cx, cy] = [R0[0] + 1, R0[1] + 1], r0 = Z.roomAt(cx, cy); const empty = !!r0 && r0.kind === null;
  Z.placeBps([{ L: 'furn', k: 'anvil', x: cx, y: cy, rot: 0 }]); Z.commit(); const r1 = Z.roomAt(cx, cy);
  const kinds = Z.rooms().map((r) => r.kind), forge = Z.hasRoom('forge'), bld = !!g.META.buildings.forge;
  return { empty, kind: r1 && r1.kind, kinds, forge, bld }; });
check('§11-7 닫힌 방 인식 · 가구로 종류 · 제작은 방 조건', s7.empty && s7.kind === 'forge' && s7.forge && s7.bld && s7.kinds.includes('altar'), JSON.stringify(s7));
const s7b = await page.evaluate(() => { const g = window.__game, Z = g.Settle, S = g.META.settle; const keep = JSON.stringify(S);
  S.furn = S.furn.filter((f) => f.k !== 'anvil'); Z.invalidate();
  const no = !Z.hasRoom('forge'); g.Town.craft('forge'); const toast = document.querySelector('#toast').textContent;
  g.META.settle = JSON.parse(keep); Z.invalidate(); g.Town.refreshWorld(); return { no, toast, back: Z.hasRoom('forge') }; });
check('§11-7 작업방이 없으면 제작할 수 없다', s7b.no && /작업방/.test(s7b.toast) && s7b.back, JSON.stringify(s7b));

// 4. 되돌리기 20단계, 방 복사·회전·붙이기
const s4 = await page.evaluate(() => { const g = window.__game, Z = g.Settle; Z.clearHistory();
  const cells = []; for (let y = 10; y < 30 && cells.length < 23; y++) for (let x = 10; x < 30 && cells.length < 23; x++) if (Z.checkBps([{ L: 'wall', k: 'wood', x, y }]).ok.length) cells.push([x, y]);
  for (const [x, y] of cells) Z.placeBps([{ L: 'wall', k: 'wood', x, y }]);
  let n = 0; while (Z.undo()) n++; const bpAfter = g.META.settle.bp.length; let m = 0; while (Z.redo()) m++;
  const clip = Z.copyRoom(R0[0] + 1, R0[1] + 1), rot = Z.rotateClip(clip), flip = Z.flipClip(rot);
  return { n, bpAfter, m, clip: clip && { w: clip.w, h: clip.h, cells: clip.cells.length, furn: clip.furn.length }, rot: { w: rot.w, h: rot.h, furnRot: rot.furn[0] && rot.furn[0].rot }, pasted: Z.clipBps(flip, 10, 28).length }; });
check('§11-4 되돌리기 20단계 · 방 복사·회전·반전', s4.n === 20 && s4.bpAfter === 3 && s4.m === 20 && s4.clip && s4.clip.cells === 16 && s4.clip.furn === 1 && s4.pasted === 17, JSON.stringify(s4));
await page.evaluate(() => { const Z = window.__game.Settle, S = window.__game.META.settle; S.bp = []; Z.clearHistory(); window.__game.Town.refreshWorld(); });

// 5. 방 프리셋 → 추천 자리 2~3곳, 누르면 그 자리에
const s5 = await page.evaluate(() => { const g = window.__game, T = g.Town; T.buildAct('stop'); T.buildAct('back'); T.buildAct('cat', 'room'); T.buildAct('item', 'preset:library'); T.buildAct('size', 'S'); window.shelf0 = g.META.settle.furn.filter((f) => f.k === 'bookshelf').length; const spots = T.bm.spots.map((s) => [s.x, s.y, s.w, s.h]); window.sp0 = T.bm.spots[0]; look(sp0.x + 1, sp0.y + 1); return { n: spots.length, spots }; });
const p5 = await page.evaluate(() => scr(sp0.x + 1, sp0.y + 1));
await page.touchscreen.tap(p5.x, p5.y); await page.waitForTimeout(80);
const s5b = await page.evaluate(() => { const g = window.__game, S = g.META.settle, Z = g.Settle; return { shelf: S.furn.filter((f) => f.k === 'bookshelf').length + S.bp.filter((b) => b.k === 'bookshelf').length - shelf0, library: Z.hasRoom('library') }; });
check('§11-5 프리셋: 추천 자리 2~3곳, 누르면 그 자리에 지어진다', s5.n >= 2 && s5.n <= 3 && s5b.shelf === 1 && s5b.library, JSON.stringify({ ...s5, ...s5b }));

// 6. 알아서 짓기: 모자란 방(침대, 직업 작업방)을 한 번에
const s6 = await page.evaluate(() => { const g = window.__game, M = g.META, S = M.settle; S.bp = []; M.npcs.push({ ...M.npcs[0], id: 'nh', name: '사냥', job: 'hunter', rel: {} });
  const need = g.Settle.neededRooms().map(([k]) => k); g.Town.buildAct('auto'); const all = [...S.furn, ...S.bp], beds = all.filter((b) => b.k === 'bed').length, leather = all.filter((b) => b.k === 'leather').length;
  M.npcs.pop(); return { need, beds, leather }; });
check('§11-6 알아서 짓기: 침대·작업방을 한 번에', s6.need.includes('bedroom') && s6.need.includes('hunter') && s6.beds >= 2 && s6.leather === 1, JSON.stringify(s6));
await page.evaluate(() => { const g = window.__game; g.META.settle.bp = []; g.Town.exitBuild(); g.Town.refreshWorld(); });
await page.screenshot({ path: path.join(outDir, 'settlement.png') });

// 9. 옛 저장(고정 건물) → 같은 기능의 방
const s9 = await page.evaluate(() => { const g = window.__game;
  const old = { v: 8, gen: 1, visits: 3, cleared: [true, false, false, false], npcs: [], newNpcs: [], buildings: { plaza: { shown: true }, gate: { shown: true }, altar: { shown: true }, storage: { shown: true }, forge: { shown: true }, herb: { shown: true }, inn: { shown: true }, library: { shown: true } },
    mats: { 약초: 2 }, items: {}, recipes: {}, fallen: [], closed: {}, lit: [true, false, false, false], visitors: [], lore: [], glowMods: [], relics: [], unrandsSeen: [], gear: [], hero: null, rememberedKeepers: [] };
  localStorage.setItem('torch-meta-v3', JSON.stringify(old)); g.resetMetaForTest(); const M = g.loadMeta(); const Z = g.Settle;
  return { v: M.v, has: ['forge', 'herb', 'inn', 'library', 'altar'].map((k) => Z.hasRoom(k)), gate: M.settle.furn.some((f) => f.k === 'gate'), heap: M.settle.furn.some((f) => f.k === 'heap'), bld: Object.keys(M.buildings).sort().join() }; });
check('§11-9 옛 마을의 고정 건물이 같은 기능의 방으로', s9.v === 10 && s9.has.every(Boolean) && s9.gate && s9.heap && /forge/.test(s9.bld), JSON.stringify(s9));

check('§11-11 페이지 오류 없음', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close(); server.close();
const bad = results.filter((r) => !r).length;
console.log(bad ? `\n${bad}개 실패` : `\n모두 통과 (${results.length})`);
process.exit(bad ? 1 : 0);
