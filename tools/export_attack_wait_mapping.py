"""Refresh the authored effect table, preserving the current design and verification prose."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
content = json.loads((ROOT / 'data/content/essences.json').read_text())['rows']
rules = json.loads((ROOT / 'data/content/attack_wait_effects.json').read_text())
roles = {'OFFENSE': '공격형', 'DEFENSE': '방어형', 'CHAIN': '연쇄형'}
events = {'ATTACK':'공격 확정','HIT':'적중','WAIT':'대기','STRUCK':'피격'}
document = ROOT / 'docs/attack-wait-soulstones.ko.md'
existing = document.read_text()
intro, table = existing.split('## 부위별 효과', 1)
_, verification = table.split('## 검증', 1)
lines = [intro.rstrip(), '', '## 부위별 효과', '',
'이 표는 `data/content/attack_wait_effects.json`에서 내보낸다. 한 행이 실제 효과 하나이며 계열은 피해 타입 추가를 뜻하지 않는다.', '',
'| 부위 ID | 이름 | 역할 | 계열 | 사건 | 효과 | 재사용/횟수 |', '| --- | --- | --- | --- | --- | --- | --- |']
rows = []
for base, entry in content.items():
    for part, definition in entry.get('parts', {'': entry}).items():
        sid = base + ('/' + part if part else '')
        legacy = definition.get('effect', base)
        if not legacy: legacy = base
        eid = rules['bindings'].get(legacy, rules['bindings'].get(base))
        assert eid in rules['effects'], sid
        rows.append((sid, definition.get('name', entry.get('name', base)), eid))
        for element, mapping in rules['variants'].items():
            if legacy in mapping:
                rows.append((sid + '@' + element, definition.get('name', base) + ' · ' + element, mapping[legacy]))
for sid, name, eid in rows:
    r = rules['effects'][eid]
    limits = []
    if 'cooldown' in r: limits.append(f'{r["cooldown"]/100:g}턴')
    if 'uses' in r: limits.append(f'조우당 {r["uses"]}회')
    if 'cap' in r: limits.append(f'소환 {r["cap"]}명' if r['op'] == 'summon' else f'최대 {r["cap"]}')
    lines.append(f'| `{sid}` | {name} | {roles[r["role"]]} | {r["family"]} | {events[r["event"]]} | {r["text"]} | {" · ".join(limits) or "—"} |')
lines += ['', '## 검증' + verification]
document.write_text('\n'.join(lines))
print(f'{len(rows)} authored concrete mappings; {len(rules["effects"])} effects')
