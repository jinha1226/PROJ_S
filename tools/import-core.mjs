// Copy only the dependency closure of the selected SS components.
import fs from 'node:fs';
import path from 'node:path';
const source = '/mnt/d/SS';
const target = process.cwd();
const pending = [
  'sim/turn_engine.gd', 'sim/environment_rules.gd',
  'sim/dungeon_population/hexaco_profile.gd', 'sim/party_memory_state.gd',
  'game/rebuilt/body_bridge.gd',
  'assets/fonts/NanumSquareR.ttf', 'assets/fonts/NanumSquareR.LICENSE.txt',
];
const copied = new Set();
while (pending.length) {
  const relative = pending.pop();
  if (copied.has(relative)) continue;
  if (relative.includes('..')) throw Error(relative);
  const origin = path.join(source, relative);
  const destination = path.join(target, relative);
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  fs.copyFileSync(origin, destination);
  copied.add(relative);
  if (!relative.endsWith('.gd')) continue;
  const text = fs.readFileSync(origin, 'utf8');
  for (const match of text.matchAll(/res:\/\/([^"\s]+\.(?:gd|json))/g)) pending.push(match[1]);
}
console.log(`Imported ${copied.size} original files.`);
