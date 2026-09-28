export const SKILLS = [
  { id: 'push', name: '밀치기', icon: '✋', cd: 3, range: 1, color: 0xf2e6c8, css: '#f2e6c8', needsEnemy: true,
    desc: '인접한 적을 2칸 밀친다. 벽에 박으면 4 피해 + 기절, 다른 적과 부딪히면 둘 다 3 피해. 얼음 위에서는 끝까지 미끄러진다.' },
  { id: 'fire', name: '불씨', icon: '🔥', cd: 5, range: 5, color: 0xff7a1a, css: '#ff8a2a',
    desc: '4 화염 + 화상. 풀은 번지고 기름은 폭발한다. 빙결된 적은 녹아 증기 폭발(+4), 중독된 적은 독 폭발, 젖은 적은 절반.' },
  { id: 'bolt', name: '번개', icon: '⚡', cd: 5, range: 5, color: 0xffe14a, css: '#ffe14a',
    desc: '5 번개. 물이나 젖은 대상에 맞으면 이어진 물·젖은 대상 전체가 감전된다(+2, 기절). 물에 서 있는 나도 맞는다.' },
  { id: 'frost', name: '냉기', icon: '❄', cd: 6, range: 4, color: 0x8fdcff, css: '#8fdcff',
    desc: '2 피해 + 빙결 2턴(젖었으면 5턴). 십자 범위의 물을 얼음으로 바꾼다. 빙결된 적은 물리 공격에 1.5배.' },
  { id: 'venom', name: '독침', icon: '☠', cd: 4, range: 5, color: 0x79e05a, css: '#79e05a',
    desc: '중독 6턴(매 턴 1). 중독된 적에게 불이 닿으면 독 폭발 — 주변에 3 피해, 옆의 중독된 적도 연쇄 폭발.' },
];

export const SK = Object.fromEntries(SKILLS.map((s) => [s.id, s]));
