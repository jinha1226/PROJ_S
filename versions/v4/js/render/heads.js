/* ================= 머리 · 얼굴 · 머리 모양 (인형 부품) =================
   머리 가운데(0, y, z)를 기준으로 부품 목록을 만든다. 주인공과 주민이 함께 쓴다.
   머리 모양: short(짧은 머리 + 옆으로 넘긴 앞머리) · bob(단발) · pony(묶은 머리) · long(긴 머리) · buzz(아주 짧게) · bald(민머리) */
const R = [0.27, 0.275, 0.255];
const lighter = (c, k) => { const r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255, f = (v) => Math.min(255, Math.round(v + (255 - v) * k)); return (f(r) << 16) | (f(g) << 8) | f(b); };
const darker = (c, k) => { const r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255, f = (v) => Math.round(v * (1 - k)); return (f(r) << 16) | (f(g) << 8) | f(b); };

/** 얼굴: 흰자 · 눈동자 · 반짝임 · 윗눈꺼풀 선 · 눈썹 · 코 · 입 · 볼 */
export function faceParts({ y = 0.76, z = 0.025, skin, hair = 0x664630, eye = 0x3b4b40, mood = 0, style = 'short', cover = 0 }) {
  const brows = cover >= 2 || style === 'buzz' || style === 'bald'; // 앞머리가 이마를 덮으면 눈썹은 가려진다
  const out = [], lid = 0x2a2020, Z = z + 0.245;
  for (const sx of [-1, 1]) {
    const ex = 0.087 * sx;
    out.push(
      { s: 'sphere', p: [ex, y + 0.004, Z], k: [0.054, 0.07, 0.022], c: 0xfff8e9, outline: false },
      { s: 'sphere', p: [ex - 0.004 * sx, y - 0.004, Z + 0.016], k: [0.034, 0.05, 0.013], c: eye, outline: false },
      { s: 'sphere', p: [ex - 0.004 * sx, y - 0.01, Z + 0.023], k: [0.018, 0.028, 0.008], c: darker(eye, 0.55), outline: false },
      { s: 'sphere', p: [ex + 0.014 * sx * -1, y + 0.022, Z + 0.029], k: 0.012, c: 0xffffff, outline: false },
      { s: 'tube', path: [[0.136 * sx, y + 0.036, Z - 0.022], [0.09 * sx, y + 0.078, Z + 0.004], [0.048 * sx, y + 0.05, Z + 0.004]], r0: 0.012, r1: 0.006, rs: 6, ts: 6, c: lid, outline: false }, // 윗눈꺼풀
      { s: 'sphere', p: [0.165 * sx, y - 0.066, Z - 0.03], k: [0.036, 0.018, 0.014], c: 0xe8a898, outline: false }, // 볼
    );
    if (brows) out.push({ s: 'tube', path: [[0.13 * sx, y + 0.104 - mood * 0.01, Z - 0.028], [0.09 * sx, y + 0.12, Z - 0.008], [0.052 * sx, y + 0.112 + mood * 0.012, Z - 0.006]], r0: 0.011, r1: 0.008, rs: 6, ts: 6, c: darker(hair, 0.2), outline: false }); // 눈썹
  }
  const smile = 0.006 + mood * 0.006;
  out.push(
    { s: 'sphere', p: [0, y - 0.06, Z + 0.016], k: [0.022, 0.02, 0.014], c: darker(skin, 0.12), outline: false }, // 코
    { s: 'tube', path: [[-0.034, y - 0.088 + smile * 0.3, Z - 0.004], [0, y - 0.1 - smile * 0.4, Z + 0.002], [0.034, y - 0.088 + smile * 0.3, Z - 0.004]], r0: 0.009, r1: 0.009, rs: 6, ts: 6, c: 0x7a3a30, outline: false }, // 입
  );
  return out;
}

