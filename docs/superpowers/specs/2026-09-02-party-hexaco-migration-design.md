# Party HEXACO migration design

## Decision

Party companions use one continuous HEXACO profile with six integer axes in
the inclusive range `0..1000`: `H`, `E`, `X`, `A`, `C`, and `O`.

The temporary party-only four-facet compatibility profile
(`aggression`, `altruism`, `boldness`, `composure`) is removed from party
creation, combat utility, morale, exile records, observations, and UI. Fixed
personality archetypes are not stored or simulated. A display label may be
derived from the two strongest HEXACO deviations and has no mechanical effect.

## Deterministic generation and migration

- A companion profile is `DungeonHexacoProfile.generated(personality_seed,
  entity_id)`.
- The entity ID, rather than a roster slot, keeps the profile stable when the
  roster is reordered.
- A legacy four-facet value is never approximately mapped to a HEXACO axis.
- Session migration regenerates every companion and exile summary from the
  stored session personality seed and stable former-member ID.
- Migrated legacy journals remain strict snapshot restores because replaying an
  old automatic decision under new personality semantics is not equivalent.
  New HEXACO-native sessions retain exact journal-to-snapshot replay checking.

## Party utility semantics

- `ENGAGE`: favoured by low Emotionality (`E`), low Agreeableness (`A`), and
  high Extraversion (`X`).
- `PROTECT`: favoured by high Honesty-Humility (`H`), high Emotionality (`E`),
  and high Agreeableness (`A`).
- `RETREAT`: favoured by high Emotionality (`E`) and low Conscientiousness
  (`C`).
- `HOLD`: favoured by high Conscientiousness (`C`) and low Emotionality (`E`).

Objective danger, injury, relationships, current stress, and squad context
remain stronger situational inputs. Personality weights stay capped at 300.

## Morale and override pressure

Morale has no random probability roll. Events create deterministic stress
deltas. Recipient sensitivity is derived directly from HEXACO:

`resilience = (C + (1000 - E)) / 2`

Higher `E` increases emotional contagion and panic pressure; higher `C`
increases self-control and reduces them. Override burden uses the same derived
resilience and still includes grievance and gratitude.

## Schema and acceptance

- Party encounter schema v15 requires HEXACO for every companion.
- Exile summaries store `style_label`, `profile_hash`, and all six axes.
- Save/load preserves six-axis profiles exactly.
- Legacy session load regenerates profiles from the saved seed without mixing
  the old and new models.
- Unit, deterministic matrix, full regression, UI smoke, and web export checks
  must pass before merging to `main`.
