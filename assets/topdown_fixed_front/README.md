# Fixed-front top-down runtime art

These are the shipping 96x96 RGBA layers selected from
`assets/generated/topdown_fixed_front_v1/runtime`. They live outside the generated
source tree because the Web export intentionally excludes generated concepts and
review sheets.

All body, armor and weapon PNGs share one canvas and foot anchor. Compose them in
that order without directional swapping, mirroring or per-layer repositioning.
The source sheets and terrain candidates remain in the generated asset folder and
are not runtime dependencies.
