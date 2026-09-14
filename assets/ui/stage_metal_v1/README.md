# Stage metal button skin v1

Approved pixel-metal button mockup adapted with the built-in imagegen tool (style-transfer mode). No CLI/API fallback used.

- `frame.png`: generated project asset, 1254 × 1254 RGB (opaque charcoal corners).
- `playtest/stage_button_skin.gd`: one cached nearest-resized 64 × 64 texture, shared StyleBoxTexture states; 8px fixed corners/content margins. No per-frame texture resizing.
- Normal slate, selected/proceed cyan, pressed darker cyan, disabled dim slate are engine tints of the same frame, so corner geometry stays identical.
- Used by stage portraits, both skill slots, Proceed/deployment, and top menu. Detail windows keep their existing theme. Text, portraits and HP/MP remain live UI, not baked into textures.
- Built-in generated source: `exec-e3521df6-58e6-4203-bdeb-456eddd09090.png`; approved style reference: `exec-f9c9ebb1-df3a-4496-8402-7d459eefa011.png`.

## Final generation prompt

Use case: style-transfer. Create ONE production game UI texture, not a mockup. Reference image is approved STYLE reference. Output a square 1024x1024 image containing exactly ONE blank square button frame filling the canvas edge to edge. Match reference BASIC NORMAL blue-gray slate metal frame with small stepped bracket rivets at four corners and dark blue charcoal flat center. Clean coarse pixel art, as if 64x64 pixels enlarged by nearest neighbor. The whole frame occupies the whole canvas, no surrounding padding, no text, no icons, no diagrams, no other buttons, no drop shadow outside. Thin 4-pixel-wide metal bevel at 64px logical size, corner brackets confined to 8x8 logical pixels. Center must be perfectly flat solid dark #15212b, straight edges uniform and stretchable for Godot 9-slice. Symmetrical identical corner footprints. No gradients, no ornamental grain, no glow. We will tint this neutral metal frame cyan for selected/proceed and darken for disabled using engine states. Preserve the slate metal and crisp stepped corners from the approved reference.

## Verification

Godot 4.6.2, Linux validation copy, 2026-09-14:

- `tests/stage_button_skin_acceptance.gd`: 64px shared texture, fixed corners, selection/press/release, drag/cancel, disabled and hold behavior.
- `tests/stage_context_ui_acceptance.gd`: actual 360×800 viewport touch dispatch, portrait opens character window, deployment and Proceed each run exactly once.
- `tests/nine_room_ui.gd`: 360×800 and 390×844 layout and stage UI regression.
- Runtime screenshot: `docs/ui/portrait-context-ui-v2/metal-buttons-runtime.png`.

These checks cover the skin and affected UI, not the full gameplay suite or a physical mobile device. No combat formulas or board rendering changed.
