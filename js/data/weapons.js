/* ---------- 2차: 공격 형태 · 약점 · 영혼석 ---------- */
export const FORMS = {
  slash: { name: '베기', icon: '⚔', injury: '출혈', part: '가죽', color: 'green' },
  blunt: { name: '타격', icon: '🔨', injury: '골절', part: '뼈', color: 'purple' },
  pierce: { name: '찌르기', icon: '🗡', injury: '급소', part: '심장', color: 'red' },
};

export const WEAPONS = {
  sword: { name: '장검', form: 'slash', dmg: [3, 5] },
  axe: { name: '손도끼', form: 'slash', dmg: [4, 6] },
  mace: { name: '철퇴', form: 'blunt', dmg: [3, 5] },
  hammer: { name: '전투 망치', form: 'blunt', dmg: [4, 6] },
  dagger: { name: '단검', form: 'pierce', dmg: [2, 4] },
  spear: { name: '창', form: 'pierce', dmg: [3, 5] },
};

export function WPN(id) {
  const plus = id.endsWith('+'), b = WEAPONS[plus ? id.slice(0, -1) : id];
  return plus ? { ...b, name: b.name + '+', dmg: [b.dmg[0] + 1, b.dmg[1] + 1], plus: true } : b;
}

export const ARMORS = {
  leather: { name: '가죽 갑옷', maxHp: 6, desc: '최대 HP +6' }, 'leather+': { name: '가죽 갑옷+', maxHp: 9, desc: '최대 HP +9' },
  bone: { name: '뼈 흉갑', shield: 4, desc: '층마다 보호막 4로 시작' }, 'bone+': { name: '뼈 흉갑+', shield: 6, desc: '층마다 보호막 6으로 시작' },
};
