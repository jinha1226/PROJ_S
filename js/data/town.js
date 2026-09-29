export const JOBS = {
  keeper: { name: '제단지기', b: 'altar', work: 'tend' },
  blacksmith: { name: '대장장이', b: 'forge', work: 'hammer' },
  herbalist: { name: '약초꾼', b: 'herb', work: 'farm' },
  hunter: { name: '사냥꾼', b: 'hunter', work: 'carve' },
  scholar: { name: '학자', b: 'library', work: 'read' },
  cook: { name: '요리사', b: 'inn', work: 'stir' },
};

export const TRAITS = [['H', '정직·겸손'], ['E', '감정성'], ['X', '외향성'], ['A', '원만성'], ['C', '성실성'], ['O', '개방성']];

export const ADJ = { H: ['욕심 많은', '정직한'], E: ['담담한', '걱정 많은'], X: ['과묵한', '수다스러운'], A: ['까칠한', '너그러운'], C: ['게으른', '성실한'], O: ['고지식한', '호기심 많은'] };

export const adj = (n, k) => ADJ[k][n.t[k] > 0 ? 1 : 0];

export const NAMES = ['도윤', '서연', '하준', '지우', '민서', '예준', '수아', '시우', '하린', '지호', '유나', '건우', '채원', '이안', '소율', '태오', '나은', '로운', '다온', '미르', '보람', '한결'];

export const HERO_NAMES = ['아린', '로하', '세온', '미카', '단비', '해솔', '가람', '이든', '라온', '새봄'];

export const SKINS = [0xffd7b0, 0xf1c29a, 0xd9a47a, 0xb87a52];

export const HAIRS = [0x3a2618, 0x6a4020, 0xc89a4a, 0x2a2a30, 0xe0e0e0, 0xb04a2a];

export const JOB_CLOTH = { keeper: 0x8a7ab0, blacksmith: 0x6a5a4a, herbalist: 0x6aa04a, hunter: 0x8a6a3a, scholar: 0x5a4aa0, cook: 0xe0d8c8 };

export const MOODS = ['😠', '😟', '🙂', '😊', '😄'];

export const TALK = {
  X: { hi: ['오늘도 무사히 왔네! 얘기 좀 해 줘요!', '다들 모여 봐, 모험가가 왔어!'], lo: ['…왔군.', '(고개만 끄덕인다)'] },
  A: { hi: ['천천히 해요, 다 잘될 거예요.', '필요한 거 있으면 말해요.'], lo: ['또 빈손은 아니겠지?', '귀찮게 하지 마.'] },
  C: { hi: ['도구는 다 손봐 뒀어. 재료만 가져와.', '정해진 순서대로 하자고.'], lo: ['아, 내일 하면 안 돼?', '대충 해도 되잖아…'] },
  E: { hi: ['다친 데는 없죠? 정말 걱정했어요.', '밤새 잠을 못 잤어요…'], lo: ['살아 왔으면 됐지.', '겁낼 거 없어.'] },
  O: { hi: ['그 영혼석 색 좀 봐! 뜯어봐도 돼?', '새 조합을 시험해 보고 싶어.'], lo: ['하던 대로 하는 게 제일이야.', '이상한 건 들고 오지 마.'] },
  H: { hi: ['제 몫은 필요 없어요. 모두의 것이죠.', '솔직히 말할게요, 그건 위험해요.'], lo: ['그거 나 좀 주면 안 되나?', '내가 한 거라고 해 줘.'] },
};

export const WORKTALK = { hammer: ['땅! 땅!', '불 조절이 관건이지'], farm: ['잘 자라라~', '물 줄 시간이네'], carve: ['가죽은 결대로', '이 뼈 쓸 만하네'], read: ['흠, 흥미로운 기록이야', '이 문양은…'], stir: ['간은 딱 좋아', '배고픈 사람?'], tend: ['영혼석이 우는 소리가 나', '제단이 따뜻하네'] };

export const RECIPES = [
  { id: 'w_axe', b: 'forge', weapon: 'axe', in: { 가죽: 1, 뼈: 1, 광석: 2 } },
  { id: 'w_hammer', b: 'forge', weapon: 'hammer', in: { 뼈: 2, 광석: 2 } },
  { id: 'w_spear', b: 'forge', weapon: 'spear', in: { 심장: 1, 광석: 2 } },
  { id: 'a_leather', b: 'forge', armor: 'leather', in: { 가죽: 3 } },
  { id: 'a_bone', b: 'forge', armor: 'bone', in: { 뼈: 3, 광석: 1 }, hidden: true },
  { id: 'o_shield', b: 'forge', gear: 'shield', in: { 가죽: 2, 광석: 1 } },
  { id: 'o_torch', b: 'hunter', gear: 'torch', in: { 기름: 1, 뼈: 1 } },
  { id: 'i_ident', b: 'library', out: 'ident', n: 1, in: { 심장: 1, 약초: 1 } },
  { id: 'i_heal', b: 'herb', out: 'heal', n: 1, in: { 약초: 2 } },
  { id: 'i_cure', b: 'herb', out: 'cure', n: 1, in: { 약초: 1, 심장: 1 } },
  { id: 'i_haste', b: 'herb', out: 'haste', n: 1, in: { 심장: 1, 얼음: 1 }, hidden: true },
  { id: 'i_oil', b: 'hunter', out: 'oil', n: 2, in: { 기름: 1 } },
  { id: 'i_water', b: 'hunter', out: 'water', n: 2, in: { 가죽: 1 } },
  { id: 'i_smoke', b: 'hunter', out: 'smoke', n: 1, in: { 뼈: 1, 약초: 1 } },
  { id: 'i_recall', b: 'library', out: 'recall', n: 1, in: { 뼈: 1, 심장: 1 } },
  { id: 'i_tele', b: 'library', out: 'tele', n: 1, in: { 심장: 1, 뼈: 1, 약초: 1 } },
  { id: 'i_blaze', b: 'library', out: 'blaze', n: 1, in: { 기름: 1, 심장: 1 } },
  { id: 'i_fear', b: 'library', out: 'fear', n: 1, in: { 뼈: 2 }, hidden: true },
  { id: 'f_feast', b: 'inn', buff: 'feast', in: { 가죽: 1, 약초: 1 } },
  { id: 'f_stew', b: 'inn', out: 'heal', n: 2, in: { 약초: 1, 심장: 1 } },
];

export const BLD = {
  gate: { name: '출발문', icon: '🚪', x: 5, y: 1.3 },
  altar: { name: '영혼석 제단', icon: '💎', x: 2.2, y: 3.6 },
  storage: { name: '창고', icon: '📦', x: 7.9, y: 4.0 },
  plaza: { name: '모닥불', icon: '🔥', x: 5, y: 7 },
  forge: { name: '대장간', icon: '🔨', x: 2.2, y: 9.6 },
  herb: { name: '약초 공방', icon: '🌿', x: 7.9, y: 9.6 },
  hunter: { name: '사냥꾼 오두막', icon: '🏹', x: 2.2, y: 12.4 },
  inn: { name: '모닥불 식당', icon: '🍲', x: 5.2, y: 12.8 },
  library: { name: '서재', icon: '📜', x: 7.9, y: 12.4 },
};

export const CRAFT_B = ['forge', 'herb', 'hunter', 'library', 'inn'];

export const TW = 11, TH = 15;

export const TOWN_PAL = { floor: 0xdcc28e, floor2: 0xd2b682, wall: 0x4f9a45, wall2: 0x62ae52, void: 0x3f6a36, grassFloor: 0x7cc45a, waterFloor: 0x2a6ab0, dim: 1 };
