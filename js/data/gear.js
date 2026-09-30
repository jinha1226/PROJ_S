import { ZONE_FLOORS } from './terrain.js';
import { OLD_WEAPON, WEAPONS, WPN } from './weapons.js';

/* ================= 장비 (DCSS식 — docs/설계_아이템_장비.md) =================
   기본템 + 강화치(+N) + 속성 하나(무기 브랜드 / 방어구 에고) · 장신구(모양만 보이는 반지·목걸이)
   · 랜다트(무작위 유물) · 픽다트(옛 등불지기의 유품). 등급 색은 없다. */
/** 장비 칸 10개: 무기·보조손(버클러·방패·오브, 한손 무기일 때만) + 방어구·장신구. 무기 세트·교체는 없다 */
export const SLOTS = ['weapon', 'off', 'head', 'body', 'cloak', 'hands', 'feet', 'neck', 'ring1', 'ring2'];
export const SLOT_NAME = { weapon: '무기', off: '보조손', head: '머리', body: '몸통', cloak: '망토', hands: '장갑', feet: '신발', neck: '목걸이', ring1: '반지', ring2: '반지', ring: '반지' };
export const SLOT_ICON = { weapon: '⚔', off: '🛡', head: '⛑', body: '👕', cloak: '🧥', hands: '🧤', feet: '🥾', neck: '📿', ring1: '💍', ring2: '💍', ring: '💍' };
export const BAG_MAX = 20;

const MAT = { cloth: '천', leather: '가죽', chain: '사슬', plate: '판금' };
export const MAT_COLOR = { cloth: 0xe8d8b0, leather: 0x9a6a3a, chain: 0x7e8796, plate: 0xaeb9c8 };
const arm = (slot, mat, name, def, eva = 0, o = {}) => ({ slot, mat, name, def, eva, ...o });
/** 기본템 (§5) */
export const GEAR_BASES = {
  ...Object.fromEntries(Object.keys(WEAPONS).map((k) => [k, { slot: 'weapon', weapon: k, name: WEAPONS[k].name }])),
  buckler: { slot: 'off', name: '버클러', def: 1, block: 10 },
  shield: { slot: 'off', name: '방패', def: 2, block: 20, eva: -2 },
  orb_red: { slot: 'off', orb: 'red', name: '붉은 오브' }, orb_purple: { slot: 'off', orb: 'purple', name: '보랏빛 오브' }, orb_green: { slot: 'off', orb: 'green', name: '초록 오브' },
  body_cloth: arm('body', 'cloth', '천옷', 0, 5), body_leather: arm('body', 'leather', '가죽 갑옷', 2), body_chain: arm('body', 'chain', '사슬 갑옷', 4, -4), body_plate: arm('body', 'plate', '판금 갑옷', 6, -8),
  head_cloth: arm('head', 'cloth', '두건', 0), head_leather: arm('head', 'leather', '가죽 모자', 1), head_chain: arm('head', 'chain', '투구', 1, -1),
  cloak: arm('cloak', 'cloth', '망토', 1),
  gloves: arm('hands', 'leather', '장갑', 1),
  boots: arm('feet', 'leather', '신발', 1),
  neck: { slot: 'neck', name: '목걸이', jewel: true },
  ring: { slot: 'ring', name: '반지', jewel: true },
};
/** 오브 (§4.1): 강화 +N = 효과 한 단계 */
export const ORBS = {
  red: { line: (n) => `빨강 영혼석 스킬 피해 +${n}` },
  purple: { line: (n) => `보라 영혼석 스킬의 범위나 지속이 ${n}단계 는다` },
  green: { line: (n) => `초록 영혼석 스킬을 쓰면 보호막 ${n + 1}을 얻는다` },
};
/** 품질 (§5): 구역마다 한 단계. 무기 피해 +0~3, 방어구·방패 방어 +0/+0/+1/+1 */
export const QUALITY = [null, { name: '낡은', dmg: 0, def: 0 }, { name: '평범한', dmg: 1, def: 0 }, { name: '좋은', dmg: 2, def: 1 }, { name: '명장의', dmg: 3, def: 1 }];
export const hasQuality = (base) => { const B = GEAR_BASES[base]; return !B.jewel && !B.orb; };
/** 강화 상한: 무기 +6, 몸통 +4, 그 밖 +2 (장신구는 강화 없음) */
export const plusMax = (it) => { const B = GEAR_BASES[it.base]; return B.jewel ? 0 : B.weapon ? 6 : B.slot === 'body' ? 4 : 2; };

