# UI refinements and sprite alignment

- Supply HUD uses small native pixel silhouettes, updated only when their four-step level changes. Food slices represent fullness (like the gauge); the adjacent number remains actual owned food count. Torch flame height represents equipped fuel; unequipped, extinguished and depleted torches have no flame. No per-frame icon animation or generated bitmap dependencies.
- Detail folio uses the available viewport height and a wider mobile width. Header/tabs stay outside the scroll; status content has more usable room.
- Item details float under the modal, not inside the inventory VBox. Selecting items no longer scrolls away the equipment paper doll. Popup placement prefers below the selected slot, otherwise above, bounded by the viewport. Mobile tap selects; outside tap/close dismisses. Existing equip/use/drop authority unchanged.
- 0x72 left-facing bodies incorrectly added one sprite width to x before drawing with a negative width. Godot mirrors UVs without requiring that translation. Removed the translation; opaque rendered bounds now match for both facings.
- Motion expiration requests a final redraw before processing stops, avoiding stale camera/actor canvas offsets until the next action.

Validation: main_hud_acceptance and character_views_acceptance run in headless and X11; sprite_alignment_acceptance checks actual rendered bounds in both facings and final camera redraw. Screenshots from the UI tests are local `/tmp/main-hud-runtime.png`, `/tmp/character-status.png`, `/tmp/character-items.png`. Physical mobile testing remains necessary.
