export const COLORS = {
  red: { name: '빨강', trig: '내 공격이 적중할 때', hex: 0xff4a5a, css: '#ff5a6a' },
  purple: { name: '보라', trig: '대기할 때', hex: 0xb45aff, css: '#c27dff' },
  green: { name: '초록', trig: '적에게 맞을 때', hex: 0x4ad86a, css: '#62e27a' },
};

/** 영혼석 = 액티브 스킬 하나 (docs/설계_영혼석_스킬.md §3)
 *  cd: 기본 쿨타임 · tgt: adj(붙은 적) | tile(r칸 지점) | line(r칸 직선) | empty(붙은 빈칸) | area(r칸 지점, 반경 rad) | self | around(나 주변 1칸) | sight(시야)
 *  elem: 숨은 방을 여는 원소(fire·frost·bolt·push) · ← 표시는 옛 스킬을 이어받은 것 */
export const STONE = {
  r_bleed: { color: 'red', icon: '🩸', name: '피 내기', cd: 4, tgt: { t: 'adj' }, line: '붙은 적에게 무기 공격 + 출혈 5 (해골 제외)' },
  r_extra: { color: 'red', icon: '✦', name: '연속 베기', cd: 4, tgt: { t: 'adj' }, line: '붙은 적에게 무기 공격 2번. 두 번째는 출혈 중이면 +2' },
  r_poison: { color: 'red', icon: '☠', name: '독침', cd: 4, tgt: { t: 'tile', r: 5 }, line: '중독 6턴(매 턴 1). 중독된 적에 불이 닿으면 독 폭발' },
  r_push: { color: 'red', icon: '✋', name: '밀치기', cd: 3, tgt: { t: 'adj' }, elem: 'push', line: '2칸 밀친다. 벽에 박으면 4 피해 + 기절, 적끼리 부딪히면 둘 다 3' },
  r_arrow: { color: 'red', icon: '🏹', name: '뼈 화살', cd: 3, tgt: { t: 'line', r: 6 }, line: '6칸 직선으로 4 피해, 2명까지 관통' },
  r_shock: { color: 'red', icon: '⚡', name: '번개', cd: 5, tgt: { t: 'tile', r: 5 }, elem: 'bolt', line: '5 번개. 물·젖은 대상이면 이어진 곳 전체 감전(+2, 기절)' },
  r_fire: { color: 'red', icon: '🔥', name: '불씨', cd: 5, tgt: { t: 'tile', r: 5 }, elem: 'fire', line: '4 화염 + 화상. 풀 번짐, 기름 폭발, 빙결 증기 폭발, 중독 독 폭발' },
  r_freeze: { color: 'red', icon: '❄', name: '냉기', cd: 6, tgt: { t: 'tile', r: 4 }, elem: 'frost', line: '2 피해 + 빙결 2턴(젖었으면 5턴). 십자 범위 물을 얼음으로' },
  p_summon: { color: 'purple', icon: '👻', name: '영혼 고블린', cd: 6, tgt: { t: 'empty' }, line: '붙은 빈칸에 영혼 고블린 소환 4턴 (동시에 최대 2)' },
  p_shield: { color: 'purple', icon: '🛡', name: '보호막', cd: 5, tgt: { t: 'self' }, line: '보호막 +6 (최대 10)' },
  p_poison: { color: 'purple', icon: '☠', name: '독 안개', cd: 5, tgt: { t: 'around' }, line: '붙은 적 모두 중독 4, 주변에 독 안개' },
  p_push: { color: 'purple', icon: '💥', name: '충격파', cd: 5, tgt: { t: 'around' }, elem: 'push', line: '붙은 적 모두 2칸 밀친다 (벽 충돌 규칙 동일)' },
  p_heal: { color: 'purple', icon: '❤', name: '숨 고르기', cd: 6, tgt: { t: 'self' }, line: 'HP 6 회복 + 중독·화상 해제' },
  p_shock: { color: 'purple', icon: '🌩', name: '폭풍', cd: 6, tgt: { t: 'sight' }, elem: 'bolt', line: '보이는 젖은 적 모두 번개 4 (전도 규칙 동일)' },
  p_fire: { color: 'purple', icon: '🔥', name: '불길', cd: 6, tgt: { t: 'area', r: 4, rad: 1 }, elem: 'fire', line: '4칸 안 지점 3×3에 불 3 + 화상, 풀이면 번짐' },
  p_wet: { color: 'purple', icon: '💧', name: '물벼락', cd: 4, tgt: { t: 'area', r: 4, rad: 2 }, line: '4칸 안 지점 반경 2: 적 모두 젖고, 바닥에 물웅덩이' },
  g_counter: { color: 'green', icon: '⚔', name: '반격 자세', cd: 4, tgt: { t: 'self' }, aura: 'counter', rounds: 1, line: '다음 적 턴 동안 붙은 공격자에게 맞을 때마다 무기 반격' },
  g_shield: { color: 'green', icon: '🛡', name: '막기', cd: 4, tgt: { t: 'self' }, aura: 'guard', rounds: 1, line: '다음 적 턴 받는 피해 절반 + 보호막 3' },
  g_poison: { color: 'green', icon: '🌵', name: '독 가시', cd: 5, tgt: { t: 'self' }, aura: 'thorn', rounds: 3, line: '3라운드 동안 나를 때린 적 중독 3' },
  g_push: { color: 'green', icon: '✋', name: '밀쳐내기', cd: 3, tgt: { t: 'adj' }, elem: 'push', line: '붙은 적을 3칸 밀치고 기절 1턴 (벽 충돌 규칙 동일)' },
  g_heal: { color: 'green', icon: '🩹', name: '상처 봉합', cd: 6, tgt: { t: 'self' }, line: '이번 전투에서 받은 피해의 절반 회복 (최대 8)' },
  g_shock: { color: 'green', icon: '⚡', name: '번개 갑주', cd: 5, tgt: { t: 'self' }, aura: 'storm', rounds: 3, line: '3라운드 동안 나를 때린 적에게 번개 3 (젖었으면 번짐)' },
  g_fire: { color: 'green', icon: '🔥', name: '불꽃 방출', cd: 4, tgt: { t: 'around' }, elem: 'fire', line: '붙은 적 모두 불 3 + 화상' },
  g_freeze: { color: 'green', icon: '❄', name: '서리 갑주', cd: 6, tgt: { t: 'self' }, aura: 'frost', rounds: 3, line: '3라운드 동안 나를 때린 적 빙결 1턴 (젖었으면 3턴)' },
};

/** 지속 효과(오라) 이름 · 색 */
export const AURA = { counter: { name: '반격 자세', hex: 0xff5a4a }, guard: { name: '막기', hex: 0x9fd8ff }, thorn: { name: '독 가시', hex: 0x79e05a }, storm: { name: '번개 갑주', hex: 0xffe14a }, frost: { name: '서리 갑주', hex: 0x8fdcff } };

/** 레벨 = 열린 영혼석 칸 수(1~6). 경험치 = 쓰러뜨린 적의 최대 HP 합(보스 두 배) — docs/밸런스_기준.md §1.1 */
export const LEVEL_XP = [0, 15, 45, 100, 180, 300];
export const levelOf = (xp) => { let l = 1; while (l < LEVEL_XP.length && xp >= LEVEL_XP[l]) l++; return l; };
