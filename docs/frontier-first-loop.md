# Frontier: first playable settlement loop

## Scope

Reuse the existing settlement, two dungeon layouts, combat, items, aid, followers and construction systems. New games begin alone at a shelter in a world whose main roads and cities are occupied. Region 1 is the old ruins along a frontier forest trail; region 2 is a mine reached through the existing deeper passage. This milestone changes campaign structure, not the terrain art into a finished outdoor biome.

## Player flow

1. Select species. Start at the shelter; the region selection panel and existing home management are available immediately, without purchasing a house in a public town.
2. Choose the forest trail. Find the waiting survivor close to the entrance, share one food, then explicitly accept companionship.
3. Return together to the entrance. Use menu → shelter return. Existing safe-return checks still apply.
4. The surviving companion becomes a persistent company member and stays at the shelter in reserve. Existing home UI lists them as a resident and can use residents for rest/work. The region panel allows assigning them to the next expedition or leaving them home.
5. Explore further to discover the mine and activate its connection. Direct mine travel remains locked until the existing anchor is activated.

## Persistence and compatibility

The new START operation has an optional boolean `frontier`. The start event and founder tag identify the campaign; original START operations retain their old behavior. Existing dungeon-focused tests explicitly choose that older start. Assistance and acceptance use the existing population command journal. Successful return emits a company-join event only once before ending temporary expedition membership. Death does not recruit a resident.

Only actual company members appear as shelter residents. Other pre-existing NPCs remain world inhabitants and explorers, not residents waiting in a magically populated player village. The starter survivor uses an existing NPC and stays in REST near the entry rather than inventing a separate dialogue-only character.

## Not included

No continuous open world, new forest art, global occupation/front simulation, multiple autonomous settlements, or permanent per-region terrain changes across expeditions. NPC labor still uses the existing settlement work model; the goal is one complete rescue-to-residency loop, not a finished RimWorld-scale colony simulator.

## Verification

`tests/frontier_campaign_acceptance.gd` exercises the actual new-game UI, singleton shelter, region departure, canonical path movement, food aid, companionship, safe return, persistent resident projection and exact save/journal replay. Existing character UI acceptance remains on the explicit legacy dungeon start.
