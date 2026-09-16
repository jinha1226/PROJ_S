# 아이템 보충 및 조명 경계 수정

- [추가 아이템 6종](icons.png): 내장 image_gen으로 제작, [원본과 프롬프트](../../../art/sources/fantasy_items_v2/README.md).
- [다리 비교 목업](../../../art/archive/mockups/character-legs/comparison.png): 사용자 선택 전 미적용.

## 조명

기존 폰 아트 적용 캡처에서 보이는 큰 밝은 삼각형 얼룩은 극좌표 조명 메쉬가 시야 경계를 가로지르고, 시야 밖 꼭짓점을 투명하게 샘플링하면서 발생할 수 있었다. 평면 모드에서는 보이는 각 타일 안에 2×2 사각형을 나누어 조명 메쉬를 생성한다. 모든 삼각형이 한 타일 안에 머물러 MEMORY/UNSEEN 타일을 가로지르지 않는다. 작은 이끼·균열은 원본 바닥 그림이므로 유지한다. 사용자가 본 정확한 화면은 제공되지 않았으므로 모든 얼룩의 원인이 같다고 단정하지 않는다.

- radial_darkness_acceptance: 각 삼각형의 세 꼭짓점이 동일한 VISIBLE 타일 안에 있는지 검사.
- retained_render_acceptance: 실제 GPU 렌더링 통과. 기존 밝기 계산과 캐시 동작 유지. retained/immediate 그림 차이 평균 0.00235, 변화 픽셀 비율 0.00356.
- fantasy_item_expansion_acceptance: 새 무기 및 강철 변형, 몬스터 곤봉, 미감정 물약 연결 검사.

## 휴식

자동 휴식 안내는 `휴식 중 · HP 현재/최대 · MP 현재/최대`로 표시한다. 내부 경과 시간은 안내에 노출하지 않는다. 회복과 시간 진행 규칙은 그대로다.
