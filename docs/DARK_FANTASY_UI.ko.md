# 다크 판타지 UI 스킨

공통 이미지: `assets/ui/dark_fantasy_v1/iron_frame.png`.
`imagegen` 스킬의 built-in 도구로 생성했다. 원본을 보존하고 Godot에서
nearest-neighbor로 48×48 UI 텍스처를 캐시한다. 24×24 월드 타일과 함께 쓰는
2배 UI 단위이며, 생성 원본이 정확한 24×24 픽셀 파일이라는 뜻은 아니다.
8픽셀 모서리를 고정하는 `StyleBoxTexture` 9-slice로 버튼과 패널을 늘린다.

공통 버튼, 초상화 테두리, 기술 버튼, 탭, 정보 패널, 마을 시설 메뉴,
전술 팝업과 툴팁에 적용했다. 체력 게이지의 비례 채움은 단색으로 유지한다.
기본 철색, 선택/포커스 황동, 위험 적색, 비활성 어두운 철색을 구분한다.
한글은 저장소의 Galmuri14, 텍스처는 nearest 필터를 사용한다.
기존 아이콘에는 픽셀 선을 사용하고 휴식·줍기·전술의 기호를 구분했다.
초상화의 옛 256픽셀용 자르기 좌표를 24픽셀 원본 기준 16픽셀 상반신으로
고치고, 장비 레이어를 함께 정수 배율로 그려 빈 초상화 문제도 수정했다.
맵 타일이나 캐릭터의 원본 아트 자체는 이번 변경에서 다시 그리지 않았다.

## 검증

초상화별 슬롯 정렬·빈 슬롯·시전자 전환·자연 탐험 후 화염탄 시전,
치유할 피해가 없는 대상 거부와 시간 불변을 acceptance test로 확인한다.
`tools/capture_dark_fantasy_ui.gd`는 실제 OpenGL 렌더러로 360/450px 필드,
전술 메뉴와 마을 화면을 캡처한다. 웹 release export와 소스 밖 패키지 초기화도
확인했다. 원격 배포와 브라우저 실기기 테스트는 포함하지 않는다.

확인한 캡처: [360px 필드](previews/dark-ui-360.png),
[450px 필드](previews/dark-ui-450.png), [전술](previews/dark-ui-tactics.png),
[마을](previews/dark-ui-town.png).

## 생성 프롬프트

Use case: stylized-concept. Asset type: production game UI 9-slice texture, not a mockup. Create ONE square blank dark-fantasy black iron and worn stone UI frame suitable for a 24x24 pixel-art dungeon game. The whole image must be a faithful nearest-neighbor enlargement of an EXACT 24 by 24 logical pixel sprite, with hard square pixel edges, limited 10-color grayscale palette and absolutely no anti-aliasing, blur, gradients, letters, icons, symbols, ornaments, or text. Fill the entire square edge to edge, no outside margin, no background beyond the frame. Four logical pixels thick frame on all four sides. Square stepped corner bevels and tiny worn iron rivet marks contained strictly inside each 4x4 corner. Top and left edge are subtly lit iron, bottom and right are deep charcoal. The middle 16x16 logical pixels are solid almost-black charcoal, completely uniform, so it can stretch behind legible text. Middle edges must be straight, simple and stretchable. This will be cut at exactly one-sixth and five-sixths of the image width/height for Godot StyleBoxTexture nine-slicing. Restrained grim dark fantasy, tactile black iron, no gold or cyan, no rounded smooth corners. Output one square raster image.
