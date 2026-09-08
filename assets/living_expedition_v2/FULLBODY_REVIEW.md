# 전신 수정 후보 — 미적용

내장 image_gen, 2026-09-09. 기존 actors.png는 보존.
파일: actors-fullbody-review.png

상반신 대신 짧은 팔·다리·발을 추가하고 슬라임과 딱정벌레의 의복을 제거했다.
사용자 피드백: 일반적인 AI 생성 이미지처럼 느껴져 고유한 아트 방향으로 재시도한다.
중간 검토 후보이며 런타임에 등록하지 않는다. 검사 결과 RGB 불투명 이미지로 체크무늬가 배경에 포함돼 있다. 실제 적용용 투명 스프라이트가 아니다.

## 생성 프롬프트

Use case: precise-object-edit.
Input image: edit target, the previous nine-character atlas. Correct the anatomical framing; these currently look like cropped bust portraits.
Output: ONE square 3x3 sprite atlas on genuine transparent background, nine evenly spaced cells with generous padding, no cell borders or labels.
Keep the species identities, reading order, muted clothing colors, bold ink contours, faceless simplicity, and coherent flat illustrated style of the reference.
CHANGE humanoids into COMPLETE standing full-body miniature game pieces: whole head, compact torso and hips, two very short close-set legs ending in clearly distinct rounded boots, tiny arms resting close to the sides. Entire figure from hair to soles visible, never cropped. Head about 40% of total figure height, torso/hips 40%, stubby legs/feet 20%. No long legs, no wide stance, no huge shoulder cape hiding body. Simple short tunic with waist band instead of portrait-style shoulder cloak. Neutral front-facing sprites viewed slightly overhead for a flat top-down world, no isometric turn. Human navy, elf moss, dwarf ochre with beard NOT hiding entire torso, orc burgundy, wolf beastkin violet, goblin brown, kobold rust. Distinct tiny feet/paws MUST visibly finish each humanoid silhouette.
Bottom middle: a WHOLE squat turquoise slime puddle creature, no clothes, no clasp, no human torso. Bottom right: a WHOLE dark beetle with shell abdomen and six short insect legs, no clothes, no clasp, not a beetle head on a human bust.
Mobile clarity: extremely simple large color masses, 2-3 tones per material, strong outside edge, no eyes or mouth detail, no detailed fingers, no little buckles or necklace, no texture grain, no decorative highlights, no weapons. Designed for 24-36 screen-pixel display. Every subject centered and contained within its own equal cell, feet/puddle bottoms align to common 85% cell-height baseline. No ground or cast shadow, no text, no watermark.

