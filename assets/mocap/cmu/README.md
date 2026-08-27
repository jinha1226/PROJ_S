# CMU swordplay motion spike

This spike uses `02_07` (swordplay) from the Carnegie Mellon University
Graphics Lab Motion Capture Database.

The side-view runner prototype also uses `02_03` (run/jog). Its raw BVH is
stored as `02_03_run.bvh`; `02_03_run_2d.json` contains one clean 23-frame
stride loop sampled at 30 fps. Rebuild it with
`tools/blender/export_cmu_run_2d.py`.

- Original source: <https://mocap.cs.cmu.edu/>
- BVH conversion mirror: <https://github.com/una-dinosauria/cmu-mocap>
- Runtime clip: `02_07_swordplay_game.json` (73 frames at 30 fps)
- Blender/Godot-ready reference: `../../duel3d/cmu_swordplay_mannequin.glb`
- Rebuild script: `../../../tools/blender/render_cmu_motion_sheet.py`

The source database permits copying, modification, redistribution, and use in
commercially sold products, but the raw data may not be resold directly,
including in converted form.

Acknowledgment:

> The data used in this project was obtained from mocap.cs.cmu.edu.
> The database was created with funding from NSF EIA-0196217.

The JSON joint stream is used only for the current skinless motion viewer. The
BVH/GLB motion remains the source of truth for retargeting a future character
skin.
