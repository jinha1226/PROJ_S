"""Render key poses from CMU 02_07 swordplay as a skinned joint mannequin."""

from __future__ import annotations

import math
import json
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BVH_PATH = PROJECT_ROOT / "assets" / "mocap" / "cmu" / "02_07_swordplay.bvh"
OUTPUT_DIR = PROJECT_ROOT / "previews" / "mocap_swordplay_frames"
ASSET_DIR = PROJECT_ROOT / "assets" / "duel3d"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
ASSET_DIR.mkdir(parents=True, exist_ok=True)
FRAMES = (1320, 1360, 1400, 1440, 1465, 1490, 1530, 1570, 1610)
CLIP_START = 1320
CLIP_END = 1610
SOURCE_STEP = 4  # 120 fps source -> 30 fps game clip.

JOINT_SOURCES = (
    ("hips", "Hips", False),
    ("spine", "Spine", False),
    ("chest", "Spine1", False),
    ("neck", "Neck1", False),
    ("head", "Head", False),
    ("head_top", "Head", True),
    ("left_shoulder", "LeftArm", False),
    ("left_elbow", "LeftForeArm", False),
    ("left_wrist", "LeftFingerBase", False),
    ("left_hand", "LeftHandIndex1", True),
    ("right_shoulder", "RightArm", False),
    ("right_elbow", "RightForeArm", False),
    ("right_wrist", "RightFingerBase", False),
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

BONE_LINKS = (
    ("hips", "spine", "body"), ("spine", "chest", "body"),
    ("chest", "neck", "body"), ("neck", "head", "body"),
    ("head", "head_top", "body"),
    ("chest", "left_shoulder", "body"), ("left_shoulder", "left_elbow", "body"),
    ("left_elbow", "left_wrist", "body"), ("left_wrist", "left_hand", "body"),
    ("chest", "right_shoulder", "body"), ("right_shoulder", "right_elbow", "body"),
    ("right_elbow", "right_wrist", "body"), ("right_wrist", "right_hand", "body"),
    ("hips", "left_hip", "body"), ("left_hip", "left_knee", "body"),
    ("left_knee", "left_ankle", "body"), ("left_ankle", "left_toe", "body"),
    ("hips", "right_hip", "body"), ("right_hip", "right_knee", "body"),
    ("right_knee", "right_ankle", "body"), ("right_ankle", "right_toe", "body"),
    ("right_hand", "sword_tip", "weapon"),
)

VISIBLE_BONES = (
    "Hips", "LowerBack", "Spine", "Spine1", "Neck1", "Head",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
    "LeftArm", "LeftForeArm", "LeftFingerBase", "LeftHandIndex1",
    "RightArm", "RightForeArm", "RightFingerBase", "RightHandIndex1",
)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def material(name: str, color: tuple[float, float, float, float], emission: float = 0.0) -> bpy.types.Material:
    result = bpy.data.materials.new(name)
    result.diffuse_color = color
    result.use_nodes = True
    node = result.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = color
    node.inputs["Roughness"].default_value = 0.58
    if emission:
        node.inputs["Emission Color"].default_value = color
        node.inputs["Emission Strength"].default_value = emission
    return result


def bind_rigid(obj: bpy.types.Object, rig: bpy.types.Object, bone_name: str) -> None:
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = rig
    obj.parent = rig


def cylinder_between(name: str, start: Vector, end: Vector, radius: float, mat: bpy.types.Material, rig: bpy.types.Object, bone_name: str) -> None:
    direction = end - start
    if direction.length < 0.015:
        return
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=radius, depth=direction.length, location=(start + end) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bind_rigid(obj, rig, bone_name)


def sphere_at(name: str, point: Vector, radius: float, mat: bpy.types.Material, rig: bpy.types.Object, bone_name: str) -> None:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=point)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bind_rigid(obj, rig, bone_name)


def make_mannequin(rig: bpy.types.Object) -> None:
    body = material("MocapBody", (0.035, 0.40, 0.52, 1.0), 0.18)
    joints = material("MocapJoints", (0.35, 0.90, 1.0, 1.0), 0.45)
    blade = material("TrainingBlade", (1.0, 0.36, 0.08, 1.0), 0.75)
    for bone_name in VISIBLE_BONES:
        bone = rig.data.bones.get(bone_name)
        if bone is None:
            continue
        start = bone.head_local.copy()
        end = bone.tail_local.copy()
        radius = 0.045 if any(token in bone_name for token in ("Leg", "UpLeg", "Spine", "Back")) else 0.035
        cylinder_between(f"Body_{bone_name}", start, end, radius, body, rig, bone_name)
        sphere_at(f"Joint_{bone_name}", start, radius * 1.35, joints, rig, bone_name)

    # The right index chain has the most stable hand-facing axis in the CMU rig.
    hand = rig.data.bones["RightHandIndex1"]
    direction = (hand.tail_local - hand.head_local).normalized()
    sword_start = hand.head_local - direction * 0.08
    sword_end = hand.tail_local + direction * 0.85
    cylinder_between("MotionSword", sword_start, sword_end, 0.024, blade, rig, "RightHandIndex1")


