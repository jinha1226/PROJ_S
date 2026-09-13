# DCSS item tiles (CC0 export subset)

Source: https://github.com/crawl/tiles/tree/a6ea1655db5c044829d9eea19a232fa6fcac87b0/releases/Nov-2015

Retrieved 2026-09-14. The crawl/tiles project publishes a selected CC0 export and excludes pieces with unresolved licensing; see the included upstream README, ARTISTS and TILES_UNDER_UNKNOWN_LICENSE files. We selected only files actually present in that export, not arbitrary tiles from the GPL game checkout. CC0 reference: https://creativecommons.org/publicdomain/zero/1.0/

All PNGs are unmodified originals. Filename `item__weapon__club.png` corresponds to export path `item/weapon/club.png`; replace `__` with `/` to recover each source path. Runtime mapping: `playtest/dcss_item_assets.gd`. This is the November 2015 artwork export, independent from our DCSS 0.34.1 balance reference.

Known item approximations: trident uses the spear2 silhouette; chain armour uses ring_mail1; padded armour uses robe2; orcbow uses longbow1; brass charm uses face1_gold. These are temporary same-category proxies, not claims of exact original equipment depiction. Scroll appearances 10–11 reuse colours with distinct existing number marks for legacy consumable definitions. No new effect badge has been added in this change.

The user subsequently approved extending the trial to terrain and actors. `world/` follows the same source-path encoding. Mapping: `playtest/dcss_world_assets.gd`. Proxies include beastkin → gnoll, frilled lizard → giant newt, rat/river rat → zombie rat (the export has no ordinary rat), fire lizard → iguana, frost spider → spider, troll → deep troll, stone golem → iron golem, shadow beast → hell hound, aberration → brain worm; several are only silhouette placeholders, not lore matches. Sandstone/limestone temporarily represent wood/metal floor surfaces. Other listed monster identities use matching or close-family exported sprites.

Actors are static whole-body sprites: no equipment layering or walking-frame animation in this trial. Movement interpolation, combat and inventory equipment stats remain unchanged. Previous 0x72 source assets are preserved. Some small environment effect/feature icons still use the existing renderer.

2026-09-14 follow-up: `items/item__food__chunk.png` is the unmodified `item/food/chunk.png` from the same pinned export. It represents all monster ability meats; legacy `ESSENCE_*` keys are save/content identifiers, not essence artwork. SHA-256: `76290ff14cd6a2d0ba876f368d5eabbfb91bd70720b69b5874bc8d06d4b0cb45`.
