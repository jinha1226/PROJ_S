# Floor 2 pixel terrain source

Built-in imagegen. 4x4 row-major: ash,rustDust,basaltA,basaltB; wood,metal,slag,water; ironWall,basaltWall,machine,soot; inactivePortal,activePortal,brazier,vent.
Source texture requires mechanical extraction into logical24 cells and palette simplification. Border strokes in this source must be considered during crop selection so ordinary floor repetition does not create an unintended heavy grid. Wall cells8/9 intentionally have solid centers and light top edges.

Create one square 4x4 atlas of 16 equal TOP-DOWN low-resolution pixel terrain tiles for a mobile dungeon game. Absolutely flat vertical overhead camera. No gaps, no labels, no borders. Each cell is a single logical24x24 tile enlarged, broad crisp square pixel clusters, 6-10colors per tile, subdued dark palette, no fine noise or antialiased illustration.
Biome: abandoned ash-gray foundry built by an ancient civilization, rust iron, cold blue drainage, a little amber energy. Normal ground is QUIET and low contrast behind bright small characters. No diagonal paths or decorative roads in ordinary floor tiles. All tile edges fill cells with repeatable texture; not individual 3D cubes.
Row1: quiet charcoal ash earth; sparse dull rusty dust on ash; large basalt gray floor slabs; second quiet basalt slab variant.
Row2: old blackened wood planks; plain rusty iron floor plates; sparse pale slag rubble on ash; flat dark blue water with one or two broad ripple strokes.
Row3: a completely SOLID DARK iron blocking wall top with ONE bright narrow edge; a completely SOLID dark basalt blocking wall top with a narrow silver rim; overhead dark machine block with one dull brass circular cap; plain soot-black packed ground.
Row4: inactive circular metal portal on basalt floor; active circular amber portal on the same floor; tiny overhead orange brazier on ash; simple dark ventilation grille on metal.
IMPORTANT wall cells are filled solid masses, NOT hollow squares, holes, wells, doors, chests or circular frames. Floor tiles lighter than wall centers, wall edge gives clear boundary. No perspective showing vertical front walls, no isometric, no characters, no UI, no text, no tiny cables or bolts.