/** 머리 모양. cover: 모자·투구가 덮는 정도 — 0 없음, 1 모자(옆·뒤만), 2 투구·두건(옆머리만) */
export function hairParts({ y = 0.76, z = 0.025, hair = 0x664630, style = 'short', cover = 0, seed = 0 }) {
  if (style === 'bald') return [];
  const out = [], zc = z - 0.02, hi = lighter(hair, 0.28), sh = 0.28;
  const dome = { s: 'lathe', p: [0, y, zc], pts: [[0.296, 0.09], [0.29, 0.16], [0.245, 0.232], [0.165, 0.283], [0.07, 0.302], [0, 0.305]], seg: 24, c: hair, shade: 0.15, paint: [{ c: hi, a: 1.1, y0: y + 0.2, y1: y + 0.235 }] };
  const back = (len, flare = 0.02) => ({ s: 'lathe', p: [0, y, zc], pts: [[0.27 + flare, -len], [0.3, -len * 0.6], [0.306, 0], [0.3, 0.1], [0.296, 0.16]], phi0: 0.95, phiLen: Math.PI * 2 - 1.9, seg: 26, wave: 0.1, waveN: 11, waveTop: 0.05, c: hair, shade: sh });
  /** 뒤로 흘러내리는 머리 가닥(뒷모습이 밥그릇처럼 밋밋하지 않게) */
  const strands = (len, n = 5) => Array.from({ length: n }, (_, i) => { const a = Math.PI + (i - (n - 1) / 2) * 0.42, sx = Math.sin(a), cz = Math.cos(a); return { s: 'tube', path: [[sx * 0.1, y + 0.29, zc + cz * 0.1], [sx * 0.27, y + 0.13, zc + cz * 0.28], [sx * 0.3, y - len, zc + cz * 0.29]], r0: 0.07, r1: 0.022, rs: 8, ts: 8, c: i % 2 ? hair : lighter(hair, 0.1), shade: 0.2 }; });
  const lock = (sx, len = 0.12) => ({ s: 'tube', path: [[0.235 * sx, y + 0.16, zc + 0.1], [0.278 * sx, y + 0.03, zc + 0.14], [0.258 * sx, y - len, zc + 0.12]], r0: 0.05, r1: 0.017, rs: 8, c: hair, shade: 0.2 });
  const bangs = (n = 6, swept = 0.03) => Array.from({ length: n }, (_, i) => {
    const t = i / (n - 1), x0 = -0.17 + t * 0.34, end = 0.09 + ((i + seed) % 2) * 0.035;
    const tx = x0 + swept, tz = zc + 0.255 * Math.sqrt(Math.max(0, 1 - (tx / 0.27) ** 2 - (end / 0.275) ** 2)) + 0.03; // 끝은 이마에 붙는다
    return { s: 'tube', path: [[x0 * 0.6, y + 0.285, zc + 0.08], [x0 * 0.95, y + 0.225, zc + 0.215], [tx, y + end, tz]], r0: 0.056, r1: 0.02, rs: 8, ts: 8, c: i % 3 === 1 ? hi : hair, outline: false };
  });
  if (cover >= 2) { out.push(lock(-1, 0.08), lock(1, 0.08)); return out; }
  if (cover === 1) { out.push(back(0.14), lock(-1), lock(1)); return out; }
  if (style === 'buzz') { out.push({ ...dome, pts: dome.pts.map(([r, q]) => [r - 0.012, q]) }, { ...back(0.02, 0), wave: 0 }); return out; }
  out.push(dome);
  if (style === 'short') out.push(back(0.14), ...strands(0.12), lock(-1), lock(1), ...bangs(6, 0.03), { s: 'tube', path: [[0, y + 0.29, zc - 0.02], [0.02, y + 0.35, zc - 0.03], [0.06, y + 0.36, zc]], r0: 0.02, r1: 0.006, rs: 6, c: hair }); // 삐친 머리
  else if (style === 'bob') out.push(back(0.2, 0.045), ...strands(0.18, 6), lock(-1, 0.18), lock(1, 0.18), ...bangs(7, 0));
  else if (style === 'pony') out.push(back(0.1), ...strands(0.06, 4), lock(-1, 0.06), lock(1, 0.06), ...bangs(5, 0.02), { s: 'sphere', p: [0, y + 0.1, zc - 0.29], k: 0.05, c: 0xc0504a }, { s: 'tube', path: [[0, y + 0.1, zc - 0.31], [0, y - 0.05, zc - 0.4], [0, y - 0.24, zc - 0.36]], r0: 0.07, r1: 0.025, rs: 10, c: hair, shade: sh });
  else if (style === 'long') out.push(back(0.42, 0.06), ...strands(0.4, 6), lock(-1, 0.3), lock(1, 0.3), ...bangs(6, -0.01));
  return out;
}

