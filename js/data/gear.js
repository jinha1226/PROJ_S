import { WEAPONS, WPN } from './weapons.js';

/* ---------- 장비: 칸 · 기본 아이템 · 등급 · 옵션 · 전설 (docs/설계_아이템_장비.md) ---------- */
export const SLOTS = ['weapon', 'off', 'head', 'body', 'hands', 'feet', 'neck', 'ring1', 'ring2'];
export const SLOT_NAME = { weapon: '무기', off: '보조', head: '머리', body: '몸통', hands: '장갑', feet: '신발', neck: '목걸이', ring1: '반지', ring2: '반지', ring: '반지' };
export const SLOT_ICON = { weapon: '⚔', off: '🛡', head: '⛑', body: '👕', hands: '🧤', feet: '🥾', neck: '📿', ring1: '💍', ring2: '💍', ring: '💍' };
export const BAG_MAX = 20;

export const RARITY = {
  common: { name: '일반', css: '#e8e8ee', hex: 0xe8e8ee, n: [0, 0] },
  magic: { name: '마법', css: '#6aa8ff', hex: 0x5a9aff, n: [1, 2] },
  rare: { name: '희귀', css: '#ffd84a', hex: 0xffd84a, n: [3, 4] },
  legend: { name: '전설', css: '#ff8a2a', hex: 0xff8a2a, n: [1, 2] },
};
export const RARITY_ORDER = ['common', 'magic', 'rare', 'legend'];

const MAT = { cloth: '천', leather: '가죽', chain: '사슬', plate: '판금' };
export const MAT_COLOR = { cloth: 0xe8d8b0, leather: 0x9a6a3a, chain: 0x7e8796, plate: 0xaeb9c8 };
const armorBase = (slot, mat, name, def, eva) => ({ slot, mat, name, def, eva });
export const GEAR_BASES = {
  ...Object.fromEntries(Object.keys(WEAPONS).map((k) => [k, { slot: 'weapon', weapon: k, name: WEAPONS[k].name }])),
  shield: { slot: 'off', name: '방패', def: 1, block: 15 },
  torch: { slot: 'off', name: '횃불', vision: 1, torchFire: 1 },
  body_cloth: armorBase('body', 'cloth', '천옷', 0, 5), body_leather: armorBase('body', 'leather', '가죽 갑옷', 1, 0),
  body_chain: armorBase('body', 'chain', '사슬 갑옷', 2, -3), body_plate: armorBase('body', 'plate', '판금 갑옷', 3, -6),
  head_cloth: armorBase('head', 'cloth', '두건', 0, 2), head_leather: armorBase('head', 'leather', '가죽 모자', 0, 1),
  head_chain: armorBase('head', 'chain', '투구', 1, -1), head_plate: armorBase('head', 'plate', '뿔 투구', 1, -2),
  hands_cloth: armorBase('hands', 'cloth', '천 장갑', 0, 2), hands_leather: armorBase('hands', 'leather', '가죽 장갑', 0, 1),
  hands_chain: armorBase('hands', 'chain', '사슬 장갑', 1, -1), hands_plate: armorBase('hands', 'plate', '판금 장갑', 1, -2),
  feet_cloth: armorBase('feet', 'cloth', '천 신발', 0, 2), feet_leather: armorBase('feet', 'leather', '가죽 장화', 0, 1),
  feet_chain: armorBase('feet', 'chain', '사슬 장화', 1, -1), feet_plate: armorBase('feet', 'plate', '판금 장화', 1, -2),
  neck: { slot: 'neck', name: '목걸이' },
  ring: { slot: 'ring', name: '반지' },
};
export const WEAPON_TRAIT = { axe: { acc: -5, line: '명중 −5%' }, hammer: { acc: -5, line: '명중 −5%' }, dagger: { crit: 10, line: '급소 확률 +10%' }, spear: { reach: 2, line: '2칸 거리 공격(사이가 비어야 함)' } };

