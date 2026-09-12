# Character inspection and pickup refinement

## Item transaction

Live field item operations retain rollback mementos, previews, their existing one-turn time cost and journal order. They now capture without a redundant full-history audit. The field-turn resolver validates its own response; the item commit then validates its new event tail and current mutable state. Full audits remain at save/load/replay and rollback restore. Non-field legacy transactions retain their original exhaustive validation.

One local X11 fixture (44 events) measured pickup at 115,597 µs and a separate full-state audit at 97,233 µs. This is not a mobile benchmark or an old/new total comparison. The change removes two such full audits from the live item path, not rollback copies or the legitimate world turn.

## UI

- Shared HP and MP bars are outside the tab-specific scroll area. All character tabs retain them; refresh uses the inspected character's actual HP and party-member energy. Characters without party energy show MP —, not fabricated MP.
- Removed duplicate status-only HP/MP rows. The status sheet's static controls pass wheel input through; its gesture owner supports touch/mouse drag anywhere in the sheet while leaving the native scrollbar available.
- Hold a combat card or body row for 550 ms to inspect. Moving over 10 px cancels inspection and scrolls. Modal close cancels the gesture and popup. No permanent per-frame tooltip polling.
- Combat explanations derive from the actual attack spec, defense snapshot, equipment, talent and mastery contributions. Evasion is described as a defense rating used against enemy accuracy, not a guaranteed evade probability.
- Body values and individual limbs use separate rows. Descriptions distinguish skin, soft tissue and bone effects, and explicitly disclose that consciousness-driven action restrictions are not connected yet.

## Verification

`character_views_acceptance.gd`: rendered layout, inventory/equip/replay and relationship checks.

`character_interaction_pickup_acceptance.gd`: canonical drop/pickup, injected response failure with exact state/journal rollback, duplicate rejection, exhaustive post-operation audit, exact save replay, actual viewport touch hold and drag, independently formatted body rows, canonical combat injury and potion use, open-header HP update, SKILL HP/MP visibility.

Physical mobile performance and touch feel still require device verification.