/** 원소 색 · 이름 */
export const ELEM = { fire: { name: '불', css: '#ff8a3a', hex: 0xff7a1a }, frost: { name: '냉기', css: '#8fdcff', hex: 0x8fdcff }, bolt: { name: '번개', css: '#ffe14a', hex: 0xffe14a }, poison: { name: '독', css: '#79e05a', hex: 0x79e05a } };

/** 무기 브랜드 (§7.1, 하나만) */
export const BRANDS = {
  fire: { name: '화염', line: '맞히면 불 2. 풀과 기름에 불이 붙는다', elem: 'fire' },
  frost: { name: '냉기', line: '맞히면 냉기 2. 젖은 적은 1초 얼어붙는다', elem: 'frost' },
  bolt: { name: '번개', line: '맞히면 25% 확률로 번개 3. 젖은 적이면 번진다', elem: 'bolt' },
  poison: { name: '독', line: '맞히면 중독 2', elem: 'poison' },
  blood: { name: '피', line: '출혈이 2 더 쌓인다', form: 'slash', css: '#ff5a6a' },
  shatter: { name: '파쇄', line: '골절이 더 오래 가고, 골절시킬 때 1칸 밀친다', form: 'blunt', css: '#d8c8a8' },
  pierce: { name: '꿰뚫기', line: '급소 피해가 50% 더 들어간다', form: 'pierce', css: '#ffd27a' },
  vamp: { name: '흡혈', line: '입힌 피해의 30%만큼 회복한다. 해골에게는 통하지 않는다', css: '#c83a5a' },
  reso: { name: '공명', line: '빨강 영혼석 쿨타임이 한 라운드에 한 번 더 줄 수 있다', css: '#ff6a7a' },
};
/** 방어구 에고 (§7.2, 하나만) */
export const EGOS = {
  rFire: { name: '불 저항', slots: ['body', 'cloak', 'off'], line: '불 저항 +1', res: 'fire' },
  rFrost: { name: '냉기 저항', slots: ['body', 'cloak', 'off'], line: '냉기 저항 +1', res: 'frost' },
  rBolt: { name: '번개 저항', slots: ['body', 'cloak', 'off'], line: '번개 저항 +1', res: 'bolt' },
  rPoison: { name: '독 저항', slots: ['body', 'cloak', 'off'], line: '독 저항 +1', res: 'poison' },
  thorns: { name: '가시', slots: ['body'], line: '붙어서 나를 때린 적에게 피해 2', css: '#c8a060' },
  protect: { name: '보호', slots: ['body', 'off'], line: '층마다 보호막 4를 두르고 시작한다', css: '#9fd8ff' },
  patience: { name: '기다림', slots: ['cloak'], line: '제자리에서 시간을 흘리면 1초마다 보호막 2를 얻는다', css: '#c27dff' },
  vengeance: { name: '되갚음', slots: ['body', 'off'], line: '맞으면 다음 무기 공격의 피해가 2 는다', css: '#62e27a' },
  insight: { name: '통찰', slots: ['head'], line: '시야가 1칸 넓어지고, 적의 약점을 처음부터 안다', css: '#ffe38a' },
  waterwalk: { name: '물걸음', slots: ['feet'], line: '물에 젖지 않고, 얼음에서 미끄러지지 않는다', css: '#4d97ff' },
  ember: { name: '불씨 품기', slots: ['cloak'], line: '횃불이 25% 느리게 탄다', css: '#ffb040' },
  smash: { name: '강타', slots: ['hands'], line: '적이 벽에 부딪힐 때 피해가 2 는다', css: '#d8c8a8' },
  throw: { name: '투척', slots: ['hands'], line: '물건을 1칸 더 멀리 던진다', css: '#b8d0e0' },
};
/** 반지 (§7.3) — obvious: 끼는 즉시 정체가 드러난다 · ench: 수치(강화치)가 있다 */
export const RINGS = {
  prot: { name: '보호', line: '방어 {v}', ench: [-2, 4], obvious: true },
  eva: { name: '회피', line: '회피 {v}%', ench: [-3, 8], obvious: true },
  str: { name: '힘', line: '피해 {v}', ench: [-1, 3], obvious: true },
  vit: { name: '체력', line: '최대 HP +5', obvious: true },
  res: { name: '저항', line: '{e} 저항 +1' },
  red: { name: '분노', line: '빨강 영혼석이 한 턴 빨리 돈다', color: 'red' },
  purple: { name: '명상', line: '보라 영혼석이 한 턴 빨리 돈다', color: 'purple' },
  green: { name: '인내', line: '초록 영혼석이 한 턴 빨리 돈다', color: 'green' },
  see: { name: '투시', line: '벽 너머 2칸의 적이 보인다' },
};
export const AMULETS = {
  memory: { name: '기억', line: '횃불이 30% 느리게 탄다. 등잔에서 횃불을 20 더 얻는다' },
  regen: { name: '재생', line: '전투 밖에서 0.6초마다 HP 1을 회복한다' },
  chain: { name: '연쇄', line: '연쇄가 한 단계 높게 시작한다. 3단계 이상이면 보호막 2를 얻는다' },
  reflect: { name: '반사', line: '화살을 20% 확률로 되돌린다' },
  silence: { name: '고요', line: '들키기 전에 제자리에 서 있으면 적이 나를 지나칠 수 있다' },
};
/** 장신구 모양(원정마다 정체와 짝이 섞인다) */
export const JEWEL_LOOK = {
  ring: ['루비', '사파이어', '뼈', '흑요석', '호박', '은', '녹슨 쇠', '비취', '산호', '진주', '유리', '청동'],
  neck: ['뼈', '호박', '은 사슬', '깃털', '이빨', '유리 구슬', '조개'],
};

