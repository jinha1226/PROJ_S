# Pixel24 equipment fit v2

This directory is a review-only staging set. The product runtime does not load
these files yet. It contains five frozen bases, two fitted armor layers per
species, seven carried weapon poses (standard and dwarf grip families), wooden
shield poses, and selective hand/beard foreground layers.

Build from the repository root:

```sh
XDG_DATA_HOME=/tmp/pixel24-godot-user \
XDG_CACHE_HOME=/tmp/pixel24-godot-cache \
XDG_CONFIG_HOME=/tmp/pixel24-godot-config \
godot --headless --path . --script tools/art/build_pixel24_assets.gd \
  -- tools/art/pixel24_human_fit_preview.json
```

Focused validation:

```sh
XDG_DATA_HOME=/tmp/pixel24-fit-test-user \
XDG_CACHE_HOME=/tmp/pixel24-fit-test-cache \
XDG_CONFIG_HOME=/tmp/pixel24-fit-test-config \
godot --headless --path . \
  --script res://tests/pixel24_equipment_fit_acceptance.gd
```

Frozen input hashes:

```text
human    32de2e3f3b86de5b63366c110d2e8f86d10d971b9450991438eb3cfbc85dc87d
elf      459a83f7f192454666d9bb41c744de8ae2a799aeda106a3863016bd0724d393d
dwarf    ad8e86b40730a89cb0744a12fa9cb5e8d315c2c89bee72f3182e596c7eaf80f6
orc      216e349d454d64a89ae33d22442e39274900c877b9458c3ba9ee6e74c6a8ade9
beastkin 6c11308196286b066dec1df0d6724551d9730314ca864bd065747a914cac8a2a
```

The labeled review matrix is ordered by rows `human`, `elf`, `dwarf`, `orc`,
`beastkin`; its columns are recorded in
`assets/pixel24_v3/review/fit_v2/equipment-fit-index.json`.
