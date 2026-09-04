# Armored Hero Animation Prototype

This is a fixed-camera fake-2.5D character set. The character is an upright sprite
anchored over a projected map cell; it must not be warped as a floor texture.

## Atlas layout

| Row | Direction | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- | --- |
| 1 | South | Idle | Walk left | Walk right | Attack |
| 2 | East | Idle | Walk left | Walk right | Attack |
| 3 | North | Idle | Walk left | Walk right | Attack |
| 4 | West | Idle | Walk left | Walk right | Attack |

- `hero_armored_atlas_4x4_256.png`: normalized 1024 x 1024 RGBA atlas.
- `runtime/`: sixteen separately named 256 x 256 RGBA frames.
- `source/hero_armored_atlas_source.png`: untouched generated source.
- `hero_armored_readability_48px.png`: each frame reduced to 48px and enlarged
  with nearest-neighbor sampling for visual inspection only.
- `character_manifest.json`: atlas layout and suggested feet anchor.

The armor visibly covers both shoulders and arms. Walk frames alternate the legs and
counter-swing the arms; attack frames extend the sword arm outside the torso silhouette.

This prototype is a single baked armored appearance. Supporting equipment changes
properly will require a shared base-body animation atlas plus armor and weapon overlay
atlases using exactly the same frame rectangles and feet anchor.
