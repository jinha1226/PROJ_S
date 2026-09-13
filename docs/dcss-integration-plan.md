# DCSS 밸런스 도입 — 원본 확인과 구현 범위

2026-09-13. 사용자 선택: DCSS. 현재 코드 기준: `b0d60ac`.
거점·반복 원정은 현재 게임 방향에서 제외한다. 기존 정착지 기능을 다시 활성화하지 않는다.

## 고정한 원본

- 공식 저장소: https://github.com/crawl/crawl
- 안정판: 0.34.1, release https://github.com/crawl/crawl/releases/tag/0.34.1
- commit: `1eebc1a2892e1c89776a0d7a10691f8dac8d9796` (공식 tree API로 확인).
- LICENSE: https://github.com/crawl/crawl/blob/0.34.1/LICENSE
- 원본 소스는 분석을 위해 /tmp/dcss-0.34.1에 받았다. 게임 저장소에는 원본 코드·데이터를 반입하지 않았다.

## 실제 코드 연결 지점

| 영역 | 기존 경로 | 도입 시 확인할 계약 |
|---|---|---|
| 능력치 | sim/actor_stat_rules.gd, data/content/species_catalog.json | STR/DEX/INT의 역할·초기값·숙련도 관계 |
| 무기 | data/content/weapons.json, sim/weapon_attack_rules.gd | 기본 피해·명중·공격 지연·숙련도, 현재 피해에 더해지는 actor power 제거/변환 여부 |
| 방어 | sim/turn_engine.gd, sim/combat_defense_rules.gd | 고정 피해 차감과 milli 명중률을 DCSS AC/EV 판정으로 연결 |
| 몬스터 | sim/combat_profile_registry.gd, sim/dungeon_population | HP/HD/AC/EV/공격·속도·특수 행동과 층별 출현 |
| 아이템 | data/content/item_catalog.json | 장비·강화·미식별 소비품·회복 공급과 성장 곡선 |
| 별도 데모 | game/rebuilt/equipment.gd, game/rebuilt/world.gd | 제품 기본 진입과 별도 --rebuilt-demo를 혼동하지 않기 |

제품 기본 진입은 playtest/entry_router.tscn → party_encounter_sandbox.tscn이다.
제품 정착지는 playtest/product_features.gd의 SETTLEMENT_ENABLED=false다.
DCSS와 현재 엔진의 피해·명중 단위가 달라 수치만 교체해서는 원작 밸런스를 재현하지 못한다.

## 사용자 정정 — 밸런스만 적용

사용자는 코드 이식을 명시적으로 제외했다. 아래의 원본 이식/GPL 방향 확정 항목은 철회한다. 전투 공식·AI·부상 엔진은 기존 구현을 사용하며, DCSS의 수치와 역할 관계를 현재 단위로 변환한다. 코드·원본 데이터 파일을 반입하거나 저장소 라이선스를 변경하지 않는다.

## 최초 제안 구현 순서와 검증 (아래 사용자 정정 우선)

1. 능력치·숙련도·명중/피해·AC/EV·공격 지연의 최소 규칙 묶음을 함께 도입한다.
2. 현재 무기와 대응되는 초반 무기/방어구 및 고블린·코볼트·애더·오크를 연결한다.
3. 원본 판정의 알려진 입력/출력과 분포를 검증하고, 실제 제품 시작·전투·드롭·장비·저장/재생을 검증한다.
4. 유지할 신체/성격/동료 규칙의 차이를 명시하고 우리 게임에 맞춰 조정한다.

원본 전체의 신·분기·마법·모든 몬스터를 이 단계에 구현한 것으로 간주하지 않는다.
구현 전에 원본 이식 또는 규칙 분석 후 기존 코드 구현 중 사용자가 원하는 방식을 확정한다.
원본 코드를 다른 언어로 번역하는 것도 독립 구현으로 취급하지 않는다.

## 현재 완료와 미완료

완료: 현재 진입/기능 상태 확인, 공식 안정판 및 commit 고정, 원본 라이선스·전투 소스 확인, 연결 지점과 검증 범위 기록.
미완료: 원본 코드/데이터 반입, 전투·아이템·몬스터 밸런스 변경. 사용자 답변으로 밸런스만 도입하는 범위가 확정됐다.
원본 LICENSE는 GPLv2 또는 이후 버전 및 개별 파일 예외를 명시한다. 실제 이식을 선택하면 해당 고지·라이선스를 보존하고 배포 조건을 함께 처리한다.
