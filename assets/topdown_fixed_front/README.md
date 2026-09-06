# Fixed-front top-down runtime art

The visible body and monster bases are native 24x24 RGBA pixel sprites derived
deterministically from the approved 96px designs. The conversion limits each
sprite's palette, removes partial alpha, and retains the common foot anchor. The
larger originals remain under `assets/generated/topdown_fixed_front_v3` and
`assets/generated/topdown_monsters_v1`; no image generator is needed to rebuild
this readability pass.

The five body bases keep the approved fixed-front pose. Species readability at
mobile zoom comes from head shape, ears, hair/fur, body proportion and color.
Equipment is still disabled for the base-readability pass; its older 96px layers
remain registered but are not composited.

`terrain/floor1_atlas_16x1_16.png` and `floor2_atlas_16x1_16.png` are the shipping
native-resolution atlases. Low-information ground uses broad 2x2 pixel clusters;
walls, routes, machinery and portals retain 1px semantic shapes. The original
128px atlases remain under `assets/generated/topdown_pixel_readability_v1/source`
as reversible sources, outside the Web package. The flat camera chooses
deterministic variants for terrain and portal state. This is presentation-only
and never changes pathing, FOV, occupancy or pointer mapping.
