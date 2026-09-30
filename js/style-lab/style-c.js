import { ROLE_COLOR, THREAT, hurtLevel, isWall, isWallish, swingOffset, tileAt, windupLevel } from './scenes.js';

/* ================= C: 2D 탑다운 (Canvas 2D, 그림 파일 없이 도형만) =================
   고정 배경(칸·벽·가구)은 한 번 그려 두고, 매 프레임 빛·예고·인물만 다시 그린다. */
const h2 = (x, y, s = 0) => { const v = Math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453; return v - Math.floor(v); };
const TAU = Math.PI * 2;
const CLOTH = { hero: '#8a6a44', guard: '#5b6270', sword: '#5a4a5e', archer: '#4a5a44', healer: '#b8ae94' };
const HAIR = { hero: '#3a2a1e', guard: '#8a9098', sword: '#2a2224', archer: '#5a4a2a', healer: '#d8d2c0' };
const FOE = { goblin: { body: '#5a6440', head: '#6f7a4a', r: 0.21 }, skeleton: { body: '#b8b09a', head: '#d6cfba', r: 0.22 }, boss: { body: '#3e3a3c', head: '#5a4e48', r: 0.44 } };
const hex = (n) => '#' + n.toString(16).padStart(6, '0');

export class StyleC {
  constructor(host) {
    this.host = host;
    this.cv = document.createElement('canvas'); this.cv.className = 'sl-canvas'; host.appendChild(this.cv);
    this.g = this.cv.getContext('2d');
    this.bg = document.createElement('canvas'); this.dark = document.createElement('canvas');
    this.sc = null; this.ts = 32; this.ox = 0; this.oy = 0; this.dpr = 1;
  }
  show(on) { this.cv.style.display = on ? 'block' : 'none'; if (on) this.resize(); }
  setScene(sc) { this.sc = sc; this.resize(); }
  resize() {
    if (!this.sc) return;
    const W = this.host.clientWidth || innerWidth, H = this.host.clientHeight || innerHeight, dpr = this.dpr = Math.min(2, devicePixelRatio || 1);
    this.cv.width = W * dpr; this.cv.height = H * dpr; this.cv.style.width = W + 'px'; this.cv.style.height = H + 'px';
    const sc = this.sc, ts = this.ts = Math.floor(Math.min(W / (sc.w + 0.3), H / (sc.h + 0.3)));
    this.ox = Math.round((W - ts * sc.w) / 2); this.oy = Math.round((H - ts * sc.h) / 2);
    this.dark.width = this.bg.width = sc.w * ts * dpr; this.dark.height = this.bg.height = sc.h * ts * dpr;
    this.drawStatic();
  }
  /* ---------- 고정 배경 ---------- */
  drawStatic() {
    const sc = this.sc, g = this.bg.getContext('2d'), ts = this.ts;
    g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0); g.clearRect(0, 0, sc.w * ts, sc.h * ts);
    for (let y = 0; y < sc.h; y++) for (let x = 0; x < sc.w; x++) this.tile(g, x, y, tileAt(sc, x, y));
    // 벽 그림자: 벽 아래(남쪽) 칸에 짧은 그림자
    g.fillStyle = 'rgba(0,0,0,.28)';
    for (let y = 0; y < sc.h - 1; y++) for (let x = 0; x < sc.w; x++) if (isWall(tileAt(sc, x, y)) && !isWallish(tileAt(sc, x, y + 1))) g.fillRect(x * ts, (y + 1) * ts, ts, ts * 0.2);
    for (let y = 0; y < sc.h; y++) for (let x = 0; x < sc.w; x++) if (isWall(tileAt(sc, x, y))) this.wall(g, x, y, tileAt(sc, x, y));
    for (const p of sc.props) this.prop(g, p);
    // 격자선: 아주 옅게
    g.strokeStyle = 'rgba(0,0,0,.12)'; g.lineWidth = 1;
    for (let y = 0; y < sc.h; y++) for (let x = 0; x < sc.w; x++) { const c = tileAt(sc, x, y); if (!isWall(c) && c !== 'g') g.strokeRect(x * ts + 0.5, y * ts + 0.5, ts - 1, ts - 1); }
  }
  noise(g, x, y, base, amt, n = 10, size = 0.08) {
    const ts = this.ts; g.fillStyle = base; g.fillRect(x * ts, y * ts, ts, ts);
    for (let i = 0; i < n; i++) {
      const u = h2(x, y, i), v = h2(y, x, i + 9), w = h2(x + i, y - i, 3);
      g.fillStyle = w > 0.5 ? `rgba(255,255,255,${amt * w})` : `rgba(0,0,0,${amt * (1 - w) * 1.4})`;
      g.fillRect(x * ts + u * ts, y * ts + v * ts, ts * size * (0.6 + w), ts * size * (0.6 + w));
    }
  }
  tile(g, x, y, c) {
    const ts = this.ts, X = x * ts, Y = y * ts, r = h2(x, y);
    if (c === '.' && this.sc.id === 'dungeon' || c === '#') { // 돌바닥: 판돌 넷
      const base = ['#4b4843', '#474440', '#504c46'][Math.floor(r * 3)];
      this.noise(g, x, y, base, 0.07, 14);
      g.strokeStyle = 'rgba(0,0,0,.25)'; g.lineWidth = 1; g.beginPath(); const m = 0.45 + r * 0.1; g.moveTo(X + ts * m, Y); g.lineTo(X + ts * m, Y + ts); g.moveTo(X, Y + ts * (1 - m)); g.lineTo(X + ts * m, Y + ts * (1 - m)); g.stroke();
    } else if (c === '~') {
      g.fillStyle = '#2c4250'; g.fillRect(X, Y, ts, ts);
      g.fillStyle = 'rgba(0,0,0,.18)'; g.fillRect(X, Y, ts, ts * 0.12);
    } else if (c === '"' || c === 'g') {
      this.noise(g, x, y, c === 'g' ? ['#56603f', '#5a6442', '#535c3c'][Math.floor(r * 3)] : '#4a5438', 0.06, 8);
      g.strokeStyle = c === 'g' ? 'rgba(120,140,80,.55)' : 'rgba(110,130,75,.6)'; g.lineWidth = 1;
      g.beginPath(); for (let i = 0; i < 6; i++) { const u = h2(x, y, i + 20), v = h2(x, y, i + 40); g.moveTo(X + u * ts, Y + v * ts); g.lineTo(X + u * ts + (h2(x, i, 1) - 0.5) * 3, Y + v * ts - ts * 0.14); } g.stroke();
    } else if (c === '.') { this.noise(g, x, y, ['#6f624c', '#6a5d48', '#74674f'][Math.floor(r * 3)], 0.07, 12, 0.06); }
    else if (c === '=') { // 나무 바닥: 널빤지 셋
      for (let i = 0; i < 3; i++) { g.fillStyle = ['#6d5238', '#654b33', '#72573c'][(i + x + y) % 3]; g.fillRect(X, Y + i * ts / 3, ts, ts / 3); }
      g.strokeStyle = 'rgba(0,0,0,.3)'; g.lineWidth = 1; g.beginPath(); for (let i = 1; i < 3; i++) { g.moveTo(X, Y + i * ts / 3); g.lineTo(X + ts, Y + i * ts / 3); } g.moveTo(X + ts * (0.3 + r * 0.4), Y); g.lineTo(X + ts * (0.3 + r * 0.4), Y + ts / 3); g.stroke();
    } else if (c === 'f') { // 밭: 이랑 + 싹
      g.fillStyle = '#4e3b2a'; g.fillRect(X, Y, ts, ts);
      g.fillStyle = '#5e4832'; for (let i = 0; i < 2; i++) g.fillRect(X, Y + ts * (0.12 + i * 0.5), ts, ts * 0.26);
      for (let i = 0; i < 2; i++) for (let j = 0; j < 3; j++) { const cx = X + ts * (0.18 + j * 0.32), cy = Y + ts * (0.25 + i * 0.5); g.fillStyle = '#6e8a48'; g.beginPath(); g.ellipse(cx - 2, cy, ts * 0.07, ts * 0.04, -0.6, 0, TAU); g.ellipse(cx + 2, cy, ts * 0.07, ts * 0.04, 0.6, 0, TAU); g.fill(); }
    } else if (c === 's') { this.noise(g, x, y, '#6a5d48', 0.06, 10, 0.06); }
    else if (c === 'D') { this.noise(g, x, y, '#6d5238', 0.05, 6); }
    else { g.fillStyle = '#6a5d48'; g.fillRect(X, Y, ts, ts); }
    if (c === 's') { // 창고 구역 테두리(점선)
      g.save(); g.strokeStyle = 'rgba(220,200,150,.5)'; g.setLineDash([3, 3]); g.lineWidth = 1;
      const S = (dx, dy) => tileAt(this.sc, x + dx, y + dy) === 's';
      g.beginPath(); if (!S(0, -1)) { g.moveTo(X, Y + 1); g.lineTo(X + ts, Y + 1); } if (!S(0, 1)) { g.moveTo(X, Y + ts - 1); g.lineTo(X + ts, Y + ts - 1); } if (!S(-1, 0)) { g.moveTo(X + 1, Y); g.lineTo(X + 1, Y + ts); } if (!S(1, 0)) { g.moveTo(X + ts - 1, Y); g.lineTo(X + ts - 1, Y + ts); } g.stroke(); g.restore();
    }
    if (c === 'D') { // 문: 판자 + 경첩
      const sc = this.sc, hz = isWallish(tileAt(sc, x - 1, y)) || isWallish(tileAt(sc, x + 1, y));
      g.fillStyle = '#8a6440'; g.strokeStyle = '#1c1612'; g.lineWidth = 1.5;
      if (hz) { g.fillRect(X + 1, Y + ts * 0.36, ts - 2, ts * 0.28); g.strokeRect(X + 1, Y + ts * 0.36, ts - 2, ts * 0.28); }
      else { g.fillRect(X + ts * 0.36, Y + 1, ts * 0.28, ts - 2); g.strokeRect(X + ts * 0.36, Y + 1, ts * 0.28, ts - 2); }
    }
  }
  /** 벽: 윗면 + 어두운 위쪽 가장자리 + 윤곽 */
  wall(g, x, y, c) {
    const ts = this.ts, X = x * ts, Y = y * ts, sc = this.sc, r = h2(x, y, 5);
    const top = c === 'W' ? '#6e5236' : c === 'S' ? '#7e786e' : ['#6c665d', '#686259', '#716b61'][Math.floor(r * 3)];
    const edge = c === 'W' ? '#3a2a1c' : c === 'S' ? '#48443e' : '#34312d';
    const thin = c === 'W' || c === 'S';
    // 정착지 벽은 칸보다 얇게, 이웃 벽 쪽으로 잇는다
    const n = (dx, dy) => isWallish(tileAt(sc, x + dx, y + dy));
    if (thin) {
      const t = ts * 0.3, c0 = ts / 2 - t / 2, segs = [[X + c0, Y + c0, t, t]];
      if (n(-1, 0)) segs.push([X, Y + c0, ts / 2, t]); if (n(1, 0)) segs.push([X + ts / 2, Y + c0, ts / 2, t]);
      if (n(0, -1)) segs.push([X + c0, Y, t, ts / 2]); if (n(0, 1)) segs.push([X + c0, Y + ts / 2, t, ts / 2]);
      g.fillStyle = 'rgba(0,0,0,.28)'; for (const [sx, sy, sw, sh] of segs) g.fillRect(sx + 1, sy + 3, sw, sh);
      g.fillStyle = top; for (const [sx, sy, sw, sh] of segs) g.fillRect(sx, sy, sw, sh);
      g.fillStyle = edge; for (const [sx, sy, sw, sh] of segs) if (sw > sh) g.fillRect(sx, sy, sw, sh * 0.32);
      if (!n(0, -1)) g.fillRect(X + c0, Y + c0, t, t * 0.32);
      if (c === 'W') { g.fillStyle = 'rgba(0,0,0,.25)'; for (const [sx, sy, sw, sh] of segs) if (sw > sh) for (let i = 1; i < 3; i++) g.fillRect(sx + sw * i / 3, sy, 1, sh); }
      return;
    }
    const rx = X, ry = Y, rw = ts, rh = ts;
    g.fillStyle = top; g.fillRect(rx, ry, rw, rh);
    for (let i = 0; i < 5; i++) { g.fillStyle = `rgba(0,0,0,${0.08 + h2(x, y, i) * 0.08})`; g.fillRect(X + h2(x, y, i + 3) * ts * 0.8, Y + h2(y, x, i) * ts * 0.8, ts * 0.22, ts * 0.12); }
    if (!isWall(tileAt(sc, x, y - 1))) { g.fillStyle = edge; g.fillRect(X, Y, ts, ts * 0.18); }
    if (!isWall(tileAt(sc, x, y + 1))) { g.fillStyle = '#58534b'; g.fillRect(X, Y + ts * 0.8, ts, ts * 0.2); g.fillStyle = 'rgba(0,0,0,.35)'; g.fillRect(X, Y + ts * 0.8, ts, 1.5); }
    g.strokeStyle = 'rgba(0,0,0,.45)'; g.lineWidth = 1;
    if (!isWall(tileAt(sc, x - 1, y))) { g.beginPath(); g.moveTo(X + 0.5, Y); g.lineTo(X + 0.5, Y + ts); g.stroke(); }
    if (!isWall(tileAt(sc, x + 1, y))) { g.beginPath(); g.moveTo(X + ts - 0.5, Y); g.lineTo(X + ts - 0.5, Y + ts); g.stroke(); }
  }
  prop(g, p) {
    const ts = this.ts, X = p.x * ts, Y = p.y * ts, W = (p.w || 1) * ts, H = (p.h || 1) * ts;
    const box = (x, y, w, h, fill, line = '#1a1410', lw = 1.5) => { g.fillStyle = fill; g.fillRect(x, y, w, h); g.strokeStyle = line; g.lineWidth = lw; g.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1); };
    const shadow = (x, y, w, h) => { g.fillStyle = 'rgba(0,0,0,.25)'; g.fillRect(x + 2, y + 3, w, h); };
    switch (p.k) {
      case 'bed': shadow(X + 4, Y + 3, W - 8, H - 6); box(X + 4, Y + 3, W - 8, H - 6, '#5a4028'); box(X + 6, Y + 5, W - 12, ts * 0.32, '#cfc6ae', '#1a1410', 1); box(X + 6, Y + ts * 0.62, W - 12, H - ts * 0.62 - 6, '#6a3e36', '#1a1410', 1); g.fillStyle = 'rgba(0,0,0,.15)'; g.fillRect(X + 6, Y + ts * 0.62, W - 12, 3); break;
      case 'table': shadow(X + 3, Y + 5, W - 6, H - 10); box(X + 3, Y + 5, W - 6, H - 10, '#7a5a3a'); g.strokeStyle = 'rgba(0,0,0,.25)'; g.lineWidth = 1; g.beginPath(); g.moveTo(X + 4, Y + H / 2); g.lineTo(X + W - 4, Y + H / 2); g.stroke(); g.fillStyle = '#c8bca0'; g.beginPath(); g.arc(X + W * 0.3, Y + H / 2, ts * 0.12, 0, TAU); g.fill(); g.stroke(); break;
      case 'chair': shadow(X + ts * 0.28, Y + ts * 0.28, ts * 0.44, ts * 0.44); box(X + ts * 0.28, Y + ts * 0.28, ts * 0.44, ts * 0.44, '#6a4c30'); box(X + ts * 0.28, Y + ts * 0.66, ts * 0.44, ts * 0.1, '#4e3822', '#1a1410', 1); break;
      case 'shelf': shadow(X + 3, Y + 2, W - 6, H * 0.5); box(X + 3, Y + 2, W - 6, H * 0.5, '#5a4028'); for (let i = 0; i < 3; i++) { g.fillStyle = ['#8a5a3a', '#6a7a8a', '#b09a6a'][i]; g.fillRect(X + 6 + i * (W - 12) / 3, Y + 5, (W - 12) / 3 - 2, H * 0.5 - 8); } break;
      case 'bench': shadow(X + 2, Y + 6, W - 4, H - 12); box(X + 2, Y + 6, W - 4, H - 12, '#6a5036'); // 작업대: 연장
        g.strokeStyle = '#1a1410'; g.lineWidth = 2; g.beginPath(); g.moveTo(X + ts * 0.3, Y + H * 0.35); g.lineTo(X + ts * 0.8, Y + H * 0.55); g.stroke(); box(X + ts * 0.72, Y + H * 0.45, ts * 0.2, ts * 0.14, '#8a8e96', '#1a1410', 1); box(X + ts * 1.2, Y + H * 0.35, ts * 0.5, ts * 0.3, '#9a8a6a', '#1a1410', 1); break;
      case 'lamp': g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.arc(X + ts / 2 + 2, Y + ts / 2 + 2, ts * 0.14, 0, TAU); g.fill(); g.fillStyle = '#3a3a40'; g.beginPath(); g.arc(X + ts / 2, Y + ts / 2, ts * 0.14, 0, TAU); g.fill(); g.fillStyle = '#ffd38a'; g.beginPath(); g.arc(X + ts / 2, Y + ts / 2, ts * 0.07, 0, TAU); g.fill(); break;
      case 'tree': {
        const cx = X + ts / 2, cy = Y + ts / 2;
        g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.ellipse(cx + ts * 0.18, cy + ts * 0.22, ts * 0.7, ts * 0.55, 0, 0, TAU); g.fill();
        for (const [dx, dy, r, c] of [[-0.18, 0.1, 0.42, '#3e4a30'], [0.2, 0.05, 0.4, '#435034'], [0, -0.18, 0.44, '#4a5838'], [0.02, 0.02, 0.3, '#56643f']]) { g.fillStyle = c; g.beginPath(); g.arc(cx + dx * ts, cy + dy * ts, r * ts, 0, TAU); g.fill(); }
        g.strokeStyle = 'rgba(20,24,14,.8)'; g.lineWidth = 1.5; g.beginPath(); g.arc(cx, cy - ts * 0.18, ts * 0.44, Math.PI * 0.9, Math.PI * 2.1); g.stroke(); break;
      }
      case 'rock': case 'stones': {
        const n = p.k === 'rock' ? 1 : 3;
        for (let i = 0; i < n; i++) {
          const cx = X + ts * (n === 1 ? 0.5 : 0.28 + i * 0.22), cy = Y + ts * (n === 1 ? 0.5 : 0.4 + (i % 2) * 0.25), r = ts * (n === 1 ? 0.36 : 0.16);
          g.fillStyle = 'rgba(0,0,0,.28)'; g.beginPath(); g.ellipse(cx + 2, cy + 3, r, r * 0.8, 0, 0, TAU); g.fill();
          g.beginPath(); for (let k = 0; k < 7; k++) { const a = k / 7 * TAU, rr = r * (0.8 + h2(p.x + i, p.y, k) * 0.3); g.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr * 0.85); } g.closePath();
          g.fillStyle = '#7a766c'; g.fill(); g.strokeStyle = '#26241f'; g.lineWidth = 1.5; g.stroke();
          g.fillStyle = 'rgba(255,255,255,.12)'; g.beginPath(); g.ellipse(cx - r * 0.25, cy - r * 0.3, r * 0.4, r * 0.25, -0.4, 0, TAU); g.fill();
        }
        break;
      }
      case 'logs': for (let i = 0; i < 3; i++) { const y = Y + ts * (0.25 + i * 0.22); g.fillStyle = 'rgba(0,0,0,.25)'; g.fillRect(X + ts * 0.14, y + 2, ts * 0.72, ts * 0.18); box(X + ts * 0.12, y, ts * 0.72, ts * 0.18, '#6a4a2c', '#1a1410', 1); g.fillStyle = '#b08a5a'; g.beginPath(); g.arc(X + ts * 0.84, y + ts * 0.09, ts * 0.08, 0, TAU); g.fill(); } break;
      case 'crate': shadow(X + ts * 0.18, Y + ts * 0.18, ts * 0.64, ts * 0.64); box(X + ts * 0.18, Y + ts * 0.18, ts * 0.64, ts * 0.64, '#8a6a42'); g.strokeStyle = 'rgba(0,0,0,.4)'; g.lineWidth = 1; g.beginPath(); g.moveTo(X + ts * 0.18, Y + ts * 0.18); g.lineTo(X + ts * 0.82, Y + ts * 0.82); g.moveTo(X + ts * 0.82, Y + ts * 0.18); g.lineTo(X + ts * 0.18, Y + ts * 0.82); g.stroke(); break;
      case 'sack': g.fillStyle = 'rgba(0,0,0,.25)'; g.beginPath(); g.ellipse(X + ts / 2 + 2, Y + ts / 2 + 3, ts * 0.3, ts * 0.25, 0, 0, TAU); g.fill(); g.fillStyle = '#a8966e'; g.strokeStyle = '#1a1410'; g.lineWidth = 1.5; g.beginPath(); g.ellipse(X + ts / 2, Y + ts / 2, ts * 0.3, ts * 0.25, 0, 0, TAU); g.fill(); g.stroke(); break;
    }
  }
  /* ---------- 매 프레임 ---------- */
  render(st) {
    const sc = this.sc; if (!sc) return;
    const g = this.g, ts = this.ts, dpr = this.dpr;
    g.setTransform(1, 0, 0, 1, 0, 0); g.fillStyle = sc.id === 'dungeon' ? '#0d0c0e' : '#1a1c14'; g.fillRect(0, 0, this.cv.width, this.cv.height);
    g.setTransform(dpr, 0, 0, dpr, this.ox * dpr, this.oy * dpr);
    g.drawImage(this.bg, 0, 0, sc.w * ts, sc.h * ts);
    const P = (x) => (x + 0.5) * ts; // 칸 중심 → 픽셀
    // 물결
    g.strokeStyle = 'rgba(170,200,210,.22)'; g.lineWidth = 1;
    for (let y = 0; y < sc.h; y++) for (let x = 0; x < sc.w; x++) if (tileAt(sc, x, y) === '~') { g.beginPath(); for (let i = 0; i < 2; i++) { const yy = y * ts + ts * (0.3 + i * 0.4) + Math.sin(st.t * 1.4 + x + i * 2) * 2; g.moveTo(x * ts + ts * 0.15, yy); g.quadraticCurveTo(x * ts + ts * 0.5, yy - 3, x * ts + ts * 0.85, yy); } g.stroke(); }
    if (sc.hearth) this.hearth(g, P(sc.hearth.x), P(sc.hearth.y), st.t);
    // 빛: 어둠 층에서 빛 반경을 도려낸다
    if (st.light) {
      const d = this.dark.getContext('2d'), L = st.light, R = L.r * ts * st.flicker, cx = P(L.x), cy = P(L.y);
      d.setTransform(dpr, 0, 0, dpr, 0, 0); d.globalCompositeOperation = 'source-over'; d.clearRect(0, 0, sc.w * ts, sc.h * ts);
      d.fillStyle = sc.id === 'dungeon' ? 'rgba(8,10,22,.6)' : 'rgba(10,12,26,.5)'; d.fillRect(0, 0, sc.w * ts, sc.h * ts);
      d.globalCompositeOperation = 'destination-out';
      const gr = d.createRadialGradient(cx, cy, R * 0.15, cx, cy, R);
      gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(0.55, 'rgba(0,0,0,.85)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
      d.fillStyle = gr; d.fillRect(0, 0, sc.w * ts, sc.h * ts);
      g.drawImage(this.dark, 0, 0, sc.w * ts, sc.h * ts);
      g.save(); g.globalCompositeOperation = 'lighter';
      const warm = g.createRadialGradient(cx, cy, 0, cx, cy, R * 0.8); warm.addColorStop(0, 'rgba(255,160,70,.16)'); warm.addColorStop(1, 'rgba(255,140,60,0)');
      g.fillStyle = warm; g.fillRect(cx - R, cy - R, R * 2, R * 2); g.restore();
    }
    // 예고(위협)
    for (const T of st.tele) this.tele(g, T, P);
    for (const s of st.actors) if (windupLevel(s) > 0) this.windup(g, P(s.x), P(s.y), s.ang, windupLevel(s));
    // 인물(아래쪽이 나중에)
    const order = [...st.actors].sort((a, b) => a.y - b.y);
    for (const s of order) this.actor(g, s, P(s.x), P(s.y), st);
    if (st.swing) this.swing(g, st.swing, P);
    for (const s of st.shots) this.shot(g, s, P);
  }
  hearth(g, cx, cy, t) {
    const ts = this.ts;
    for (let k = 0; k < 8; k++) { const a = k / 8 * TAU; g.fillStyle = k % 2 ? '#6a665e' : '#7a766c'; g.strokeStyle = '#1e1c18'; g.lineWidth = 1; g.beginPath(); g.arc(cx + Math.cos(a) * ts * 0.36, cy + Math.sin(a) * ts * 0.36, ts * 0.1, 0, TAU); g.fill(); g.stroke(); }
    g.fillStyle = '#2a1e18'; g.beginPath(); g.arc(cx, cy, ts * 0.26, 0, TAU); g.fill();
    const f = 1 + Math.sin(t * 13) * 0.08 + Math.sin(t * 7.3) * 0.06;
    for (const [r, c, dx] of [[0.24, '#c8501e', 0], [0.17, '#f08a2a', Math.sin(t * 9) * 0.03], [0.09, '#ffd27a', Math.sin(t * 11) * 0.03]]) { g.fillStyle = c; g.beginPath(); g.arc(cx + dx * ts, cy - (0.24 - r) * ts * 0.4, r * ts * f, 0, TAU); g.fill(); }
  }
  tele(g, T, P) {
    const ts = this.ts, cx = P(T.x), cy = P(T.y), r = T.r * ts;
    const path = (rad) => { g.beginPath(); if (T.type === 'fan') { g.moveTo(cx, cy); g.arc(cx, cy, rad, T.ang - T.half, T.ang + T.half); g.closePath(); } else g.arc(cx, cy, rad, 0, TAU); };
    g.save();
    path(r); g.fillStyle = 'rgba(255,90,36,.12)'; g.fill();
    if (T.burst > 0) { g.fillStyle = `rgba(255,120,60,${0.55 * (1 - T.burst)})`; g.fill(); }
    else { path(Math.max(1, r * T.fill)); g.fillStyle = 'rgba(255,90,36,.38)'; g.fill(); }
    path(r); g.strokeStyle = THREAT; g.lineWidth = 2.5; g.stroke();
    g.restore();
  }
  windup(g, cx, cy, ang, lv) {
    const ts = this.ts, r = ts * 1.05, half = 0.55;
    g.save(); g.beginPath(); g.moveTo(cx, cy); g.arc(cx, cy, r, ang - half, ang + half); g.closePath();
    g.fillStyle = `rgba(255,90,36,${0.12 + 0.3 * lv})`; g.fill(); g.strokeStyle = THREAT; g.lineWidth = 2; g.stroke();
    // 머리 위 경고 표시: 작은 세모
    const y = cy - ts * 0.55 - lv * 3; g.fillStyle = THREAT; g.strokeStyle = '#1a0a04'; g.lineWidth = 1.2;
    g.beginPath(); g.moveTo(cx, y - ts * 0.16); g.lineTo(cx + ts * 0.11, y + ts * 0.04); g.lineTo(cx - ts * 0.11, y + ts * 0.04); g.closePath(); g.fill(); g.stroke();
    g.restore();
  }
  swing(g, S, P) {
    const ts = this.ts, cx = P(S.x), cy = P(S.y), a0 = S.ang - 1.2, a1 = a0 + 2.4 * S.k;
    g.save(); g.lineCap = 'round';
    for (let i = 0; i < 6; i++) { const u = i / 6, a = a1 - u * 1.1; if (a < a0) break; g.strokeStyle = `rgba(255,236,200,${0.85 * (1 - u) * (1 - S.k * 0.5)})`; g.lineWidth = ts * 0.12 * (1 - u); g.beginPath(); g.arc(cx, cy, S.r * ts, a - 0.2, a); g.stroke(); }
    g.restore();
  }
  shot(g, s, P) {
    const ts = this.ts, x = P(s.x), y = P(s.y) - s.h * ts * 0.25, dx = Math.cos(s.ang), dy = Math.sin(s.ang);
    g.save(); g.lineCap = 'round';
    g.strokeStyle = s.foe ? 'rgba(255,90,36,.35)' : 'rgba(240,230,200,.3)'; g.lineWidth = 3; g.beginPath(); g.moveTo(x - dx * ts * 0.9, y - dy * ts * 0.9); g.lineTo(x, y); g.stroke();
    g.strokeStyle = s.foe ? THREAT : '#efe6cc'; g.lineWidth = 2; g.beginPath(); g.moveTo(x - dx * ts * 0.35, y - dy * ts * 0.35); g.lineTo(x + dx * ts * 0.12, y + dy * ts * 0.12); g.stroke();
    g.restore();
  }
  /** 위에서 본 사람: 그림자 · (역할 고리) · 발 · 어깨 · 무기 · 머리 */
  actor(g, s, cx, cy) {
    const ts = this.ts, a = s.a, foe = a.side === 'foe', res = a.side === 'res', k = a.kind;
    const F = FOE[k], rad = (F ? F.r : 0.23) * ts, hurt = hurtLevel(s);
    const jx = hurt ? Math.cos(s.ang) * -3 * hurt : 0, jy = hurt ? Math.sin(s.ang) * -3 * hurt : 0;
    cx += jx; cy += jy;
    g.save();
    g.fillStyle = 'rgba(0,0,0,.35)'; g.beginPath(); g.ellipse(cx + 2, cy + 3, rad * 1.25, rad * 1.05, 0, 0, TAU); g.fill();
    if (foe) { g.fillStyle = 'rgba(120,30,30,.35)'; g.beginPath(); g.arc(cx, cy, rad * 1.45, 0, TAU); g.fill(); g.strokeStyle = 'rgba(90,20,20,.9)'; g.lineWidth = 1.2; g.stroke(); }
    else if (!res) { g.strokeStyle = ROLE_COLOR[a.role]; g.lineWidth = 2; g.beginPath(); g.arc(cx, cy, rad * 1.7, 0, TAU); g.stroke(); }
    g.translate(cx, cy); g.rotate(s.ang + Math.PI / 2); // 앞 = -y
    const sway = s.walk ? Math.sin(s.walk) * 0.12 : 0;
    // 발
    if (s.walk) { g.fillStyle = '#2a221c'; const st = Math.sin(s.walk) * rad * 0.45; g.beginPath(); g.ellipse(-rad * 0.35, -st, rad * 0.16, rad * 0.24, 0, 0, TAU); g.ellipse(rad * 0.35, st, rad * 0.16, rad * 0.24, 0, 0, TAU); g.fill(); }
    g.rotate(sway);
    const body = foe ? F.body : res ? hex(a.cloth) : CLOTH[k], head = foe ? F.head : res ? hex(a.hair) : HAIR[k];
    const sw = swingOffset(s);
    this.weapon(g, s, rad, sw);
    // 어깨
    g.fillStyle = hurt ? '#e8e0d0' : body; g.strokeStyle = '#141110'; g.lineWidth = 1.6;
    g.beginPath(); g.ellipse(0, 0, rad * 1.15, rad * 0.62, 0, 0, TAU); g.fill(); g.stroke();
    if (k === 'boss') { g.fillStyle = '#6a625a'; g.beginPath(); g.ellipse(-rad * 0.8, -rad * 0.05, rad * 0.4, rad * 0.35, 0, 0, TAU); g.ellipse(rad * 0.8, -rad * 0.05, rad * 0.4, rad * 0.35, 0, 0, TAU); g.fill(); g.stroke(); }
    if (k === 'guard') { g.fillStyle = '#7c8594'; g.beginPath(); g.ellipse(-rad * 0.75, -rad * 0.15, rad * 0.35, rad * 0.3, 0, 0, TAU); g.ellipse(rad * 0.75, -rad * 0.15, rad * 0.35, rad * 0.3, 0, 0, TAU); g.fill(); g.stroke(); }
    if (s.carry) { g.fillStyle = '#8a6a42'; g.fillRect(-rad * 0.5, -rad * 1.25, rad, rad * 0.7); g.strokeRect(-rad * 0.5, -rad * 1.25, rad, rad * 0.7); }
    // 머리
    const hr = rad * (k === 'boss' ? 0.42 : 0.55);
    g.fillStyle = head; g.beginPath(); g.arc(0, -rad * 0.08, hr, 0, TAU); g.fill(); g.stroke();
    if (k === 'boss') { g.fillStyle = '#d8ceb8'; g.beginPath(); g.moveTo(-hr * 0.7, -rad * 0.3); g.lineTo(-hr * 1.5, -rad * 0.95); g.lineTo(-hr * 0.2, -rad * 0.45); g.moveTo(hr * 0.7, -rad * 0.3); g.lineTo(hr * 1.5, -rad * 0.95); g.lineTo(hr * 0.2, -rad * 0.45); g.fill(); g.stroke(); }
    else if (k === 'goblin') { g.fillStyle = F.head; g.beginPath(); g.moveTo(-hr * 0.8, 0); g.lineTo(-hr * 1.7, rad * 0.1); g.lineTo(-hr * 0.8, rad * 0.25); g.moveTo(hr * 0.8, 0); g.lineTo(hr * 1.7, rad * 0.1); g.lineTo(hr * 0.8, rad * 0.25); g.fill(); g.stroke(); }
    else if (k === 'skeleton') { g.fillStyle = '#1a1612'; g.beginPath(); g.arc(-hr * 0.35, -rad * 0.08 - hr * 0.45, hr * 0.18, 0, TAU); g.arc(hr * 0.35, -rad * 0.08 - hr * 0.45, hr * 0.18, 0, TAU); g.fill(); }
    else if (!foe) { g.fillStyle = '#c8a888'; g.beginPath(); g.arc(0, -rad * 0.08 - hr * 0.55, hr * 0.42, Math.PI * 1.1, Math.PI * 1.9); g.fill(); } // 얼굴 쪽 살빛
    g.restore();
  }
  weapon(g, s, rad, sw) {
    const k = s.a.kind; g.save(); g.lineCap = 'round';
    const hand = (x, y, len, w, col, rot) => { g.save(); g.translate(x, y); g.rotate(rot); g.strokeStyle = '#141110'; g.lineWidth = w + 2; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -len); g.stroke(); g.strokeStyle = col; g.lineWidth = w; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -len); g.stroke(); g.restore(); };
    const bow = (x, y) => { g.strokeStyle = '#141110'; g.lineWidth = 3.2; g.beginPath(); g.arc(x, y - rad * 0.2, rad * 0.9, Math.PI * 1.2, Math.PI * 1.8); g.stroke(); g.strokeStyle = '#8a6a44'; g.lineWidth = 1.8; g.stroke(); };
    if (k === 'hero') { hand(rad * 0.85, -rad * 0.1, rad * 2.1, 2.5, '#d8dce2', -sw); g.fillStyle = '#ffb040'; g.beginPath(); g.arc(-rad * 0.95, -rad * 0.55, rad * 0.22, 0, TAU); g.fill(); g.fillStyle = '#fff0b0'; g.beginPath(); g.arc(-rad * 0.95, -rad * 0.55, rad * 0.1, 0, TAU); g.fill(); }
    else if (k === 'guard') { g.fillStyle = '#56606e'; g.strokeStyle = '#141110'; g.lineWidth = 1.6; g.beginPath(); g.ellipse(-rad * 0.35, -rad * 0.95, rad * 0.75, rad * 0.26, 0, 0, TAU); g.fill(); g.stroke(); hand(rad * 0.9, 0, rad * 1.3, 3, '#9a9ea6', 0.3); }
    else if (k === 'sword') hand(rad * 0.6, -rad * 0.1, rad * 2.6, 3.2, '#c8ccd4', -sw * 0.9);
    else if (k === 'archer' || k === 'skeleton') bow(0, -rad * 0.6);
    else if (k === 'healer') { hand(rad * 0.85, 0, rad * 2, 2.4, '#7a5a36', 0.15); g.fillStyle = '#9ade7a'; g.beginPath(); g.arc(rad * 0.85 + Math.sin(0.15) * rad * 2, -Math.cos(0.15) * rad * 2, rad * 0.22 * (1 + (s.k < 0.3 ? 0.4 : 0)), 0, TAU); g.fill(); }
    else if (k === 'goblin') hand(rad * 0.8, 0, rad * 1.7, 2.6, '#8a8a80', -sw + (s.act === 'windup' ? 0 : 0.2));
    else if (k === 'boss') hand(rad * 0.9, 0, rad * 2.2, 5, '#5a5048', -sw + 0.2 - (s.burst ? 1.4 * (1 - s.burst) : 0));
    else if (s.a.job === 'craft') hand(rad * 0.8, 0, rad * 1.4, 2.4, '#7a5a36', -sw);
    else if (s.a.job === 'farm') hand(rad * 0.8, 0, rad * 1.8, 2, '#7a5a36', 0.4 + sw);
    g.restore();
  }
}
