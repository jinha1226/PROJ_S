export const ROLES = {
  guardian: { name: '수호자', line: '앞에서 붙잡는다', color: '#75acdb', weapon: 'mace', skills: ['taunt', 'guard', 'slam'], unlock: 1 },
  fighter: { name: '검사', line: '틈을 베어 낸다', color: '#e5a679', weapon: 'sword', skills: ['cleave', 'dash', 'guard'], unlock: 1 },
  archer: { name: '궁수', line: '뒤에서 겨눈다', color: '#9ccc83', weapon: 'bow', skills: ['volley', 'dash', 'mark'], unlock: 1 },
  healer: { name: '치유사', line: '동료를 붙든다', color: '#edc77f', weapon: 'sling', skills: ['mend', 'cleanse', 'guard'], unlock: 2 },
  shaman: { name: '주술사', line: '물과 번개를 부른다', color: '#b19ce2', weapon: 'spear', skills: ['rain', 'storm', 'frost'], unlock: 2 },
};
export const SKILLS = {
  taunt: { name: '도발', line: '나를 보아라' }, guard: { name: '보호', line: '몸을 낮춘다' }, slam: { name: '강타', line: '앞을 부순다' },
  cleave: { name: '베어내기', line: '날이 돈다' }, dash: { name: '물러서기', line: '틈을 벌린다' }, volley: { name: '일제 사격', line: '화살이 쏟아진다' },
  mark: { name: '급소', line: '틈을 겨눈다' }, mend: { name: '치유', line: '상처를 감싼다' }, cleanse: { name: '정화', line: '독을 걷는다' },
  rain: { name: '비', line: '몸을 적신다' }, storm: { name: '번개', line: '물결에 빛이 번진다' }, frost: { name: '서리', line: '발을 붙잡는다' },
};
export const COMMANDS = { focus: '집중', spread: '흩어져', gather: '모여', retreat: '물러나', auto: '자동' };
