/* ================= 스타일 실험실: 장면 자료 + 시간에 따른 상태 =================
   세 스타일(A 디오라마 · B 로우폴리 · C 2D)이 같은 자료와 같은 sample(t)를 그린다.
   좌표: 칸 (x, y), 칸 중심이 정수. x 오른쪽, y 아래(3D에서는 z). 멈춤이면 t가 멈추므로 모든 움직임이 t만의 함수다. */

/** 역할 색 (위협색 붉은 주황과 겹치지 않게) */
export const ROLE_COLOR = { hero: '#e8c070', guard: '#6b9be0', sword: '#b08ce6', archer: '#4fbdb2', healer: '#93d46c', res: '#d9cfb8' };
export const THREAT = '#ff5a24';

/* 칸 기호. 던전: # 벽 . 돌바닥 ~ 물 " 풀 / 정착지: g 풀 . 흙 W 나무 벽 S 돌 벽 D 문 = 나무 바닥 f 밭 s 창고 */
const DUNGEON_MAP = [
  '############',
  '#..........#',
  '#.""".....##',
  '#."""......#',
  '#........#.#',
  '#..........#',
  '#.#........#',
  '#......~~..#',
  '#......~~~.#',
  '#..........#',
  '#..........#',
  '############',
];

const SETTLE_MAP = [
  'gggggggggggggg',
  'gWWWWWgSSSSSSg',
  'gW===WgS====Sg',
  'gW===WgS====Sg',
  'gW===WgS====Sg',
  'gWWDWWgSSDSSSg',
  'gg....g.....gg',
  'g............g',
  'gg...........g',
  'gffff.......gg',
  'gffff....sssgg',
  'gffff....sssgg',
  'gffff.......gg',
  'gggggggggggggg',
];

export const SCENES = {
  dungeon: {
    id: 'dungeon', name: '던전 전투', w: 12, h: 12, map: DUNGEON_MAP,
    props: [],
    light: { kind: 'torch', r: 4.6 },
    actors: [
      { id: 'hero', kind: 'hero', side: 'ally', role: 'hero', x: 5.2, y: 7.4, face: [0.45, -1], act: 'swing' },
      { id: 'guard', kind: 'guard', side: 'ally', role: 'guard', x: 4.1, y: 6.1, face: [0, -1], act: 'block' },
      { id: 'sword', kind: 'sword', side: 'ally', role: 'sword', x: 7.4, y: 6.3, face: [0.8, -1], act: 'fight' },
      { id: 'archer', kind: 'archer', side: 'ally', role: 'archer', x: 2.7, y: 8.7, face: [1, -0.6], act: 'shoot' },
      { id: 'healer', kind: 'healer', side: 'ally', role: 'healer', x: 5.0, y: 9.4, face: [-0.3, -1], act: 'cast' },
      { id: 'gobA', kind: 'goblin', side: 'foe', x: 4.0, y: 4.9, face: [0, 1], act: 'windup' },
      { id: 'gobB', kind: 'goblin', side: 'foe', x: 5.9, y: 6.1, face: [-0.45, 1], act: 'hurt' },
      { id: 'gobC', kind: 'goblin', side: 'foe', x: 8.3, y: 5.3, face: [-0.8, 1], act: 'fight' },
      { id: 'skel', kind: 'skeleton', side: 'foe', x: 9.6, y: 2.3, face: [-1, 0.8], act: 'shoot' },
      { id: 'boss', kind: 'boss', side: 'foe', x: 5.7, y: 2.4, face: [0, 1], act: 'charge', big: true },
    ],
    // 반복되는 연출(주기 초)
    tele: [
      { type: 'fan', from: 'boss', ang: Math.PI / 2 - 0.05, r: 3.6, half: 0.78, period: 3.2, phase: 0 },
      { type: 'circle', x: 2.7, y: 8.7, r: 1.15, period: 2.6, phase: 1.1 },
    ],
    shots: [
      { from: 'skel', to: 'guard', foe: true, period: 1.9, phase: 0.4, speed: 9 },
      { from: 'archer', to: 'gobC', foe: false, period: 1.6, phase: 0, speed: 11 },
    ],
  },
  settle: {
    id: 'settle', name: '정착지', w: 14, h: 14, map: SETTLE_MAP,
    hearth: { x: 7, y: 7 },
    light: { kind: 'hearth', r: 5.4 },
    props: [
      { k: 'bed', x: 2, y: 2, w: 1, h: 2 }, { k: 'bed', x: 4, y: 2, w: 1, h: 2 },
      { k: 'lamp', x: 3, y: 4, w: 1, h: 1 },
      { k: 'table', x: 8, y: 2, w: 2, h: 1 }, { k: 'chair', x: 8, y: 3, w: 1, h: 1, rot: 2 }, { k: 'chair', x: 9, y: 3, w: 1, h: 1, rot: 2 },
      { k: 'shelf', x: 11, y: 2, w: 1, h: 1 },
      { k: 'bench', x: 10, y: 4, w: 2, h: 1, rot: 2 },
      { k: 'tree', x: 13, y: 6, w: 1, h: 1 }, { k: 'tree', x: 12, y: 12, w: 1, h: 1 }, { k: 'tree', x: 0, y: 12, w: 1, h: 1 },
      { k: 'rock', x: 7, y: 12, w: 1, h: 1 }, { k: 'rock', x: 12, y: 8, w: 1, h: 1 }, { k: 'rock', x: 0, y: 7, w: 1, h: 1 },
      { k: 'logs', x: 9, y: 10, w: 1, h: 1 }, { k: 'crate', x: 10, y: 10, w: 1, h: 1 }, { k: 'crate', x: 10, y: 11, w: 1, h: 1 }, { k: 'stones', x: 11, y: 10, w: 1, h: 1 }, { k: 'sack', x: 11, y: 11, w: 1, h: 1 }, { k: 'logs', x: 9, y: 11, w: 1, h: 1 },
    ],
    actors: [
      { id: 'r1', kind: 'res', side: 'res', role: 'res', cloth: 0x7d6a55, hair: 0x3b2a20, job: 'walk', path: [[5, 8.4], [9.4, 8.4], [9.4, 6.4], [5, 6.4]], loop: true, speed: 1.1 },
      { id: 'r2', kind: 'res', side: 'res', role: 'res', cloth: 0x5f6f4c, hair: 0x6a4a2c, job: 'farm', path: [[1.6, 9.6], [3.4, 9.6], [3.4, 11.6], [1.6, 11.6]], loop: true, speed: 0.45, stop: 0.9 },
      { id: 'r3', kind: 'res', side: 'res', role: 'res', cloth: 0x6a5a6e, hair: 0x222222, job: 'craft', x: 10.5, y: 3.15, face: [0, 1] },
      { id: 'r4', kind: 'res', side: 'res', role: 'res', cloth: 0x80624a, hair: 0x8a6a3a, job: 'haul', path: [[9, 6.2], [9, 8], [9.9, 9.3]], loop: false, speed: 1.0, stop: 0.6 },
    ],
    tele: [], shots: [],
  },
};

