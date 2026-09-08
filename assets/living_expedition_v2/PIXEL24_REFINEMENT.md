# 기존 24×24 캐릭터 개선 방향 — 생성 비교 시트

2026-09-09, 내장 image_gen 편집. 런타임 미적용.
파일: actors-pixel24-refinement-concept.png
편집 참조: assets/generated/topdown_pixel_readability_v1/review/actors_6x.png
실제 기존 24×24 원본: assets/generated/topdown_pixel_readability_v1/runtime/actors/base/ 및 assets/topdown_fixed_front/actors/base/
16×16 비교판은 assets/generated/topdown_pixel_readability_v2/에 별도 보존되어 있다.

종족 순서와 기존 전신 비율을 유지하면서 옷의 색을 분리하는 후보이다.
중요: 생성 출력은 확대된 디자인 시트로 정확한 native 24×24 스프라이트가 아니다. 균일한 논리 픽셀 격자/색 수/알파가 보장되지 않는다. 요청과 달리 눈과 명암 세부가 남아 있어 추가 단순화 필요. 기존 24×24 파일에 적용할 팔레트·픽셀 클러스터 편집은 아직 하지 않았다.
기존 원본과 현재 게임 에셋은 변경하지 않았다.

## 프롬프트

Use case: precise-object-edit.
Input image is the EDIT TARGET: the existing enlarged reference strip of SEVEN native 24x24 pixel-art characters. Improve these existing sprites; do not replace them with vector illustration or tall characters.
Preserve the seven identities and reading order: human, elf, dwarf, orc, beastkin, goblin, kobold. Preserve the compact full-body silhouette, head/body proportion, very short arms close to torso, tiny close-set feet, fixed forward-facing slightly overhead view, and the coarse logical 24x24 pixel grid of EACH character. The reference is a nearest-neighbor enlargement: every logical source pixel should remain a single flat square block. NO finer sub-pixel detail than the reference.
Output: one wide horizontal strip of seven evenly spaced complete sprites on uniform muted slate background #525E68, no labels, UI, borders or shadows. Render each logical pixel as a crisp integer-sized block, NOT blurry or antialiased. This is an enlarged native-pixel DESIGN REVIEW, not high-resolution pixelated illustration.
Changes: simplify facial features by removing eyes/mouth sparkle and expressions, retain skin plane, hair/ears/beard/snout as species cues. Reduce scattered single-pixel flecks in clothes into connected 2-4-pixel clusters. Separate head, torso, and feet clearly while keeping the feet nearly together. 1 logical pixel charcoal outer contour, no extra heavy halo. Broad lit plane and one shadow plane only. Max about 10-12 colors per sprite.
Make clothing distinct without adding detail: human light ash tunic with small rusty-red shoulder patch; elf dusty muted teal tunic under pale hair and sharp ears; dwarf aged ochre apron with one big copper beard shape; orc muted plum/dark wine tunic and gray-green skin; beastkin smoky blue torso and pale angular face; goblin dirty moss tunic with yellow-green skin and broad sideways ears; kobold charcoal torso with rust orange head.
Art tone: restrained dark fairy tale, worn and sober, not candy colors, not cheerful cute mascots. Borrow ONLY angular asymmetric hems and limited earth/mineral palette from paper-cut design, NOT paper texture or smooth polygons. Keep bright bone/ash faces and a readable body plane so darkness does not hide the figures on a phone. No weapons or equipment overlays, no glossy shading, no realistic textures, no tall anatomy, no busy accessories.

