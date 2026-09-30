export const COLORS = {
  red: { name: '빨강', trig: '내 공격이 적중할 때', hex: 0xff4a5a, css: '#ff5a6a' },
  purple: { name: '보라', trig: '대기할 때', hex: 0xb45aff, css: '#c27dff' },
  green: { name: '초록', trig: '적에게 맞을 때', hex: 0x4ad86a, css: '#62e27a' },
};

/** 영혼석 = 액티브 스킬 하나 (docs/설계_영혼석_스킬.md §3)
 *  cd: 기본 쿨타임 · tgt: adj(붙은 적) | tile(r칸 지점) | line(r칸 직선) | empty(붙은 빈칸) | area(r칸 지점, 반경 rad) | self | around(나 주변 1칸) | sight(시야)
 *  elem: 숨은 방을 여는 원소(fire·frost·bolt·push) · ← 표시는 옛 스킬을 이어받은 것 */
export const STONE = {
  r_bleed: { color: 'red', icon: '🩸', name: '피 내기', cd: 4, tgt: { t: 'adj' }, line: '붙은 적을 무기로 치고 출혈 5를 입힌다. 해골은 피를 흘리지 않는다.' },
  r_extra: { color: 'red', icon: '✦', name: '연속 베기', cd: 4, tgt: { t: 'adj' }, line: '붙은 적을 무기로 두 번 친다. 두 번째는 출혈 중인 적에게 피해가 2 는다.' },
  r_poison: { color: 'red', icon: '☠', name: '독침', cd: 4, tgt: { t: 'tile', r: 5 }, line: '6턴 동안 매 턴 독 1. 중독된 적에게 불이 닿으면 독이 터진다.' },
  r_push: { color: 'red', icon: '✋', name: '밀치기', cd: 3, tgt: { t: 'adj' }, elem: 'push', line: '붙은 적을 2칸 밀친다. 벽에 박히면 피해 4와 기절, 다른 적과 부딪히면 둘 다 피해 3.' },
  r_arrow: { color: 'red', icon: '🏹', name: '뼈 화살', cd: 3, tgt: { t: 'line', r: 6 }, line: '6칸 직선으로 쏴 피해 4. 둘까지 꿰뚫는다.' },
  r_shock: { color: 'red', icon: '⚡', name: '번개', cd: 5, tgt: { t: 'tile', r: 5 }, elem: 'bolt', line: '번개 5. 젖은 적과 물을 타고 번진다.' },
  r_fire: { color: 'red', icon: '🔥', name: '불씨', cd: 5, tgt: { t: 'tile', r: 5 }, elem: 'fire', line: '불 4, 화상. 풀과 기름에 불이 붙는다.' },
  r_freeze: { color: 'red', icon: '❄', name: '냉기', cd: 6, tgt: { t: 'tile', r: 4 }, elem: 'frost', line: '냉기 2, 2턴 얼린다. 젖은 적은 더 오래.' },
  p_summon: { color: 'purple', icon: '👻', name: '영혼 고블린', cd: 6, tgt: { t: 'empty' }, line: '붙은 빈칸에 영혼 고블린을 4턴 부른다. 한 번에 둘까지.' },
  p_shield: { color: 'purple', icon: '🛡', name: '보호막', cd: 5, tgt: { t: 'self' }, line: '보호막 6을 두른다. 10까지 쌓인다.' },
  p_poison: { color: 'purple', icon: '☠', name: '독 안개', cd: 5, tgt: { t: 'around' }, line: '붙은 적 모두 중독 4. 주변에 독 안개가 퍼진다.' },
  p_push: { color: 'purple', icon: '💥', name: '충격파', cd: 5, tgt: { t: 'around' }, elem: 'push', line: '붙은 적을 모두 2칸 밀친다. 벽에 박힌 적은 기절한다.' },
  p_heal: { color: 'purple', icon: '❤', name: '숨 고르기', cd: 6, tgt: { t: 'self' }, line: 'HP 6을 회복하고 중독과 화상을 없앤다.' },
  p_shock: { color: 'purple', icon: '🌩', name: '폭풍', cd: 6, tgt: { t: 'sight' }, elem: 'bolt', line: '보이는 젖은 적 모두에게 번개 4. 물을 타고 번진다.' },
  p_fire: { color: 'purple', icon: '🔥', name: '불길', cd: 6, tgt: { t: 'area', r: 4, rad: 1 }, elem: 'fire', line: '4칸 안의 한 곳과 그 둘레에 불 3, 화상. 풀이 있으면 번진다.' },
  p_wet: { color: 'purple', icon: '💧', name: '물벼락', cd: 4, tgt: { t: 'area', r: 4, rad: 2 }, line: '4칸 안의 한 곳을 중심으로 물을 쏟는다. 닿은 적은 젖는다.' },
  g_counter: { color: 'green', icon: '⚔', name: '반격 자세', cd: 4, tgt: { t: 'self' }, aura: 'counter', rounds: 1, line: '다음 적 턴 동안 붙어서 때린 적에게 매번 무기로 반격한다.' },
  g_shield: { color: 'green', icon: '🛡', name: '막기', cd: 4, tgt: { t: 'self' }, aura: 'guard', rounds: 1, line: '다음 적 턴에 받는 피해가 절반이 되고, 보호막 3을 두른다.' },
  g_poison: { color: 'green', icon: '🌵', name: '독 가시', cd: 5, tgt: { t: 'self' }, aura: 'thorn', rounds: 3, line: '3라운드 동안 나를 때린 적은 중독 3.' },
  g_push: { color: 'green', icon: '✋', name: '밀쳐내기', cd: 3, tgt: { t: 'adj' }, elem: 'push', line: '붙은 적을 3칸 밀쳐 한 턴 기절시킨다.' },
  g_heal: { color: 'green', icon: '🩹', name: '상처 봉합', cd: 6, tgt: { t: 'self' }, line: '이번 전투에서 받은 피해의 절반을 회복한다. 한 번에 HP 8까지.' },
  g_shock: { color: 'green', icon: '⚡', name: '번개 갑주', cd: 5, tgt: { t: 'self' }, aura: 'storm', rounds: 3, line: '3라운드 동안 나를 때린 적에게 번개 3. 젖은 적이면 번진다.' },
  g_fire: { color: 'green', icon: '🔥', name: '불꽃 방출', cd: 4, tgt: { t: 'around' }, elem: 'fire', line: '붙은 적 모두에게 불 3, 화상.' },
  g_freeze: { color: 'green', icon: '❄', name: '서리 갑주', cd: 6, tgt: { t: 'self' }, aura: 'frost', rounds: 3, line: '3라운드 동안 나를 때린 적을 한 턴 얼린다. 젖은 적은 3턴.' },
};

