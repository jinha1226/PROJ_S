# LW-TOWN-SPRITE-01 결과

## 상태

완료. 폐기 대상인 3D 디오라마를 `main`에 포함하지 않고, 본편 2D 마을 지도 주민 표시만 실제 Pixel24 캐릭터로 교체했다.

## 구현 결과

- `BaseSettlementView`가 주민 `species_id`를 공용 `FixedFrontTopdownAssets` 레지스트리에 연결한다.
- human, elf, dwarf, orc, beastkin은 24×24 body 스프라이트를 사용한다.
- 주민 DTO에 장비가 있으면 body → armor → offhand → weapon → foreground 순서로 합성한다.
- 작업자는 캐릭터 주변 cyan 표시로 식별하며, 휴식 완료 시 침상 뒤에도 실제 캐릭터가 계속 보인다.
- `species_id`가 없는 기존 DTO는 human으로 처리하고, 미지원 미래 종족은 화면에서 사라지지 않도록 단순 표시로 폴백한다.

## 검증

| 검증 | 결과 |
|---|---|
| `tests/town_resident_sprite_acceptance.gd` | PASS |
| `tests/pixel24_asset_acceptance.gd` | PASS |
| `tests/town_life_acceptance.gd` | PASS |
| Web release export | PASS (`index.html`, 11 MB pack, 36 MB wasm) |
| export pack 독립 시작 (`--quit-after 5`) | PASS |
| `tests/base_settlement_visual_smoke.gd` | 기존과 동일한 서비스 버튼 2건 실패 |

마을 시각 smoke의 실패 두 건은 변경 전 `origin/main@5d40ad2` 별도 worktree에서도 동일하게 재현했다. 실패 항목은 `selected facility exposes its service action`, `real mouse service dispatches once after selection rebuild`이며 주민 렌더링 변경으로 새로 발생한 회귀가 아니다.

## 한계와 판단

- 이번 범위는 기존 실제 캐릭터 자산의 본편 마을 적용이다. 주민 이동 애니메이션이나 새 방향별 마을 전용 자산은 추가하지 않았다.
- 3D 디오라마 브랜치의 scene/GLB/전용 UI는 이 결과와 `main` 푸시에 포함하지 않는다.
- 승인 질문은 충족했다. 본편 마을에서 임시 원형 주민 대신 실제 종족별 캐릭터를 표시할 수 있다.
