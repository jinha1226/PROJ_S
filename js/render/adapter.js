export const ADAPTER_METHODS=['mount','resize','setDungeon','setTown','frame','onEvents','setFrozen','pick'];
export function validateAdapter(renderer) {
  for(const method of ADAPTER_METHODS)if(typeof renderer[method]!=='function')throw new Error(`Missing renderer method: ${method}`);
  return renderer;
}