/** 보랏빛 오브(데드셀안 §4.1): 보라 스킬마다 정해진 +1 (오브 강화 +N이면 +1+N) */
export const ORB_PURPLE = { p_summon: '소환 지속 +1턴', p_shield: '보호막 +2', p_poison: '중독 +1턴', p_push: '밀치기 +1칸', p_heal: '회복 +2', p_shock: '번개 +1', p_fire: '불길 범위 +1칸', p_wet: '물벼락 범위 +1칸' };

/** 지속 효과(오라) 이름 · 색 */
export const AURA = { counter: { name: '반격 자세', hex: 0xff5a4a }, guard: { name: '막기', hex: 0x9fd8ff }, thorn: { name: '독 가시', hex: 0x79e05a }, storm: { name: '번개 갑주', hex: 0xffe14a }, frost: { name: '서리 갑주', hex: 0x8fdcff } };

/** 레벨 = 열린 영혼석 칸 수(1~6). 경험치 = 쓰러뜨린 적의 최대 HP 합(보스 두 배) — docs/밸런스_기준.md §1.1 */
export const LEVEL_XP = [0, 15, 45, 100, 180, 300];
export const levelOf = (xp) => { let l = 1; while (l < LEVEL_XP.length && xp >= LEVEL_XP[l]) l++; return l; };
