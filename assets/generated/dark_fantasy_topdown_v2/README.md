# Dark Fantasy Top-Down Source Kit v2

This is a small production asset set for evaluating the new visual direction. It
contains source art and normalized runtime PNGs only; it is not wired into the game.

## Projection contract

- Floors, wall caps, the crate, and blood are true 90-degree top-down assets.
- The wall-face texture is a flat elevation mapped onto wall side polygons.
- The torch is a flat overlay attached after the engine constructs a wall face.
- No asset contains an isometric diamond or a pre-baked gameplay camera angle.
- Godot remains responsible for camera pitch, perspective, wall extrusion, FOV,
  desaturation, shadows, and light falloff.

## Files

- `source/`: untouched built-in image-generation outputs.
- `runtime/`: three deterministic 512px tileable materials and three 256px RGBA
  sprites ready for Godot import.
- `asset_manifest.json`: orientation, size, role, and anchor metadata.
- `asset_review_sheet.png`: full-resolution review contact sheet only.
- `readability_preview_32px.png`: the same assets reduced to 32px and enlarged with
  nearest-neighbor sampling to show their approximate in-game readability.
- `character/`: one armored hero prototype with sixteen direction/animation frames,
  a normalized atlas, individual RGBA files, and a 48px readability preview.

The three material textures use mirrored edge construction so opposite edges match
exactly. They are prototypes; a production biome should add several non-mirrored
variants to reduce visible repetition.