/** 랜다트 (§8): 속성 2~4개 + 대가(40%) */
export const RANDART_PROPS = ['dmg', 'def', 'eva', 'maxHp', 'res', 'vision', 'cd', 'brand', 'ego'];
export const RANDART_COSTS = ['maxHp', 'torch', 'vision', 'eva', 'cdUp'];
export const ART_A = ['잿빛', '굶주린', '고요한', '떨리는', '잊힌', '서늘한', '검은', '금빛', '깨진', '숨은', '타버린', '젖은'];
export const ART_B = ['속삭임', '맹세', '송곳니', '그림자', '약속', '비명', '파편', '등불', '발자국', '가시', '물결', '뿌리'];

/** 픽다트 = 옛 등불지기의 유품 (§9) */
export const UNRANDS = {
  mistCloak: { base: 'cloak', name: '물안개 망토', owner: '이랑', line: '제자리에서 시간을 흘리면 1초마다 주변 1칸이 젖는다', story: '호숫가 뱃사공 출신 등불지기가 두르던 것' },
  bloodFang: { base: 'twin', plus: 2, name: '피의 송곳니', owner: '다솜', line: '출혈 중인 적이 죽으면 곁의 적들에게 출혈 2', story: '굶주린 해에 사냥으로 마을을 먹여 살린 이의 칼' },
  thornPlate: { base: 'body_plate', plus: 1, name: '가시 판금', owner: '무진', line: '맞을 때마다 초록 영혼석 쿨타임이 1 더 준다. 받는 피해가 20% 는다', story: '물러서지 않았던 문지기의 갑옷' },
  stormRing: { base: 'ring', name: '번개 감긴 반지', owner: '하율', line: '번개가 1칸 더 멀리 번진다', story: '폭풍을 셌던 학자의 반지' },
  giantMace: { base: 'mace', plus: 1, name: '거인의 철퇴', owner: '석주', line: '1칸 더 멀리 밀친다. 적이 벽에 부딪히면 주변에 피해 1', story: '광산 붕괴에서 동료를 파낸 광부의 망치' },
  alchGlove: { base: 'gloves', name: '연금술사의 장갑', owner: '보늬', line: '던지는 물건이 두 개로 나뉘어 날아간다', story: '불씨 단지를 처음 만든 이의 장갑' },
  firstLamp: { base: 'neck', name: '첫 불씨 등잔', owner: '첫 등불지기', line: '횃불이 꺼져도 3칸까지는 보인다', story: '모닥불을 처음 옮겨 붙인 등불지기의 등잔' },
  namelessHelm: { base: 'head_chain', name: '이름 없는 투구', owner: null, line: '곧 공격을 예고할 적이 미리 보인다', story: '누구의 것인지 아무도 기억하지 못한다' },
};

