# Plan A 기준선 테스트 결과

- 실행 일시: 2026-09-18
- git HEAD: `64931b3` (브랜치 `feat/srpg-stage-campaign`, 브리프 기준 커밋 79f1f17 위)
- 실행 방식: `/mnt/d/STARTU/proj-s-srpg-stages`를 `/root/lw-bench-srpg/`로 rsync 후 ext4 사본에서 순차 실행 (9p 마운트 회피)

## Import 로그 요약

```
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/
cd /root/lw-bench-srpg && godot --headless --path . --editor --import --quit >/tmp/import.log 2>&1
```

- `import exit 0`
- `/tmp/import.log` 내 `SCRIPT ERROR` 발생 횟수: **0건**
- 애셋 재임포트(644 steps) 및 에디터 레이아웃 로딩까지 정상 완료

## 테스트 결과

| 테스트 | 결과 | 비고 |
|---|---|---|
| stage_counterplay_acceptance | PASS | `STAGE_COUNTERPLAY PASS`, exit 0 |
| srpg_party_turns_acceptance | PASS | `SRPG_PARTY_TURNS PASS`, exit 0 |
| first_floor_solo_roster | PASS | `FIRST_FLOOR_SOLO_ROSTER PASS`, exit 0 |
| handcrafted_tile_assets_acceptance | PASS | `HANDCRAFTED_TILE_ASSETS PASS`, exit 0 |
| round_combat_scenarios | PASS | `ROUND_SCENARIOS PASS`, exit 0 |
| first_floor_stages_acceptance | PASS | `FIRST_FLOOR_STAGES PASS`, exit 0 |
| stage_context_ui_acceptance | 미실행 (xvfb 없음) | `which xvfb-run` 결과 없음 — X11 필요한 테스트라 이 환경에서 실행 불가 |

## 결론

6종 테스트 모두 이 환경에서 PASS, exit 0. `stage_context_ui_acceptance`는 xvfb-run이 설치되어 있지 않아 미실행으로 기록. 이후 작업(Plan A 스테이지 맵/오서드 룸 구현)은 이 표를 기준선으로 삼아 "새 실패 없음"으로 판정한다. 실패 항목이 없으므로 별도 수정은 하지 않았다.