def setup_scene(rig: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 480
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.008, 0.012, 0.025)

    hip_positions = []
    foot_heights = []
    for frame in FRAMES:
        scene.frame_set(frame)
        hip_positions.append(rig.matrix_world @ rig.pose.bones["Hips"].matrix.translation)
        foot_heights.extend([
            (rig.matrix_world @ rig.pose.bones["LeftFoot"].matrix.translation).z,
            (rig.matrix_world @ rig.pose.bones["RightFoot"].matrix.translation).z,
        ])
    center = sum(hip_positions, Vector()) / len(hip_positions)
    floor_z = min(foot_heights) - 0.04

    floor_mat = material("Floor", (0.025, 0.040, 0.060, 1.0))
    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(center.x, center.y, floor_z))
    bpy.context.object.data.materials.append(floor_mat)

    bpy.ops.object.light_add(type="AREA", location=center + Vector((-3.0, -4.0, 5.0)))
    key = bpy.context.object
    key.data.energy = 900
    key.data.color = (0.38, 0.68, 1.0)
    key.data.size = 5.0
    key.rotation_euler = (math.radians(28), 0, math.radians(-30))
    bpy.ops.object.light_add(type="AREA", location=center + Vector((3.0, 1.0, 3.0)))
    rim = bpy.context.object
    rim.data.energy = 700
    rim.data.color = (1.0, 0.20, 0.05)
    rim.data.size = 3.0

    bpy.ops.object.camera_add(location=center + Vector((3.8, -6.4, 1.7)))
    camera = bpy.context.object
    target = center + Vector((0, 0, 0.2))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 58
    scene.camera = camera


def bake_game_clip(rig: bpy.types.Object) -> bpy.types.Action:
    scene = bpy.context.scene
    source_action = rig.animation_data.action
    samples: list[dict[str, object]] = []
    for source_frame in range(CLIP_START, CLIP_END + 1, SOURCE_STEP):
        scene.frame_set(source_frame)
        samples.append({bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones})

    baked = bpy.data.actions.new("SwordplayCombo")
    baked.use_fake_user = True
    rig.animation_data.action = baked
    for output_frame, sample in enumerate(samples, start=1):
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            bone.matrix_basis = sample[bone.name]
            bone.keyframe_insert("location", frame=output_frame, group=bone.name)
            bone.keyframe_insert("rotation_quaternion", frame=output_frame, group=bone.name)
            bone.keyframe_insert("scale", frame=output_frame, group=bone.name)
    for curve in baked.fcurves:
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
    if source_action is not None:
        source_action.use_fake_user = False
        bpy.data.actions.remove(source_action)
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = len(samples)
    scene.frame_set(1)
    return baked


def export_joint_clip(rig: bpy.types.Object) -> None:
    scene = bpy.context.scene
    names = [entry[0] for entry in JOINT_SOURCES] + ["sword_tip"]
    raw_frames: list[list[Vector]] = []
    floor_height = float("inf")
    for source_frame in range(CLIP_START, CLIP_END + 1, SOURCE_STEP):
        scene.frame_set(source_frame)
        points: list[Vector] = []
        for _, bone_name, use_tail in JOINT_SOURCES:
            pose_bone = rig.pose.bones[bone_name]
            point = pose_bone.tail.copy() if use_tail else pose_bone.head.copy()
            points.append(point)
        right_hand = points[names.index("right_hand")]
        right_wrist = points[names.index("right_wrist")]
        direction = (right_hand - right_wrist).normalized()
        points.append(right_hand + direction * 0.90)
        raw_frames.append(points)
        floor_height = min(
            floor_height,
            points[names.index("left_ankle")].z,
            points[names.index("left_toe")].z,
            points[names.index("right_ankle")].z,
            points[names.index("right_toe")].z,
        )

    origin = raw_frames[0][names.index("hips")]
    frames: list[list[list[float]]] = []
    for points in raw_frames:
        converted = []
        for point in points:
            # Blender Z-up to Godot Y-up. Preserve horizontal root motion.
            converted.append([
                round(point.x - origin.x, 5),
                round(point.z - floor_height, 5),
                round(-(point.y - origin.y), 5),
            ])
        frames.append(converted)

    payload = {
        "source": "CMU Graphics Lab Motion Capture Database 02_07 swordplay",
        "fps": 30,
        "joints": names,
        "bones": [{"a": a, "b": b, "kind": kind} for a, b, kind in BONE_LINKS],
        "frames": frames,
    }
    output_path = PROJECT_ROOT / "assets" / "mocap" / "cmu" / "02_07_swordplay_game.json"
    output_path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    print(f"Exported joint clip to {output_path}")


def export_game_asset(rig: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for child in rig.children_recursive:
        if child.type == "MESH":
            child.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(ASSET_DIR / "cmu_swordplay_mannequin.glb"),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
        export_skins=True,
        export_def_bones=True,
        export_all_influences=False,
        export_influence_nb=4,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_apply=True,
        export_yup=True,
    )
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET_DIR / "cmu_swordplay_source.blend"))


def main() -> None:
    clear_scene()
    bpy.ops.preferences.addon_enable(module="io_anim_bvh")
    bpy.ops.import_anim.bvh(
        filepath=str(BVH_PATH),
        global_scale=0.1,
        frame_start=1,
        use_fps_scale=False,
        update_scene_fps=True,
        rotate_mode="NATIVE",
    )
    rig = bpy.context.object
    rig.name = "CMU_Swordplay_Rig"
    make_mannequin(rig)
    setup_scene(rig)
    scene = bpy.context.scene
    for index, frame in enumerate(FRAMES):
        scene.frame_set(frame)
        scene.render.filepath = str(OUTPUT_DIR / f"pose_{index:02d}_{frame}.png")
        bpy.ops.render.render(write_still=True)
    export_joint_clip(rig)
    bake_game_clip(rig)
    export_game_asset(rig)
    print(f"Rendered {len(FRAMES)} poses to {OUTPUT_DIR}")
    print(f"Exported game clip to {ASSET_DIR / 'cmu_swordplay_mannequin.glb'}")


if __name__ == "__main__":
    main()
