# 모바일 전술 화면 목업 v1 — 생성 프롬프트

생성 방식: 내장 image_gen 도구. 아래 두 프롬프트로 신규 이미지 생성. 실제 게임 캡처나 구현 완료 화면이 아니다.
현재 스프라이트 원본을 직접 사용한 합성이 아니라, 픽셀아트와 아이소매트릭 투영을 지시한 디자인 참고 이미지다.

## A — 전장 중심

```text
Use case: ui-mockup
Asset type: high-fidelity mobile tactical dungeon RPG gameplay screen proposal, portrait 9:19.5, full screen edge-to-edge with NO phone hardware, NO surrounding presentation slide.
Primary request: Korean mobile roguelike with a readable isometric tactical dungeon, a mixed ally/enemy initiative sequence, editable companion plans, and one explicit execute button. This is a design proposal, not a screenshot of an existing shipped game.
Style: restrained crisp pixel-art sprites on muted blue-gray isometric stone diamond tiles; dark charcoal UI with thin muted brass separators, readable large Korean text, minimal ornament. Original fantasy art, no trademarks or copied game artwork. Practical implementable Godot UI, flat panels, no cinematic bloom.
Scene: small visible dungeon combat encounter, three adventurers (human sword fighter, dwarf with axe, elf caster), three enemies (two goblins and a skeleton), low wall corners that do not occlude actors, one small pillar and a shallow-water patch. Leave visual breathing room. Camera is orthographic isometric; ALL tile highlights, selection outlines and path markers must follow the SAME diamond-shaped ground projection, never axis-aligned squares.
Board information: selected fighter has a thin yellow diamond underfoot; just two restrained cyan movement diamonds near the selected actor. Enemy danger is two translucent coral diamond tiles with a small attack arrow; do not blanket the entire floor in highlights. A tiny cyan suggestion marker over an ally and a small brass check mark for a user-edited action distinguish automatic versus edited plans. No floating paragraphs, damage numbers, monster side list, or health bars over every creature.
Party portraits below the board: three equally sized compact touch cards with portrait, Korean name, Lv.3, thin red HP and blue MP bars and current/max values. Use illustrative full-sized RPG values such as HP 68/90 and MP 24/30, not a redesigned tiny-number combat system.
Bottom controls: compact buttons "이동", "공격", "변이", "가방", and a clearly larger brass-accented "진행" button. Maintain thumb-friendly targets and a safe bottom margin.
Top HUD: compact floor text "지하 1층", tiny minimap, food icon and horizontal food gauge labeled "식량 72%". NO torch icon, torch counter, torch gauge, settlement/building controls, blood meter or money-shop clutter.
Log: exactly three short legible lines below the battlefield: "고블린이 공격을 준비합니다.", "동료의 행동을 수정했습니다.", "진행을 눌러 행동을 실행하세요."
Mixed initiative sequence has six small alternating party/enemy icons with ordered numbers 1 through 6, and the first allied portrait selected. This is NOT a player-faction/enemy-faction split.
Constraints: keep all essential text large enough for a 390x844 logical screen; distinct silhouettes; clear hierarchy; no oversized decorative title, no smartphone frame, no watermarks. Render one coherent portrait screen.
Layout A — battlefield-first: tiny HUD top 7%, single thin initiative strip below it 5%, battlefield dominates middle 60%, three-line log 7%, compact three-person portrait row 10%, bottom commands 11%. Initiative is secondary to the large readable playfield.
```

## B — 행동 순서 중심

```text
Use case: ui-mockup
Asset type: high-fidelity mobile tactical dungeon RPG gameplay screen proposal, portrait 9:19.5, full screen edge-to-edge with NO phone hardware, NO surrounding presentation slide.
Primary request: Korean mobile roguelike with a readable isometric tactical dungeon, a mixed ally/enemy initiative sequence, editable companion plans, and one explicit execute button. This is a design proposal, not a screenshot of an existing shipped game.
Style: restrained crisp pixel-art sprites on muted blue-gray isometric stone diamond tiles; dark charcoal UI with thin muted brass separators, readable large Korean text, minimal ornament. Original fantasy art, no trademarks or copied game artwork. Practical implementable Godot UI, flat panels, no cinematic bloom.
Scene: small visible dungeon combat encounter, three adventurers (human sword fighter, dwarf with axe, elf caster), three enemies (two goblins and a skeleton), low wall corners that do not occlude actors, one small pillar and a shallow-water patch. Leave visual breathing room. Camera is orthographic isometric; ALL tile highlights, selection outlines and path markers must follow the SAME diamond-shaped ground projection, never axis-aligned squares.
Board information: selected fighter has a thin yellow diamond underfoot; just two restrained cyan movement diamonds near the selected actor. Enemy danger is two translucent coral diamond tiles with a small attack arrow; do not blanket the entire floor in highlights. A tiny cyan suggestion marker over an ally and a small brass check mark for a user-edited action distinguish automatic versus edited plans. No floating paragraphs, damage numbers, monster side list, or health bars over every creature.
Party portraits below the board: three equally sized compact touch cards with portrait, Korean name, Lv.3, thin red HP and blue MP bars and current/max values. Use illustrative full-sized RPG values such as HP 68/90 and MP 24/30, not a redesigned tiny-number combat system.
Bottom controls: compact buttons "이동", "공격", "변이", "가방", and a clearly larger brass-accented "진행" button. Maintain thumb-friendly targets and a safe bottom margin.
Top HUD: compact floor text "지하 1층", tiny minimap, food icon and horizontal food gauge labeled "식량 72%". NO torch icon, torch counter, torch gauge, settlement/building controls, blood meter or money-shop clutter.
Log: exactly three short legible lines below the battlefield: "고블린이 공격을 준비합니다.", "동료의 행동을 수정했습니다.", "진행을 눌러 행동을 실행하세요."
Mixed initiative sequence has six small alternating party/enemy icons with ordered numbers 1 through 6, and the first allied portrait selected. This is NOT a player-faction/enemy-faction split.
Constraints: keep all essential text large enough for a 390x844 logical screen; distinct silhouettes; clear hierarchy; no oversized decorative title, no smartphone frame, no watermarks. Render one coherent portrait screen.
Layout B — initiative-first: compact top HUD 7%, a clear 14%-height planning area with six ordered actor icons and a selected action row labeled "예정: 공격" and small "수정됨" badge; battlefield 51%, three-line log 7%, three-person portrait row 10%, bottom commands 11%. Keep the same three heroes, three enemies, and dungeon situation as described. The action sequence is more prominent, but no detailed sidebar.
```
