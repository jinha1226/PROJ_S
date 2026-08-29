# RPG 성장 수직 슬라이스

## 권위와 수명

주인공의 `ProtagonistProgression`은 `PartyEncounterState` schema v4 안에 들어가는 원정별
권위 상태다. snapshot/세션 save DTO는 모두 깊은 복사이며 UI DTO가 권위가 아니다. 사망 후
새 원정이나 `reset_party`/동일 원정 재시작은 새 value object를 만들어 레벨 1, XP 0,
훈련 0으로 완전히 초기화한다. 영구 보너스나 meta carryover는 없다.

훈련 집중 변경은 `progression.focus_changed` 사건과 session journal의 `progression` 명령을
함께 남긴다. load는 journal을 처음부터 replay한 snapshot과 저장 snapshot이 완전히 같을
때만 transactionally 교체한다. 승리 XP와 훈련은 canonical `party.victory` ID를 한 번만
처리한다. refresh, preview, 반복 입력은 XP source가 아니다. world validator는 사건
history에서 집중/승리 투영을 다시 계산하여 XP, 기술 훈련, 처리된 승리 ID 변조를 거부한다.

## 공식

- 조우 승리: XP `100` (정수, 무작위 없음)
- 레벨 `L` 시작 누적 XP: `25 × (L-1) × (L+2)`; 따라서 L1→L2는 100,
  L2→L3는 추가 150이다.
- 훈련 집중 합계는 항상 `100`. 기본은 근접 50 / 방어 30 / 탐험 20이며 UI에서 한 기술을
  선택하면 60 / 20 / 20 preset으로 바뀐다.
- 승리 훈련: `100 × focus / 100`. 현재 값들이 100의 약수이므로 손실이나 부동소수점이 없다.
- 기술 rank `R` 시작 누적 훈련: `25 × R × (R+1)`; R1=50, R2=150이다.
- 캐릭터 레벨은 pacing/요약 표시일 뿐 공격·피해에 곱하지 않는다.
- 근접 전투는 rank당 근접 `base_damage +2`다. 기존 armor와 guard 계산 전에 적용되고,
  결정론적 명중/출혈 commitment와 RNG lane은 바뀌지 않는다.
- 방어술은 주인공 HOLD의 물리 피해 감소율을 `min(500, 250 + 50 × GUARD rank)` milli로
  정한다. 즉 기본 25%에서 rank당 5%p, 상한 50%다. flat armor 적용 뒤 정수 절삭하며
  기존 HOLD 지속시간 200은 바뀌지 않는다.

## 기술과 이정표

현재 행동에 대응하는 작은 기반만 둔다.

- 근접 전투: 현재 MELEE 피해에 연결됨.
- 방어술: 현재 HOLD 물리 피해 감소율에 연결됨.
- 탐험술: 현재 권위 효과가 없는 후속 개발 seam이다.

각 registry 항목은 label, 설명, effect ID, 다음 milestone rank/label을 갖는다. modal은
milestone을 “아직 미구현”으로 명시하며 능동 기술을 가장하지 않는다. body simulation,
equipment, mutation, use-grind, 거대 skill tree는 이 slice에서 의도적으로 제외했다.

## 적 레벨과 위협

적 레벨은 저장하지 않고 canonical combat profile과 최대 HP에서 도출한다.

`score = power×4 + accuracy/20 + evasion/20 + armor×10 + max_hp`

`enemy_level = 1 + max(0, score-200)/100` (정수 나눗셈). 위협도는 같은 score를 주인공의
현재 HP와 근접 기술 보너스를 포함한 capability score에 비교한다: `<50% 하찮음`,
`50..85% 대등`, `86..120% 위험`, `>120% 치명적`. 이는 숨은 intent/path를 노출하지
않으면서 부상 상태를 반영한다.

## 확장 seam

추가 조우는 새 `party.victory`를 기존 award projection에 연결하면 된다. 능동 milestone은
registry metadata에 command/unlock ID를 추가한 뒤 별도 canonical command/event와
validator를 도입한다. 장비·신체·변이는 progression level에 곱하지 말고 combat capability
provider를 병렬로 합성해야 한다. use history는 추후 넣더라도 제한된 비-grind modifier로만
둔다.
