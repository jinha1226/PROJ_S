// 시작 · 모듈 연결. 규칙(core)과 화면(render/ui/town)은 여기서만 이어진다.
import { playerMove, playerWait } from './core/combat.js';
import { computeFOV } from './core/fov.js';
import { takeWeapon, useItem } from './core/items.js';
import { META, newHero } from './core/meta.js';
import { newRun } from './core/run.js';
import { useSkill } from './core/skills.js';
import { G, Game, TL, setListener } from './core/state.js';
import { addStone } from './core/stones.js';
import { DROPS } from './data/enemies.js';
import { STONE } from './data/stones.js';
import { RECIPES } from './data/town.js';
import { Anim, act, descend, enterDungeon, returnToTown } from './flow.js';
import { ports } from './render/ports.js';
import { Sfx } from './render/sfx.js';
import { View } from './render/view.js';
import { Town } from './town/town.js';
import { $, UI } from './ui/ui.js';
import './render/fx.js';
import './ui/input.js';
import './ui/hud.js';
import './ui/panels.js';
import './ui/screens.js';
import './town/town-ui.js';

setListener((type, data) => View.on(type, data));
Object.assign(ports, { UI, Town, Anim });

/* ================= 시작 ================= */
View.init();
UI.init();
for (const b of document.querySelectorAll('#tbtns button')) b.onclick = () => { if (Town.busy) return; const o = b.dataset.o; if (o === 'craft') Town.craft(); else Town.open(o); };
$('#btn-help2').onclick = () => UI.help(true);
$('#btn-sound2').onclick = () => { Sfx.on = !Sfx.on; $('#btn-sound2').textContent = $('#btn-sound').textContent = Sfx.on ? '🔊' : '🔇'; };
newRun();
View.buildFloor();
UI.syncAll();
UI.title();
window.__game = { get META() { return META; }, Town, Game, enterDungeon, returnToTown, newHero, RECIPES, G, UI, View, act, playerMove, useSkill, useItem, descend, TL, Anim, computeFOV, playerWait, addStone, takeWeapon, STONE, DROPS };
