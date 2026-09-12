# 숙련·이능 통합 UI

승인 목업: [growth-combined-approved.png](growth-combined-approved.png)

## 구현 범위

- 기존 인물 창의 숙련·이능 탭에 2×2 숙련 카드, 6칸 결속 스트립, 선택한 이능의 효과 설명, 보관 정수 목록을 함께 배치.
- 숙련은 현재 rank와 실제 설정의 배율을 표시. 기존 투자 확인/명령/안전 조건을 보존.
- 좁은 모바일은 기존 세로 스크롤을 사용. 메인 HUD/로그/초상화 배치는 변경하지 않음.
- 생성 이미지를 화면에 붙이지 않고 기존 금속 프레임과 네이티브 컨트롤, 정적인 작은 문양으로 구현. 매 프레임 재생성하지 않고 데이터 변경 시 갱신.
- 새 몬스터 이능은 현재 acquisition metadata만 구현되어 있음. 목록에서 패시브/액티브 설명을 볼 수 있지만 `미구현`으로 명시하고 흡수를 비활성화. 기존 FIREBOLT 흡수 경로는 유지. 이 변경은 이능 전투 효과나 VFX 구현 완료를 의미하지 않음.
- 목업의 예시 포인트/아이템/결속을 실제 런에 주입하지 않음.

## 디자인 출처

앞선 턴에서 내장 imagegen으로 제작하고 사용자가 승인한 2×2 통합 목업을 참고했다. CLI/API 생성은 사용하지 않았다. 목업의 과한 여백은 줄이고 효과 설명은 실제 데이터에서 가져온다.

최종 목업 편집 프롬프트:

> Use case: ui-mockup. Edit this single portrait Korean mobile dungeon RPG mockup. Change ONLY the mastery section layout from four full-width stacked rows into a compact TWO COLUMN BY TWO ROW grid of four equal cards. Top left 근접, top right 원거리, bottom left 마법, bottom right 방어. Keep the same dark pixel iron/brass/cyan style, title 숙련 · 이능, mastery remaining-points header and ALL ability content below unchanged in content and order. Reflow lower ability section upward to use space saved; shorten overall portrait layout rather than introducing empty space. Each mastery card has a small icon, name and rank, a concise effect label in one or two readable lines, and its own easily tapped + button. Exact card text: '근접' '3/10' '근접 공격·이능 +24%'; '원거리' '2/10' '원거리 공격·이능 +16%'; '마법' '1/10' '마법 공격·이능 +8%'; '방어' '2/10' '방어력·회피·막기 +16%'. Compact small icons, not giant emblems; no rank pips, no flavor copy. Preserve six ability slots, selected 포식 신경, 고블린 source, selected 패시브 description 다친 적에게 근접 추가 피해 and unselected 액티브 description 약점을 노리는 일격, stored essence row and 흡수 button. ONE portrait screen, not side-by-side screens. The mastery grid should be visibly 2x2 and occupy substantially less height than original mastery list. Preview only, no additional elements.

## 검증

- `tests/ability_cleanup_acceptance.gd`: 기존 테스트 스킬 자동 지급 금지 회귀 검사.
- `tests/growth_ui_acceptance.gd`: 실제 shell의 동일 탭에서 2×2 배치, 6칸 스트립, 최소 터치 영역, 390/360 폭에서 논리 viewport 경계, 두 효과 설명과 미구현 정수 소비 방지, 읽기 전용 UI의 snapshot 보존 검사.
- 화면 fixture 정수는 렌더 테스트 전용이며 실제 인벤토리에 추가하지 않는다.
- X11 환경의 OS 창 높이는 디스플레이 제한을 받으므로 실제 휴대폰 터치/브라우저 검증은 별도 필요.
