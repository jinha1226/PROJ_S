# 3색 영혼석 이전 검토

2026-09-28 · `tools/migrate_soulstone_colours.py` 출력. 6개 피격 준비 효과를 준비 없이 직접 피격 발동으로 바꾼다.

| 효과 | 새 연산 | 새 문구 |
| --- | --- | --- |
| `fire_defense` | `burst` | 인접 피격 시 화염막 |
| `poison_defense` | `status` | 인접 피격 시 중독 |
| `bleed_defense` | `status` | 인접 피격 시 출혈 |
| `air_defense` | `status` | 피격 시 공격자 마비 · 재사용 3턴 |
| `hex_defense` | `status` | 피격 시 공격자 약화 |
| `reflect_defense` | `reflect` | 대기 후 피격 피해 30% 반사 |

## 아이콘 의미 확인

- 물·젖음은 전용 아이콘이 없어서 빙결, `water_air`는 감전을 쓴다. 물 효과의 고유 그림이 필요하면 12개 체계를 확장해야 한다.
- 밀치기(`wind`, `crush`)는 전용 아이콘이 없어서 추가 공격을 쓴다. 방어 준비형은 보호 아이콘을 쓴다.
- `death_wait`·`death_chain`은 실제 해골 소환이므로 저주 대신 소환 아이콘을 쓴다.
- `fire_defense`는 피격 지점 중심 화염막, `reflect_defense`는 실제 받은 피해를 반사한다. 회피·막기 때의 초록 발동을 이 여섯 효과에 자동 적용하지 않는다.

## 초기 색별 고정 보정

빨강 공격력 +4, 보라 공격력 +2·행동 속도 +5%, 초록 최대 HP +20·방어 +3. 이 수치는 전투 재측정 전의 임시값이다. 기존 `legacy` 역할 보정은 그대로다.
