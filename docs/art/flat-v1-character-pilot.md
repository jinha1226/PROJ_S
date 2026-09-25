# 평면 일러스트 그래픽 적용

기준 화면은 [첫 게임 화면 시안](flat-v1/reference-gameplay.png)이다. [실제 적용 화면](flat-v1/gameplay-applied.png)은 390×844 휴대폰 크기의 웹 빌드에서 캡처했다. 작은 픽셀 캐릭터 대신 큰 머리와 짧고 굵은 실루엣, 넓은 색면, 절제된 먹선을 사용한다. 표시용 원본 PNG는 `assets/topdown/flat-v1/`에 모았다.

| 시트 | 용도 |
| --- | --- |
| `actors.png` | 4열×2행: 인간, 드워프, 엘프, 오크 / 늑대인간, 술사, 상인, 방랑자 |
| `monsters.png` | 4열×2행: 쥐, 목도리도마뱀, 코볼트, 고블린 / 홉고블린, 오크, 놀, 강쥐 |
| `fire-lizard-boss.png` | 보스 전용 그림 |
| `ruins-floor-slabs.png`, `mines-floor-slabs.png` | 각 층의 2열×2행 큰 판석 |
| `ruins-wall-blocks.png`, `mines-wall-blocks.png` | 각 층의 벽 앞면·윗면 |
| `ruins-materials.png`, `mines-materials.png` | 물, 목재, 흙 등 나머지 지형 |
| `props.png` | 상자, 제단, 모닥불 등 1층 소품 |
| `action-icons.png` | 하단 기본 행동 아이콘 |

게임 화면은 `floor1_art.gd`에서 층 테마별 바닥·벽·지형 시트를, `mobile_art.gd`에서 캐릭터·몬스터·보스를 선택한다. 그리드와 이동 판정은 그대로 두고 기본 카메라를 11칸으로 맞춰 휴대폰에서 실루엣이 보이게 했다. UI 버튼은 `assets/ui/button-frames-flat-v1.png`의 48px 9-slice 프레임과 `NanumSquareR` 글꼴을 사용한다.

기존 8비트 시트는 일부 숙련·주문·장비 아이콘 및 다른 화면에서 계속 참조하므로 삭제 대상이 아니다. 오래된 비교 목업은 정리했고, 실제 사용 중인 그래픽과 기준 시안만 남긴다.