/** 머리에 쓰는 것: hood(두건) · hat(챙 모자) · helm(투구) — 얼굴은 비우고 머리를 감싼다 */
export function hatParts(kind, { y = 0.76, z = 0.025, c = 0xe8d8b0, trim = 0x7a4a28 }) {
  const zc = z - 0.02, open = { phi0: 1.0, phiLen: Math.PI * 2 - 2.0 };
  if (kind === 'hood') return [
    { s: 'lathe', p: [0, y, zc], pts: [[0.335, 0.05], [0.33, 0.16], [0.28, 0.255], [0.18, 0.32], [0.07, 0.342], [0, 0.345]], seg: 24, c, shade: 0.15 },
    { s: 'lathe', p: [0, y, zc], phi0: 0.8, phiLen: Math.PI * 2 - 1.6, pts: [[0.37, -0.3], [0.345, -0.18], [0.335, -0.02], [0.335, 0.1]], seg: 24, wave: 0.06, waveN: 9, waveTop: -0.1, c, shade: 0.3 },
    ...[-1, 1].map((sx) => ({ s: 'tube', path: [[0.2 * sx, y + 0.3, zc + 0.2], [0.3 * sx, y + 0.08, zc + 0.24], [0.27 * sx, y - 0.2, zc + 0.24]], r0: 0.05, r1: 0.06, rs: 10, c: trim, shade: 0.2 })), // 얼굴 옆 가장자리
    { s: 'tube', path: [[-0.2, y + 0.3, zc + 0.2], [0, y + 0.36, zc + 0.22], [0.2, y + 0.3, zc + 0.2]], r0: 0.05, r1: 0.05, rs: 10, c: trim }, // 이마 위 가장자리
    { s: 'tube', path: [[0, y + 0.28, zc - 0.2], [0, y + 0.18, zc - 0.36], [0, y + 0.02, zc - 0.38]], r0: 0.07, r1: 0.02, rs: 10, c, shade: 0.2 }, // 뒤로 늘어진 끝
  ];
  if (kind === 'hat') return [
    { s: 'lathe', p: [0, y, zc], pts: [[0, 0.095], [0.46, 0.1], [0.5, 0.135], [0.48, 0.15], [0.3, 0.125], [0, 0.12]], seg: 28, c: trim, shade: 0.2 }, // 챙(가장자리가 살짝 말림)
    { s: 'lathe', p: [0, y, zc], pts: [[0.29, 0.1], [0.285, 0.2], [0.255, 0.3], [0.17, 0.36], [0, 0.375]], seg: 24, c, shade: 0.2, paint: [{ c: trim, y0: y + 0.13, y1: y + 0.18 }] }, // 머리 부분 + 띠
  ];
  return [ // 투구: 둥근 머리 + 이마 테 + 코 가리개 + 사슬 목가리개
    { s: 'lathe', p: [0, y, zc], pts: [[0.305, 0.07], [0.3, 0.17], [0.255, 0.255], [0.16, 0.31], [0, 0.33]], seg: 24, c, shade: 0.15 },
    { s: 'torus', p: [0, y + 0.08, zc], r: [Math.PI / 2, 0, 0], k: [0.305, 0.3, 0.14], tube: 0.2, c: trim },
    { s: 'box', p: [0, y + 0.02, zc + 0.3], k: [0.035, 0.15, 0.03], c: trim },
    { s: 'lathe', p: [0, y, zc], ...open, pts: [[0.33, -0.2], [0.31, -0.1], [0.305, 0.07]], seg: 24, c: 0x6a7280, shade: 0.25, paint: [{ c: 0x565d68, band: 0.03 }] },
  ];
}

/** 머리 전체: 얼굴 + 귀 + 머리 모양 */
export function headParts(o) {
  const { y = 0.76, z = 0.025, skin, ears = true } = o;
  return [
    { s: 'sphere', p: [0, y, z], k: R, c: skin },
    ...(ears ? [-1, 1].map((sx) => ({ s: 'sphere', p: [0.266 * sx, y - 0.035, z + 0.015], k: [0.054, 0.075, 0.035], c: skin })) : []),
    ...faceParts(o),
    ...hairParts(o),
  ];
}