/** 떨어진 장비의 종류 (§11) [평범, 강화치, 속성, 랜다트, 픽다트] */
export function dropTable(depth) {
  const z = Math.ceil(depth / ZONE_FLOORS); // 구역
  return z <= 1 ? [70, 20, 8, 2, 0] : z === 2 ? [55, 25, 14, 5, 1] : z === 3 ? [45, 25, 20, 8, 2] : [35, 25, 25, 12, 3];
}
export const GEAR_DROP = { default: 5, goblin_armor: 15, charger: 15 };

/** 저항 7단계 → 받는 피해 배율 (docs/밸런스_기준.md §3) */
export const RES_MUL = { '-3': 2.5, '-2': 2, '-1': 1.5, 0: 1, 1: 0.5, 2: 0.33, 3: 0.2 };
export const clampRes = (v) => Math.max(-3, Math.min(3, v));
export const CAPS = { def: 15, eva: 40, block: 30 };
export const BASE_EVA = 10;

/** 옛 저장의 스킬 id → 이어받은 영혼석 */
export const OLD_SKILL = { push: 'r_push', fire: 'r_fire', bolt: 'r_shock', frost: 'r_freeze', venom: 'r_poison' };
export const stoneOfSkill = (k) => OLD_SKILL[k] || k;

export const slotKind = (it) => GEAR_BASES[it.base].slot;
export const fitsSlot = (it, slot) => { const k = slotKind(it); return k === slot || (k === 'ring' && (slot === 'ring1' || slot === 'ring2')); };
/** 옛 기본템 id → 새 id (단검 → 쌍단검) */
export const newBase = (b) => OLD_WEAPON[b] || b;
/** 무기 장비 → 형태·피해(강화치·품질은 따로) — 없으면 맨손 장검 취급 */
export function weaponOf(it) { const b = it && GEAR_BASES[it.base]; return b && b.weapon ? WPN(b.weapon) : WPN('sword'); }
export const twoHanded = (it) => !!(it && GEAR_BASES[it.base].weapon && WEAPONS[GEAR_BASES[it.base].weapon].hands === 2);
export const weaponId = (it) => (it && GEAR_BASES[it.base].weapon) || 'sword';
export const isWeapon = (it) => !!(it && GEAR_BASES[it.base].weapon);
export const isJewel = (it) => !!(it && GEAR_BASES[it.base].jewel);
export const matName = (b) => MAT[GEAR_BASES[b].mat];