/* ---------- 칸 읽기 ---------- */
export function tileAt(sc, x, y) { if (x < 0 || y < 0 || x >= sc.w || y >= sc.h) return ' '; return sc.map[y][x]; }
export const isWall = (c) => c === '#' || c === 'W' || c === 'S';
/** 정착지 벽 칸 옆 이웃이 벽(문 포함)인가 */
export const isWallish = (c) => isWall(c) || c === 'D';

/* ---------- 시간 → 상태 ---------- */
const frac = (v) => v - Math.floor(v);
const len = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);
/** 경로 위 위치: loop면 한 바퀴(꼭짓점마다 stop초 쉼), 아니면 왕복(끝마다 stop초 쉼) */
function walkPath(a, t) {
  const P = a.loop ? [...a.path, a.path[0]] : a.path, segs = [];
  let total = 0;
  for (let i = 0; i < P.length - 1; i++) { const l = len(P[i], P[i + 1]); segs.push([P[i], P[i + 1], l, total]); total += l; }
  const stop = a.stop || 0, walkT = total / a.speed;
  if (a.loop) {
    const per = walkT + stop * segs.length, u = frac(t / per) * per;
    let acc = 0;
    for (const [p, q, l] of segs) {
      const d = l / a.speed;
      if (u < acc + stop) return { x: p[0], y: p[1], face: [q[0] - p[0], q[1] - p[1]], moving: false };
      if (u < acc + stop + d) { const k = (u - acc - stop) / d; return { x: p[0] + (q[0] - p[0]) * k, y: p[1] + (q[1] - p[1]) * k, face: [q[0] - p[0], q[1] - p[1]], moving: true }; }
      acc += stop + d;
    }
    return { x: P[0][0], y: P[0][1], face: [1, 0], moving: false };
  }
  const per = 2 * walkT + 2 * stop, u = frac(t / per) * per;
  let dist, back = false, moving = true;
  if (u < walkT) dist = u * a.speed;
  else if (u < walkT + stop) { dist = total; moving = false; }
  else if (u < 2 * walkT + stop) { dist = total - (u - walkT - stop) * a.speed; back = true; }
  else { dist = 0; moving = false; back = true; }
  for (const [p, q, l, off] of segs) {
    if (dist <= off + l + 1e-6) {
      const k = Math.max(0, Math.min(1, (dist - off) / l)), f = back ? [p[0] - q[0], p[1] - q[1]] : [q[0] - p[0], q[1] - p[1]];
      return { x: p[0] + (q[0] - p[0]) * k, y: p[1] + (q[1] - p[1]) * k, face: f, moving, carry: !back };
    }
  }
  const q = P[P.length - 1]; return { x: q[0], y: q[1], face: [0, 1], moving: false };
}