const ARMOR = ['body', 'head', 'hands', 'feet'];
const ELEM = { fire: '불', bolt: '번개', frost: '냉기', poison: '독' };
/** 옵션 풀. t1 = 1~6층, t2 = 7~12층. form: 그 형태 무기에만. flag: 수치 없음. */
export const AFFIXES = {
  hp: { cat: 'basic', t1: [3, 5], t2: [6, 8], slots: ['body', 'head', 'neck', 'ring'], line: '최대 HP +{v}', pre: '튼튼한', suf: '곰의' },
  def: { cat: 'basic', t1: [1, 1], t2: [2, 2], slots: ARMOR, line: '방어 +{v}', pre: '단단한', suf: '거북의' },
  eva: { cat: 'basic', t1: [3, 5], t2: [6, 8], slots: ['feet', 'hands', 'ring'], line: '회피 +{v}%', pre: '날렵한', suf: '여우의' },
  dmg: { cat: 'basic', t1: [1, 1], t2: [2, 2], slots: ['weapon', 'hands', 'ring'], line: '피해 +{v}', pre: '날카로운', suf: '늑대의' },
  ...Object.fromEntries(Object.entries(ELEM).map(([k, nm]) => [k + 'Dmg', { cat: 'elem', t1: [1, 1], t2: [2, 2], slots: ['weapon', 'neck'], line: `${nm} 피해 +{v}`, pre: { fire: '불타는', bolt: '번개 치는', frost: '서리 낀', poison: '독 묻은' }[k], suf: `${nm}의` }])),
  ...Object.fromEntries(Object.entries(ELEM).map(([k, nm]) => ['res' + k, { cat: 'elem', t1: [10, 15], t2: [20, 25], slots: [...ARMOR, 'ring'], line: `${nm} 저항 +{v}%`, pre: `${nm}을 막는`, suf: `${nm} 수호의` }])),
  wetDmg: { cat: 'elem', t1: [1, 1], t2: [2, 2], slots: ['weapon', 'hands'], line: '젖은 적에게 피해 +{v}', pre: '물먹은', suf: '빗줄기의' },
  dot: { cat: 'elem', t1: [1, 1], t2: [2, 2], slots: ['neck', 'ring'], line: '화상·중독 지속 +{v}턴', pre: '끈질긴', suf: '역병의' },
  bleed: { cat: 'form', form: 'slash', t1: [1, 1], t2: [2, 2], slots: ['weapon', 'hands'], line: '베기 출혈 +{v}', pre: '톱날', suf: '피의' },
  fracPush: { cat: 'form', form: 'blunt', flag: true, slots: ['weapon'], line: '타격 골절 시 1칸 밀치기', pre: '육중한', suf: '망치질의' },
  crit: { cat: 'form', form: 'pierce', t1: [5, 5], t2: [10, 10], slots: ['weapon', 'hands'], line: '찌르기 급소 확률 +{v}%', pre: '예리한', suf: '송곳의' },
  weakDmg: { cat: 'form', t1: [1, 1], t2: [2, 2], slots: ['weapon'], line: '약점 형태로 칠 때 피해 +{v}', pre: '약점 노리는', suf: '사냥꾼의' },
  waterEva: { cat: 'terrain', t1: [10, 10], t2: [15, 15], slots: ['feet'], line: '물 위에서 회피 +{v}%', pre: '물갈퀴', suf: '수달의' },
  burnImm: { cat: 'terrain', flag: true, slots: ['feet'], line: '풀·불 위에서 화상 면역', pre: '그을린', suf: '화덕의' },
  noSlide: { cat: 'terrain', flag: true, slots: ['feet'], line: '얼음에서 미끄러지지 않음', pre: '징 박힌', suf: '빙판의' },
  wallDmg: { cat: 'terrain', t1: [1, 1], t2: [2, 2], slots: ['hands', 'weapon'], line: '벽 충돌 피해 +{v}', pre: '부수는', suf: '성벽의' },
  throwArea: { cat: 'item', flag: true, slots: ['hands'], line: '던지는 물건 범위 +1', pre: '멀리 뿌리는', suf: '투척의' },
  potion: { cat: 'item', t1: [20, 20], t2: [40, 40], slots: ['neck', 'body'], line: '물약 회복 +{v}%', pre: '약초 향 나는', suf: '연금의' },
  autoId: { cat: 'item', flag: true, slots: ['head'], line: '미확인 소모품을 주우면 즉시 확인', pre: '눈 밝은', suf: '감정사의' },
  redTwice: { cat: 'stone', t1: [5, 5], t2: [10, 10], slots: ['weapon', 'ring'], line: '빨강 발동 시 {v}% 확률로 한 번 더', pre: '붉게 달군', suf: '분노의' },
  purpleHeal: { cat: 'stone', t1: [1, 1], t2: [2, 2], slots: ['neck', 'body'], line: '보라 발동 시 HP +{v}', pre: '고요한', suf: '명상의' },
  greenShield: { cat: 'stone', t1: [1, 1], t2: [2, 2], slots: ['body', 'off'], line: '초록 발동 시 보호막 +{v}', pre: '푸른', suf: '버팀의' },
  skillCd: { cat: 'skill', flag: true, skill: true, slots: ['head', 'neck'], line: '{skill} 재사용 대기 −1', pre: '재빠른', suf: '숙련의' },
  skillDmg: { cat: 'skill', t1: [1, 1], t2: [2, 2], slots: ['head', 'neck'], line: '스킬 피해 +{v}', pre: '주문 새긴', suf: '마법사의' },
  floorShield: { cat: 'craft', t1: [4, 4], t2: [6, 6], slots: [], line: '층마다 보호막 {v}로 시작', pre: '뼈로 엮은', suf: '뼈의' },
};
export const CAPS = { def: 6, eva: 40, block: 30, maxHp: 20, res: 50 };
export const BASE_EVA = 10;

