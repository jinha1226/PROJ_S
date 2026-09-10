# 환경 상호작용 효과

## 표시 규칙

| 실제 사건 | 짧은 효과 |
|---|---|
| 점화·불 확산 | 주황 불티 |
| 소화·약화·불 소멸 | 회청색 잔불 입자 |
| 결빙 | 푸른 결정 선 |
| 융해·응결·물 붓기 | 푸른 물방울과 파문 |
| 전기 전도 | 노란 번개 |
| 연소 폭발 | 주황 충격파 |
| 압력 파열 | 회백색 충격파 (불꽃과 구별) |
| 지형 파괴 | 흙빛 파편 |
| 증발·화염구 | 기존 흰 수증기 / 주황 투사체 효과 유지 |

실제 지도 바닥에도 얼음의 푸른 면·균열, 기름의 갈색 막, 연기의 회색 농도 표시를 연결했다.
이전의 수증기 표시와 함께 현재 보이는 칸에만 나타나며 MEMORY/UNSEEN에는 현재 상태를 노출하지 않는다.

## 비용·안전성

- `environment_vfx.gd`는 이벤트→표현 매핑만 담당한다. 물리, RNG, 피해 수치를 바꾸지 않는다.
- 효과는 420~850ms 후 끝난다. 기존 화염구/증발 효과는 1초다.
- 한 전달 묶음에서 같은 종류·같은 칸은 하나로 합치고 신규 환경 효과는 최대 24개만 표시한다.
  기존 전체 활성 효과 제한 48개도 유지한다.
- 숨겨진 환경 효과는 큐에 넣지 않는다. 한 번 소비/생략한 event ID는 재생하지 않으므로
  나중에 시야가 열리거나 동일 결과를 새로고침해도 과거 효과가 갑자기 나오지 않는다.
- 폭발 root와 파열 root를 다시 그리지 않고 실제 전파 칸의 explosion_wave를 사용하여
  동일 폭발을 중복 연출하지 않는다. 연료 소비 tick마다 연기 입자를 생성하지 않는다.
- 새 외부 코드·이미지·음원 없이 기존 픽셀 도형 렌더링 경로를 사용한다.

## 검증 명령

```sh
godot --headless --path . --script tests/environment_vfx_acceptance.gd
godot --headless --path . --script tests/fireball_environment_acceptance.gd
godot --headless --path . --script tests/run_environment_regression_tests.gd
```

VFX acceptance는 실제 시뮬레이션의 점화/소화/상변화/전기/폭발/파괴 이벤트 연결,
모든 primitive, 중복 제거, 숨김→노출 시 과거 사건 미재생, 대량 연쇄 상한,
렌더링의 세계·RNG 비변이성을 검사한다. Pages CI에도 추가했다.

Godot 4.6.2 검증: VFX acceptance PASS (headless 및 X11/Compatibility),
화염구 acceptance PASS, 환경 회귀 62 tests / 0 failed.
X11에서 대량 연쇄 24개 상한과 실제 primitive 렌더링 화면을 확인했다.
