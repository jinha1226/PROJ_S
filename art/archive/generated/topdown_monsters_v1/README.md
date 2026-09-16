# Fixed-front monster assets v1

Runtime sprites for the two monster species currently spawned by floors 1–2.
Both are direction-independent, unarmed 96×96 PNGs with a shared foot baseline.

## Generated source

- `source/goblin_kobold_sheet.png`: transparent two-character source sheet
- `runtime/goblin.png`: 96×96 goblin runtime crop
- `runtime/kobold.png`: 96×96 kobold runtime crop
- `review/goblin_kobold_96px.png`: full-size side-by-side review strip
- `review/goblin_kobold_24px.png`: mobile-distance readability strip

The shipping copies live in `assets/topdown_fixed_front/monsters/`.

## Generation prompt

> Create a transparent PNG asset sheet containing two cute fantasy creature
> tokens for a mobile tile game, matching the attached character sprite style.
> One horizontal row with exactly two separate, equally sized full-body figures
> centered in independent cells with generous transparent padding and the same
> foot baseline. Left: a small olive-green goblin with large pointed ears and a
> plain charcoal tunic. Right: a small warm rust-and-ochre kobold with a compact
> reptile-like muzzle, short backward horns, and a plain charcoal tunic. Use
> compact SD proportions: large head and torso, very short close-set arms and
> legs, both feet fully visible. Fixed-front slightly top-down presentation,
> direction-independent. No handheld objects, armor, shadows, ground, scenery,
> lettering, labels, borders, UI, blood, or action. Facial marks should be
> minimal: just two tiny dark eye marks. Crisp pixel-hybrid edges, restrained
> dark outline, simple readable silhouettes, muted colors, consistent scale and
> lighting, suitable for cropping into two 96 by 96 transparent runtime sprites.

The first output baked in a checkerboard. A second image edit preserved the
figures while replacing that checkerboard with true alpha transparency.