export const LEGENDS = {
  mistCloak: { base: 'body_cloth', name: '물안개 망토', line: '대기할 때마다 내 주변 1칸이 젖는다' },
  bloodFang: { base: 'dagger', name: '피의 송곳니', line: '출혈 중인 적이 죽으면 피가 터져 주변 1칸 적에게 출혈 2' },
  thornPlate: { base: 'body_plate', name: '가시 판금', line: '맞으면 초록 영혼석이 두 번 발동. 받는 피해 +20%' },
  stormRing: { base: 'ring', name: '번개 감긴 반지', line: '번개가 번질 때 1칸 더 멀리 번진다' },
  giantMace: { base: 'mace', name: '거인의 철퇴', line: '밀치기가 1칸 더 멀리. 벽 충돌 시 주변도 흔들려 1 피해' },
  alchGlove: { base: 'hands_leather', name: '연금술사의 장갑', line: '던지는 물건이 두 개로 나뉘어 날아간다' },
};

export const RARE_A = ['잿빛', '붉은', '고요한', '떨리는', '잊힌', '서늘한', '검은', '금빛', '깨진', '숨은'];
export const RARE_B = ['속삭임', '맹세', '이빨', '그림자', '약속', '비명', '파편', '등불', '발자국', '가시'];
/** 층(1~12, 보스는 'boss')별 등급 확률 [일반, 마법, 희귀, 전설] */
export function rarityTable(depth) {
  if (depth === 'boss') return [0, 0, 70, 30];
  return depth <= 3 ? [60, 35, 5, 0] : depth <= 6 ? [40, 45, 13, 2] : depth <= 9 ? [25, 45, 25, 5] : [15, 40, 35, 10];
}
export const GEAR_DROP = { default: 12, goblin_armor: 25, charger: 25 };

/** 장비의 슬롯 종류(반지는 ring1/ring2 어느 쪽이든) */
export const slotKind = (it) => GEAR_BASES[it.base].slot;
export const fitsSlot = (it, slot) => { const k = slotKind(it); return k === slot || (k === 'ring' && (slot === 'ring1' || slot === 'ring2')) || (slot === 'off' && k === 'weapon'); };
/** 무기 장비 → WPN 형태 수치(없으면 맨손 장검 취급) */
export function weaponOf(it) { const b = it && GEAR_BASES[it.base]; return b && b.weapon ? WPN(b.weapon) : WPN('sword'); }
export const weaponId = (it) => (it && GEAR_BASES[it.base].weapon) || 'sword';
export const isWeapon = (it) => !!(it && GEAR_BASES[it.base].weapon);
export function affixLine(a, known = true) {
  if (!known) return '???';
  const A = AFFIXES[a.id]; return A.line.replace('{v}', a.v).replace('{skill}', a.skill ? ({ push: '밀치기', fire: '불씨', bolt: '번개', frost: '냉기', venom: '독침' }[a.skill]) : '');
}
export const matName = (b) => MAT[GEAR_BASES[b].mat];
