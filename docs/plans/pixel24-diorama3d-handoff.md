# 새 실행 세션 전달 문구 — LW-D3D-01

모델은 Sol, 추론은 medium으로 선택하고 작업 폴더를 아래 경로로 지정한다.
아래 문구를 새 세션에 전달하면 된다.

```text
/mnt/d/STARTU/living-world-sim-diorama3d 에서 LW-D3D-01을 구현해줘.
브랜치는 feat/pixel24-diorama3d 이고, 최신 푸시본으로 확인한
29fcc26c42c427fa7de580603b94fe46e4c0afdb에서 분리한 작업 폴더야.

docs/plans/pixel24-diorama3d-plan.md 전체와
같은 폴더의 pixel24-diorama3d-source-audit.json을 읽고 실행해.
이 요청은 위 계획 범위의 구현·테스트·문서화·커밋까지 승인한 거야.
상위 AGENTS.md의 지정 세션 대신, 이번 작업은 이 새 세션이 실행 담당이고
결과는 나에게 직접 보고해. 별도 queue나 하위 실행 에이전트로 재위임하지 마.

현재 pixel24_v3/fit_v2 에셋을 기준으로 실제 부피가 있는 3D 모델을 만들고,
수직 직교 탑뷰에서 한 칸을 24 렌더 픽셀로 보여줘.
18×18칸 시험 구역에 인간·드워프·고블린, 인간 검 장비 토글,
창고 3×3·대장간 3×2, 나무와 소수 지형·소품을 구현해.
칸 클릭/이동, 장애물 차단, 나무 가림 처리를 확인해.
평면 이미지를 Sprite3D에 붙이는 것으로 실제 3D를 대체하지 마.

먼저 구체적인 protocol을 작성·커밋하고, 구현 후 실제 렌더 이미지를 확인해.
24픽셀 투영 측정과 원본/3D 비교, focused tests, 결과 문서까지 완료해.
원본 에셋과 다른 작업 폴더의 변경은 보존하고,
본편 전환·main 병합·원격 push/배포는 하지 마.
결과는 docs/results/pixel24-diorama3d-result.md에 정리하고
결과 commit, 실행 방법, 주요 이미지와 한계를 나에게 보고해.
```