const PERIOD = { swing: 1.25, windup: 1.8, fight: 1.1, shoot: 1.6, craft: 0.9, farm: 1.3, cast: 2.2, hurt: 1.25 };

/**
 * 장면의 t초 상태. 모든 스타일이 같은 값을 그린다.
 * actors[i]: { a(자료), x, y, ang(바라보는 방향: 0=+x, π/2=+y 아래), walk(걸음 위상, 0이면 서 있음), bob(0..1), act, k(행동 진행 0..1), carry }
 */
export function sample(sc, t) {
  const by = {}, out = { t, actors: [], tele: [], shots: [], swing: null, light: null, flicker: 1 };
  for (const a of sc.actors) {
    let x = a.x, y = a.y, face = a.face || [0, 1], walk = 0, carry = false;
    const ph = (a.id.charCodeAt(0) * 0.7 + a.id.charCodeAt(a.id.length - 1) * 1.3) % 6.28;
    if (a.path) { const p = walkPath(a, t + ph); x = p.x; y = p.y; face = p.face; walk = p.moving ? (t + ph) * 7.5 * Math.max(0.6, a.speed) : 0; carry = a.job === 'haul' && p.carry; }
    const act = a.act || a.job || 'idle', per = PERIOD[act];
    let k = per ? frac(t / per + (act === 'fight' ? ph * 0.15 : 0)) : 0;
    if (act === 'hurt') k = frac(t / per - 0.3); // 등불지기의 휘두름에 맞춰 움찔
    const s = { a, x, y, ang: Math.atan2(face[1], face[0]), walk, bob: Math.sin(t * 2.4 + ph) * 0.5 + 0.5, act, k, carry, ph };
    by[a.id] = s; out.actors.push(s);
  }
  for (const T of sc.tele) {
    const k = frac((t + T.phase) / T.period), fill = Math.min(1, k / 0.82), burst = k > 0.82 ? (k - 0.82) / 0.18 : 0;
    if (T.type === 'fan') { const b = by[T.from]; out.tele.push({ type: 'fan', x: b.x, y: b.y, ang: T.ang, r: T.r, half: T.half, fill, burst }); b.k = fill; b.burst = burst; }
    else out.tele.push({ type: 'circle', x: T.x, y: T.y, r: T.r, fill, burst });
  }
  for (const S of sc.shots) {
    const f = by[S.from], g = by[S.to], k = frac((t + S.phase) / S.period), d = Math.hypot(g.x - f.x, g.y - f.y), fly = d / S.speed / S.period;
    if (k < fly) { const u = k / fly; out.shots.push({ x: f.x + (g.x - f.x) * u, y: f.y + (g.y - f.y) * u, h: 0.8 + Math.sin(Math.PI * u) * 0.35, ang: Math.atan2(g.y - f.y, g.x - f.x), foe: S.foe, u }); }
  }
  const hero = by.hero;
  if (hero) {
    const k = hero.k;
    if (k > 0.12 && k < 0.55) out.swing = { x: hero.x, y: hero.y, ang: hero.ang, r: 1.3, k: (k - 0.12) / 0.43 };
    out.light = { x: hero.x, y: hero.y, r: sc.light.r };
  }
  if (sc.hearth) out.light = { x: sc.hearth.x, y: sc.hearth.y, r: sc.light.r };
  out.flicker = 1 + Math.sin(t * 13) * 0.035 + Math.sin(t * 7.3 + 1) * 0.05 + Math.sin(t * 23.7) * 0.025;
  return out;
}

/** 무기 각도 오프셋(라디안, +는 뒤로 젖힘): 휘두름·치켜듦·망치질 */
export function swingOffset(s) {
  const k = s.k;
  if (s.act === 'swing' || s.act === 'fight') { if (k < 0.12) return 1.1 * (k / 0.12); if (k < 0.55) return 1.1 - 2.4 * ((k - 0.12) / 0.43); return -1.3 + 1.3 * ((k - 0.55) / 0.45); }
  if (s.act === 'windup') return 1.5 * Math.min(1, k / 0.75) * (k < 0.9 ? 1 : 1 - (k - 0.9) / 0.1 * 2.2);
  if (s.act === 'craft') return k < 0.35 ? 1.2 * k / 0.35 : 1.2 - 1.6 * Math.min(1, (k - 0.35) / 0.12);
  if (s.act === 'farm') return Math.sin(k * Math.PI * 2) * 0.5;
  return 0;
}
/** 치켜든 정도(0..1): 한 방 직전 경고의 세기 */
export const windupLevel = (s) => (s.act === 'windup' ? Math.min(1, s.k / 0.75) * (s.k < 0.9 ? 1 : 0) : 0);
/** 맞아서 움찔(0..1) */
export const hurtLevel = (s) => (s.act === 'hurt' && s.k < 0.25 ? 1 - s.k / 0.25 : 0);
