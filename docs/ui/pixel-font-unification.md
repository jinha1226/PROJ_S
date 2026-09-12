# Pixel typography

All explicit playtest font sources now use the bundled Galmuri14 face (license: assets/fonts/Galmuri-OFL.txt). This includes HUD, menus, character panels, map labels, ASCII fallback glyphs and combat effects, plus legacy lab screens. The main UI's inherited theme uses the same face. Existing fonts are retained on disk for historical compatibility.

Do not set the project-wide GUI font to an imported font during initial import: changing it while the editor reimports the face caused repeated text-server errors. Keep the runtime theme responsible for the default font instead.

Font import disables antialiasing and subpixel positioning and fixes oversampling to 1. Existing text sizes are preserved to avoid enlarging compact mobile controls. Bitmap glyph shapes at small/non-native sizes and fractional viewport scaling still need physical-device review; this change does not force integer viewport scaling or crop the mobile viewport.

Validation: main HUD and character-view acceptance checks include pixel-font identity and Korean/numeric glyph coverage; X11 runtime screenshots check layout after import.
