# Battleheart migration fixture

`battleheart_schema22_combat.json` is a genuine pre-active-skill save generated
from the Web pack exported at commit `3ae72d8`, not a current snapshot with fields
deleted. It uses `REGRESSION_V1`, world seed `44`, personality seed `20260828`.

The old public session APIs executed one exploration wait, WEDGE deployment,
and three autonomous party turns (five journal entries total). The same old
packed code successfully loaded the resulting save before it was copied here.
Party schema is 22; no active-skill energy or loadout fields are present.

This small fixture supports the local `battleheart_mvp_acceptance.gd` migration
case. It does not add a GitHub Actions simulation job.
