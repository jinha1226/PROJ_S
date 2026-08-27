"""Convert CMU 02_03 run/jog BVH into a compact side-view joint clip."""

from __future__ import annotations

import json
from pathlib import Path

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT_ROOT / "assets" / "mocap" / "cmu" / "02_03_run.bvh"
OUTPUT = PROJECT_ROOT / "assets" / "mocap" / "cmu" / "02_03_run_2d.json"
# One clean stride loop. Source frames 118 and 26 are near-identical poses;
# stop one sample before the duplicate so runtime interpolation stays smooth.
START_FRAME = 26
END_FRAME = 114
SOURCE_STEP = 4

JOINTS = (
    ("hips", "Hips", False),
    ("chest", "Spine1", False),
    ("head", "Head", True),
    ("left_shoulder", "LeftArm", False),
    ("left_elbow", "LeftForeArm", False),
    ("left_hand", "LeftHandIndex1", True),
    ("right_shoulder", "RightArm", False),
    ("right_elbow", "RightForeArm", False),
    ("right_hand", "RightHandIndex1", True),
    ("left_hip", "LeftUpLeg", False),
    ("left_knee", "LeftLeg", False),
    ("left_ankle", "LeftFoot", False),
    ("left_toe", "LeftToeBase", True),
    ("right_hip", "RightUpLeg", False),
    ("right_knee", "RightLeg", False),
    ("right_ankle", "RightFoot", False),
    ("right_toe", "RightToeBase", True),
)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def main() -> None:
    clear_scene()
    bpy.ops.preferences.addon_enable(module="io_anim_bvh")
    bpy.ops.import_anim.bvh(
        filepath=str(SOURCE),
        global_scale=0.1,
        frame_start=1,
        use_fps_scale=False,
        update_scene_fps=True,
        rotate_mode="NATIVE",
    )
    rig = bpy.context.object
    scene = bpy.context.scene
    frames = []
    root_forward = []
    hips_height = []
    floor_height = float("inf")
    names = [entry[0] for entry in JOINTS]

    for frame_number in range(START_FRAME, END_FRAME + 1, SOURCE_STEP):
        scene.frame_set(frame_number)
        hips = rig.pose.bones["Hips"].head.copy()
        pose = []
        for _, bone_name, use_tail in JOINTS:
            bone = rig.pose.bones[bone_name]
            point = bone.tail.copy() if use_tail else bone.head.copy()
            # The performer travels along Blender -Y. Remove root translation so
            # the game can control speed while retaining vertical weight shift.
            pose.append([
                round(-(point.y - hips.y), 5),
                round(point.z - hips.z, 5),
            ])
        frames.append(pose)
        root_forward.append(round(-hips.y, 5))
        hips_height.append(hips.z)
        floor_height = min(
            floor_height,
            rig.pose.bones["LeftFoot"].head.z,
            rig.pose.bones["LeftToeBase"].tail.z,
            rig.pose.bones["RightFoot"].head.z,
            rig.pose.bones["RightToeBase"].tail.z,
        )

    payload = {
        "source": "CMU Graphics Lab Motion Capture Database 02_03 run/jog",
        "fps": 30,
        "joints": names,
        "root_forward": root_forward,
        "root_height": [round(value - floor_height, 5) for value in hips_height],
        "frames": frames,
    }
    OUTPUT.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    print(f"Exported {len(frames)} side-view frames to {OUTPUT}")


if __name__ == "__main__":
    main()
