# Approved 64px terrain

Unmodified copies of the project-generated sources in `docs/art/handcrafted-stages/`.
The originals remain available to the HTML preview; this directory is the Godot/export dependency.

`playtest/handcrafted_tile_assets.gd` samples the same measured atlas anchors as the
HTML preview. Ground is a transparent 64×32 diamond, obstacles occupy 64×64,
and projected dungeon wall faces use 32×48 samples. Nearest sampling is explicit.
No generative model runs in the game; a bounded shared texture cache is built once
per encountered theme. Existing simulation terrain IDs remain authoritative.
