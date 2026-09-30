/* 행동 등록표: ACTS[kind] = { resolve(u, a), update?(u, a, dt) }. 의존 없는 모듈이라 어느 두뇌·스킬 모듈이 먼저 불려도 등록할 수 있다 (sim/action.js가 돌린다) */
export const ACTS = {};
/** 모듈 사이 고리(불러오는 순서와 상관없이): counter(e, src, mul) = 되치기 한 번 */
export const HOOKS = {};
