# DCSS 초반 콘텐츠 목록

기준: [DCSS 0.34.1](https://github.com/crawl/crawl/tree/0.34.1), commit `1eebc1a2892e1c89776a0d7a10691f8dac8d9796`. 원본 구현을 복사하지 않고 수치·규칙을 분석해 기존 Godot 엔진에 맞춘다.

실제 적용: **DCSS 대응 무기 19종, 몬스터 8종**. 기존 무기 7종과 몬스터 2종을 포함한다. 자체 재료 개량 무기 8개는 별도이며 자연 공격 8개를 포함한 무기 정의 총수는 35개다.

## 무기

피해·명중 보너스·지연은 DCSS 참고값이다. 지연 단위는 aut이며 현재 게임에서는 ×10(쇠뇌 재장전 포함), 기본 피해는 무숙련 인간 raw damage 목표 ×5다. 약한 무기는 기존 actor power 24 때문에 피해 하한 24를 사용한다.

| 이름 | 게임 ID | 피해 | 명중 | 지연 | 출현 최소 층 |
|---|---|---:|---:|---:|---:|
| club | `DCSS_CLUB` | 5 | 3 | 13 | 1 |
| whip | `DCSS_WHIP` | 6 | 2 | 11 | 1 |
| mace | `MACE` | 8 | 3 | 14 | 1 |
| flail | `DCSS_FLAIL` | 10 | 0 | 14 | 2 |
| dagger | `DCSS_DAGGER` | 4 | 6 | 10 | 1 |
| short sword | `SHORT_SWORD` | 5 | 4 | 10 | 1 |
| rapier | `THRUSTING_SWORD` | 7 | 4 | 12 | 1 |
| falchion | `DCSS_FALCHION` | 8 | 2 | 13 | 1 |
| long sword | `DCSS_LONG_SWORD` | 10 | 1 | 14 | 2 |
| scimitar | `DCSS_SCIMITAR` | 12 | 0 | 14 | 2 |
| hand axe | `HAND_AXE` | 7 | 3 | 13 | 1 |
| war axe | `DCSS_WAR_AXE` | 11 | 0 | 15 | 2 |
| spear | `SPEAR` | 6 | 4 | 11 | 1 |
| trident | `DCSS_TRIDENT` | 9 | 1 | 13 | 2 |
| staff | `DCSS_STAFF` | 5 | 5 | 12 | 1 |
| quarterstaff | `DCSS_QUARTERSTAFF` | 10 | 3 | 13 | 2 |
| shortbow | `BOW` | 8 | 2 | 14 | 1 |
| orcbow | `DCSS_ORCBOW` | 11 | -3 | 15 | 2 |
| arbalest | `CROSSBOW` | 16 | -2 | 19 | 2 |

## 몬스터

| 이름 | 게임 종족 | DCSS HD | 게임 HP | 최소 층 |
|---|---|---:|---:|---:|
| 고블린 | `goblin` | 1 | 40 | 1 |
| 코볼트 | `kobold` | 1 | 35 | 1 |
| 목도리 도마뱀 | `dcss_frilled_lizard` | 1 | 20 | 1 |
| 놀 | `dcss_gnoll` | 2 | 130 | 2 |
| 홉고블린 | `dcss_hobgoblin` | 1 | 55 | 1 |
| 오크 | `dcss_orc` | 1 | 70 | 1 |
| 쥐 | `dcss_rat` | 1 | 25 | 1 |
| 강쥐 | `dcss_river_rat` | 2 | 110 | 2 |

1층은 HD 1, 2층은 HD 1–2 후보를 사용하며 종별 출현은 seed에 따라 달라진다. 최초 튜토리얼 그룹은 기존 두 몬스터를 유지한다. 기존 신체·아트를 대용으로 사용한다. 주문·독·저항·비행·변신 등 미지원 특수 행동을 가진 적은 추가하지 않는다.

## 분석용 전체 목록

[참조 JSON](../data/reference/dcss-0.34.1-catalog.json)은 몬스터 정의 668개와 무기 정의 59개(현행 47, 구형 12)를 보존한다. 여기에는 비출현·특수 정의가 포함되며 플레이 가능한 종 수가 아니다. 런타임이 전체 목록을 읽거나 자동으로 출현시키지 않는다. 명시적 갑옷 23개도 추출했지만 매크로로 생성되는 용 갑옷 전체를 포함하는 목록은 아니다.
