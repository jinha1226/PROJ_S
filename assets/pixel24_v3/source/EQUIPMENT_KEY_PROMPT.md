# Equipment keyed source

Use equipment-keyed.png for import; equipment.png contains baked checkerboard and is archived only.
Built-in imagegen background edit; preserve source shapes, replace backdrop with saturated magenta for deterministic alpha extraction.
Same 4x4 mapping as EQUIPMENT_PROMPT.md. Isolated hood/helmet openings must also be keyed.

Use case: background-extraction. Edit target: the equipment atlas. Change ONLY the background: REMOVE ALL gray-and-white checkerboard including holes inside the hood, helmet and bow/crossbow. Replace it with perfectly uniform solid saturated magenta RGB(255,0,255), not transparency and not a checkerboard. Preserve all sixteen equipment pixel sprites, cell layout, their exact silhouettes and colors, and sharp pixel edges. Do not add outlines, shadows, gradients or noise. Every background pixel including internal empty openings must be exactly the same flat magenta. No text. This is a color-key source for a sprite importer.

