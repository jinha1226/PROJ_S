/* ---------- 공격 형태 · 약점 ---------- */
export const FORMS = {
  slash: { name: '베기', icon: '⚔', injury: '출혈', part: '가죽', color: 'green' },
  blunt: { name: '타격', icon: '🔨', injury: '골절', part: '뼈', color: 'purple' },
  pierce: { name: '찌르기', icon: '🗡', injury: '급소', part: '심장', color: 'red' },
};

/* ================= 무기 12종 = 색 3 × 베기·타격·찌르기·원거리 (docs/설계_아이템_장비_데드셀안.md §3) =================
   color: 같은 색 영혼석 1개당 피해 +15% · hands: 1 | 2 · shape: 모양 · crit: 치명 조건(×2) · range: 원거리 사거리 · reload: 쏜 뒤 장전 턴 */
export const WEAPONS = {
  axe: { name: '손도끼', color: 'red', hands: 1, form: 'slash', dmg: [3, 5], shape: 'front', crit: 'bleeding' },
  flail: { name: '쇠사슬 도리깨', color: 'red', hands: 1, form: 'blunt', dmg: [2, 4], shape: 'fan', crit: 'crowd' },
  twin: { name: '쌍단검', color: 'red', hands: 2, form: 'pierce', dmg: [2, 3], shape: 'twin', crit: 'chain' },
  boomerang: { name: '부메랑', color: 'red', hands: 1, form: 'slash', dmg: [2, 4], shape: 'boomerang', crit: 'twice', range: 4 },
  greatsword: { name: '대검', color: 'purple', hands: 2, form: 'slash', dmg: [4, 6], shape: 'sweep', crit: 'waited' },
  hammer: { name: '전투 망치', color: 'purple', hands: 2, form: 'blunt', dmg: [5, 7], shape: 'smash', crit: 'slam' },
  spear: { name: '창', color: 'purple', hands: 1, form: 'pierce', dmg: [3, 5], shape: 'line2', crit: 'approach' },
  crossbow: { name: '석궁', color: 'purple', hands: 2, form: 'pierce', dmg: [5, 8], shape: 'bolt', crit: 'aimed', range: 7, reload: 1 },
  sword: { name: '장검', color: 'green', hands: 1, form: 'slash', dmg: [3, 5], shape: 'front', crit: 'riposte' },
  mace: { name: '철퇴', color: 'green', hands: 1, form: 'blunt', dmg: [3, 5], shape: 'front', crit: 'avenge', stun: 25 },
  rapier: { name: '레이피어', color: 'green', hands: 1, form: 'pierce', dmg: [2, 4], shape: 'front', crit: 'low', retreat: true },
  sling: { name: '투석구', color: 'green', hands: 1, form: 'blunt', dmg: [2, 4], shape: 'shot', crit: 'avenge', range: 4, knock: 1 },
};
export const WEAPON_IDS = Object.keys(WEAPONS);
/** 모양 한 줄 */
export const SHAPES = {
  front: '앞의 한 적',
  fan: '앞 넓은 부채꼴의 적 모두',
  twin: '한 적을 두 번 찌른다',
  boomerang: '4칸 날아갔다 돌아오며 길 위의 적을 모두 맞힌다',
  sweep: '바라보는 쪽 반원의 적 모두. 뒤는 비어 있다',
  smash: '한 적을 치고 1칸 밀친다',
  line2: '앞 직선 2.6칸, 줄지은 적을 꿰뚫는다',
  bolt: '7칸 직선을 꿰뚫는다',
  shot: '4칸까지 날아가 맞은 적을 1칸 밀친다',
};
/** 치명 조건 한 줄 */
export const CRITS = {
  bleeding: '출혈 중인 적',
  crowd: '한 번에 3명 이상 맞히면 전부',
  chain: '같은 적을 연속 턴에 공격하면',
  twice: '같은 적을 두 번 맞히면 두 번째',
  waited: '직전 턴에 대기했으면',
  slam: '밀쳐서 벽·다른 적에 부딪히면',
  approach: '이번 적 턴에 나에게 다가온 적',
  aimed: '장전을 대기로 했으면 다음 첫 발',
  riposte: '방금 막거나 피한 뒤 첫 공격',
  avenge: '나를 방금 때린 적',
  low: '내 HP가 절반 이하일 때',
};
/** 옛 무기 id → 새 무기 (단검 → 쌍단검) */
export const OLD_WEAPON = { dagger: 'twin' };

export function WPN(id) {
  const plus = id.endsWith('+'), k = plus ? id.slice(0, -1) : id, b = WEAPONS[OLD_WEAPON[k] || k];
  return plus ? { ...b, name: b.name + '+', dmg: [b.dmg[0] + 1, b.dmg[1] + 1], plus: true } : b;
}
