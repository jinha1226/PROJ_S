"""Export the authored arena mapping; it never invents bindings."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
content = json.loads((ROOT / 'data/content/essences.json').read_text())['rows']
rules = json.loads((ROOT / 'data/content/attack_wait_effects.json').read_text())
roles = {'OFFENSE': '공격형', 'DEFENSE': '방어형', 'CHAIN': '연쇄형'}
events = {'ATTACK':'공격 확정','HIT':'적중','WAIT':'대기','STRUCK':'피격','BLOCK':'막기','DODGE':'회피','KILL':'처치','MOVED':'이동','HEALED':'치유 성공','CLEANSED':'정화 성공','PUSHED':'밀침 성공','COLLISION':'벽 충돌','SUMMON':'소환 성공','SUMMON_END':'소환수 사망','PET_HIT':'소환수 적중','PET_KILL':'소환수 처치'}
lines = ['# 공격·대기 영혼석 — 실행 매핑', '', '2026-09-27 · `attack_wait_v1` · 전투 시험에서 선택 가능', '',
'시작 화면 → 전투 시험 → **공격·대기 영혼석**. 인물마다 0~6개를 선택하고 시작한다. 새 에셋 없이 기존 그림과 VFX를 사용한다. 일반 원정과 기존 전투 시험은 `legacy`이며 기본값을 바꾸지 않았다. 영혼석 고정 보상은 새 프로필로 매핑했으며 원정 적용은 모바일 플레이 확인 및 MP 관련 장비·아이템 매핑 뒤 진행한다.', '',
'주인공은 이동·공격·대기를 직접 선택한다. 공격의 접근 이동은 발동하지 않으며, 의도적 대기만 대기 효과를 만든다. 영혼석 효과는 MP와 추가 행동을 소비하지 않는다. 상태 부여를 먼저 처리한 뒤 연쇄를 판정하며, 추가타는 다시 기본 적중을 발행하지 않는다. 효과별 행동당 한도와 비상 큐 한도를 구분한다.', '',
'원소 연결은 해당 영혼석이 있을 때만 실행한다. 전하 공격에는 명시적 전기 피해 2가 포함되어 물+전기 연결을 활성화한다. 상태 갱신이 없어도 실제 피해가 발생하면 발동·기여·표시를 기록한다. 상태 변화와 피해가 모두 없으면 기록하지 않는다. 물/지형의 젖음과 기존 환경 갱신은 유지하지만 새 효과는 기존 자동 독성 폭발·파쇄·지형 방전을 동시에 실행하지 않는다. 몬스터의 기존 대표 효과는 기존 반응 정책이다.', '',
'대기 방어는 다음 합법적인 자기 행동까지 유지한다. 피격 준비는 유효 직접 피격에 1회 시도하고 확률 실패에도 소비한다. 자세 감소는 중첩하지 않는다. 빙결·기절 재적용은 정상 행동 기회를 얻기 전까지 막는다. 새 규칙에서 부여한 혼란은 물리 공격 명중을 20%p 낮추며 진영과 행동 횟수를 바꾸지 않는다. 위협은 이미 보이는 대상의 다음 선택 점수만 보정한다.', '',
'치유는 부상한 실제 아군 중 가장 낮은 HP 비율을 선택하며 강한 대기 치유는 70% 이하·조우당 2회·재사용 3턴이다. 동일 적의 시야 이탈로 횟수가 복원되지 않는다. 소환은 공용 한도 1명·빈 인접 칸·재사용 3턴을 사용한다. 호위는 실제 피해 대신 받기 경로를 사용하며 자연 만료는 사망 연쇄를 만들지 않는다.', '',
'공격/대기 아이콘, 준비·위협·조준·치유 잔여 횟수, 흡수한 효과 요약과 상세 조건은 같은 실행 데이터를 읽는다. 새 프로필에서 MP·수동 주문 바는 기본 HUD에 표시하지 않는다. NPC Utility AI는 효과의 예상 가치를 읽고 소환수 목표 집중은 다음 정상 행동에 적용한다. 확률 예측에서 RNG와 상태를 변경하지 않는다.', '',
'수치는 초기 시험값이다. 테스트 통과는 모바일 재미·층 전체 밸런스 검증을 의미하지 않는다. 원정 기본값 전환과 MP 관련 전리품/장비 재배치는 아직 적용하지 않았다.', '',
'## 부위별 효과', '', '이 표는 `data/content/attack_wait_effects.json`에서 내보낸다. 같은 영혼석이 역할 세 개를 모두 주지 않는다. 한 행이 실제 효과 하나이며 계열은 피해 타입 추가를 뜻하지 않는다.', '',
'| 부위 ID | 이름 | 역할 | 계열 | 사건 | 효과 | 재사용/횟수 |', '| --- | --- | --- | --- | --- | --- | --- |']
rows = []
reward_names = {'SUPPORT':'서포터','MELEE':'근접 딜러','TANK':'탱커','RANGED':'원거리 딜러','MAGIC':'캐스터'}
stat_names = {'atk':'공격력','hp':'최대 HP','ac':'방어','speed':'행동 속도'}
reward_lines = ['## 영혼석 고정 보상', '', '새 프로필의 인물·동료·NPC에게 같은 표를 적용한다. 변형 영혼석의 기존 속성 저항은 유지한다. 보상에 MP와 주문력을 추가하지 않으며 능력치 계산·흡수 전 상세·효과 요약이 같은 표를 읽는다. 드롭·영구 흡수·교체 제한은 변경하지 않는다. 장비·소모품의 MP 매핑과 원정 기본값 전환은 별도 단계다.', '', '| 역할 | 고정 보상 |', '| --- | --- |']
for role, stats in rules['role_stats'].items():
    text = ' · '.join(f'{stat_names[key]} +{amount}{"%" if key == "speed" else ""}' for key, amount in stats.items())
    reward_lines.append(f'| {reward_names[role]} | {text} |')
at = lines.index('## 부위별 효과')
lines[at:at] = reward_lines + ['']
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
lines += ['', '## 검증', '', '`tests/attack_wait.gd`는 전체 효과 매핑과 부여→연쇄 순서, 면역, 벽·거리, 의도/강제 대기, 방어 준비, 재봉쇄, 마지막 적 처치·지속 피해 귀속, 치유 횟수, 소환·호위·집중, 봉인과 예측 순수성을 검사한다. 고정 보상은 실제 흡수·HP·공격력·프로필 전환·NPC 적용까지 확인하며 전하가 갱신되지 않은 전기 피해의 발동·기여·표시와 행동당 한도를 검사한다. `tests/attack_wait_ui.gd`는 프로필 선택·6칸·요약·흡수 전 보상·MP/기술 바 표시와 320×568 / 390×844 / 430×932 배치를 검사한다. 두 검사는 GitHub Actions에 포함한다.', '', '2026-09-27 보상·발동 기록 수정 검증: 관련 12개 검사 묶음, 총 2,164항목 통과(신규 규칙 414항목·UI 19항목 포함). Web 내보내기, 배포 파일 단독 시작, 같은 배포 파일의 새 보상·매핑·3인 아레나·시간 진행을 확인했다. 사람의 모바일 플레이와 원정 누적 밸런스는 이 검사에 포함하지 않는다.', '', '원인 행동/부모 이벤트/주체/규칙/대상 기록은 `session.aw_trace`, 비상 한도 발생은 `aw_overflows`, 기존 효과 기여 집계는 `battle_stats.members`에서 확인한다. 로그는 전투 결과 문장을 유지하며 발동 설명 팝업은 추가하지 않았다.', '']
(ROOT / 'docs/attack-wait-soulstones.ko.md').write_text('\n'.join(lines))
print(f'{len(rows)} authored concrete mappings; {len(rules["effects"])} effects')
