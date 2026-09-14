"""Deterministic authored low-poly hero, genuine armature and 64px Cycles renders.
Run: blender --background --python tools/art/build_rigged_pixel_hero.py -- --out PATH
No generated-image input, per-frame image editing or external dependencies.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Quaternion
from bpy_extras.object_utils import world_to_camera_view

parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True)
parser.add_argument('--limit', type=int, default=0)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
out = Path(args.out).resolve()
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    geometry = nodes.new('ShaderNodeNewGeometry')
    dot = nodes.new('ShaderNodeVectorMath'); dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = Vector((-.4, -.6, .7)).normalized()
    ramp = nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.interpolation = 'CONSTANT'
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    for i, (position, shade) in enumerate([(0, .40), (.25, .70), (.65, 1.0)]):
        stop = ramp.color_ramp.elements[0] if i == 0 else ramp.color_ramp.elements.new(position)
        stop.position = position
        stop.color = (*(c*shade for c in rgb), 1)
    emission = nodes.new('ShaderNodeEmission')
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(geometry.outputs['Normal'], dot.inputs[0])
    links.new(dot.outputs['Value'], ramp.inputs[0])
    links.new(ramp.outputs['Color'], emission.inputs['Color'])
    links.new(emission.outputs[0], output.inputs['Surface'])
    return mat

mats = {name: material(name, rgb) for name, rgb in {
    'skin': (.62, .34, .16), 'skin_light': (.83, .53, .29),
    'hair': (.065, .035, .024), 'hair_high': (.12, .065, .035),
    'cloth': (.025, .18, .20), 'cloth_dark': (.018, .09, .11),
    'pants': (.035, .045, .055), 'leather': (.14, .065, .027),
    'steel': (.30, .38, .43), 'steel_edge': (.56, .65, .69),
    'gold': (.55, .34, .095), 'eyes': (.008, .012, .016),
}.items()}

arm = bpy.data.armatures.new('HeroSkeleton')
rig = bpy.data.objects.new('HeroRig', arm)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bone_defs = {
    'root': ((0, 0, 0), (0, 0, .2), None),
    'hips': ((0, 0, .66), (0, 0, .82), 'root'),
    'torso': ((0, 0, .82), (0, 0, 1.22), 'hips'),
    'head': ((0, 0, 1.22), (0, 0, 1.60), 'torso'),
}
for side, s in [('R', -1), ('L', 1)]:
    bone_defs.update({
        'upper_arm.'+side: ((s*.29, 0, 1.16), (s*.33, 0, .92), 'torso'),
        'forearm.'+side: ((s*.33, 0, .92), (s*.34, 0, .70), 'upper_arm.'+side),
        'hand.'+side: ((s*.34, 0, .70), (s*.34, 0, .62), 'forearm.'+side),
        'thigh.'+side: ((s*.14, 0, .68), (s*.14, 0, .39), 'hips'),
        'shin.'+side: ((s*.14, 0, .39), (s*.14, 0, .13), 'thigh.'+side),
        'foot.'+side: ((s*.14, 0, .13), (s*.14, -.17, .09), 'shin.'+side),
    })
for name, (head, tail, parent) in bone_defs.items():
    bone = arm.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    if parent: bone.parent = arm.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
rig.show_in_front = True
gear, body = [], []

def bind(obj, name, bone, mat, equipped=False):
    obj.name = name
    obj.data.materials.append(mats[mat])
    # Mesh vertices are authored in the rig rest coordinates. Rigid weights keep
    # the coarse segment shapes; every segment still uses the actual armature.
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    mod = obj.modifiers.new('Skeleton deformation', 'ARMATURE')
    mod.object = rig
    (gear if equipped else body).append(obj)
    return obj

def box(name, loc, dims, bone, mat, bevel=.025, equipped=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Large pixel-friendly chamfers', 'BEVEL')
        mod.width, mod.segments = bevel, 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return bind(obj, name, bone, mat, equipped)

box('Tunic', (0, 0, 1.0), (.48, .29, .46), 'torso', 'cloth', .055)
box('Tunic hem', (0, 0, .77), (.48, .32, .13), 'hips', 'cloth_dark')
box('Belt', (0, -.015, .82), (.49, .33, .07), 'hips', 'leather', .01)
box('Buckle', (0, -.19, .82), (.085, .04, .065), 'hips', 'gold', .005)
box('Neck', (0, 0, 1.26), (.15, .15, .13), 'head', 'skin')
box('Face', (0, -.01, 1.48), (.41, .36, .39), 'head', 'skin_light', .065)
box('Nose', (0, -.206, 1.44), (.065, .065, .075), 'head', 'skin', .012)
box('Hair cap', (0, .015, 1.65), (.45, .38, .16), 'head', 'hair', .04)
box('Hair back', (0, .16, 1.52), (.40, .12, .26), 'head', 'hair', .035)
for x, z, w in [(-.15, 1.58, .12), (-.055, 1.62, .13), (.065, 1.60, .14), (.165, 1.56, .10)]:
    box('Hair fringe', (x, -.18, z), (w, .10, .15), 'head', 'hair_high' if x < -.1 else 'hair', .016)
for x in [-.11, .11]:
    box('Eye', (x, -.195, 1.47), (.055, .016, .048), 'head', 'eyes', 0)
for side, s in [('R', -1), ('L', 1)]:
    box('Sleeve.'+side, (s*.30, 0, 1.055), (.19, .24, .27), 'upper_arm.'+side, 'cloth', .03)
    box('Forearm.'+side, (s*.335, 0, .81), (.15, .19, .23), 'forearm.'+side, 'skin')
    box('Hand.'+side, (s*.34, -.01, .665), (.16, .18, .12), 'hand.'+side, 'skin_light')
    box('Upper leg.'+side, (s*.14, 0, .53), (.20, .24, .28), 'thigh.'+side, 'pants')
    box('Lower leg.'+side, (s*.14, 0, .26), (.16, .20, .27), 'shin.'+side, 'pants')
    box('Boot.'+side, (s*.14, -.065, .095), (.21, .35, .18), 'foot.'+side, 'leather')
    box('Pauldron.'+side, (s*.30, 0, 1.16), (.24, .29, .16), 'upper_arm.'+side, 'steel', .045, True)
box('Breastplate', (0, -.035, 1.035), (.50, .33, .34), 'torso', 'steel', .05, True)
box('Breastplate trim', (0, -.217, .90), (.39, .035, .055), 'torso', 'gold', .005, True)
box('Sword grip', (-.34, -.025, .64), (.055, .07, .16), 'hand.R', 'leather', .005, True)
box('Sword guard', (-.34, -.025, .54), (.24, .06, .045), 'hand.R', 'gold', .007, True)
box('Sword blade', (-.34, -.025, .28), (.085, .032, .48), 'hand.R', 'steel_edge', .01, True)
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=.235, depth=.065, location=(.35, -.14, .83), rotation=(math.pi/2, 0, 0))
bind(bpy.context.object, 'Shield', 'forearm.L', 'leather', True)
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=.075, depth=.09, location=(.35, -.185, .83), rotation=(math.pi/2, 0, 0))
bind(bpy.context.object, 'Shield boss', 'forearm.L', 'steel', True)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.cycles.use_denoising = False
scene.render.threads_mode = 'FIXED'
scene.render.threads = 4
scene.render.resolution_x = scene.render.resolution_y = 64
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.render.filter_size = .01
scene.view_settings.view_transform = 'Standard'
scene.world.color = (.35, .35, .35)
bpy.ops.object.camera_add(location=(6, -6, .97+4.899))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, .97))-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type, camera.data.ortho_scale = 'ORTHO', 2.25
scene.camera = camera
for loc, energy, size in [((-3, -4, 7), 450, 4), ((4, 1, 4), 220, 5)]:
    bpy.ops.object.light_add(type='AREA', location=loc)
    lamp = bpy.context.object
    lamp.data.energy, lamp.data.shape, lamp.data.size = energy, 'DISK', size
    lamp.rotation_euler = (Vector((0, 0, 1))-lamp.location).to_track_quat('-Z', 'Y').to_euler()

def rotate(name, angle, axis='X'):
    bone = rig.pose.bones[name]
    basis = arm.bones[name].matrix_local.to_quaternion()
    bone.rotation_mode = 'QUATERNION'
    axis_vector = {'X': (1, 0, 0), 'Y': (0, 1, 0), 'Z': (0, 0, 1)}[axis]
    bone.rotation_quaternion = basis.inverted() @ Quaternion(axis_vector, angle) @ basis

def pose(direction, frame):
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion = Quaternion()
        bone.location = (0, 0, 0)
    rotate('root', math.radians([180, 90, 0, -90][direction]), 'Z')
    if 1 <= frame <= 4:
        phase = (frame-1)*math.pi/2
        for side, sign in [('R', 1), ('L', -1)]:
            swing = math.sin(phase)*sign
            rotate('thigh.'+side, swing*.42)
            rotate('shin.'+side, -.28*max(0, swing))
            rotate('upper_arm.'+side, -swing*.32)
            rotate('forearm.'+side, -.12)
    elif frame >= 5:
        # Ready -> strike -> follow-through -> recovery. Same rig, no extra arm.
        upper = [-.45, -1.50, -1.24, -.40][frame-5]
        elbow = [-.55, -.06, -.22, -.30][frame-5]
        rotate('upper_arm.R', upper)
        rotate('forearm.R', elbow)
        rotate('upper_arm.L', -.35)
        rotate('torso', [0, -.12, -.07, 0][frame-5], 'Y')
    bpy.context.view_layer.update()

def projected(v):
    p = world_to_camera_view(scene, camera, v)
    return [round(p.x*64, 3), round((1-p.y)*64, 3)]

manifest = {'version': 1, 'frame_size': [64, 64], 'anchor': projected(Vector((0, 0, 0))),
 'directions': ['NE', 'SE', 'SW', 'NW'], 'actions': {'idle': [0], 'walk': [1, 2, 3, 4], 'attack': [5, 6, 7, 8]},
 'variants': ['base', 'equipped'], 'frames': [], 'bones': list(bone_defs),
 'equipment_bones': {obj.name: obj.vertex_groups[0].name for obj in gear}}
rendered = 0
for direction in range(4):
    for frame in range(9):
        pose(direction, frame)
        for bone in rig.pose.bones:
            bone.keyframe_insert('rotation_quaternion', frame=direction*9+frame+1)
        # Render evaluates the scene's current animation time. Without this it
        # silently restores frame 1 even though the in-memory pose was updated.
        scene.frame_set(direction*9+frame+1)
        bpy.context.view_layer.update()
        joints = [[projected(rig.matrix_world @ b.head), projected(rig.matrix_world @ b.tail)] for b in rig.pose.bones if b.name != 'root']
        for variant in manifest['variants']:
            for obj in gear: obj.hide_render = variant == 'base'
            name = f'{variant}-{direction}-{frame}.png'
            scene.render.filepath = str(out / name)
            bpy.ops.render.render(write_still=True)
            manifest['frames'].append({'variant': variant, 'direction': direction, 'frame': frame, 'file': name, 'joints': joints})
            rendered += 1
            print('RIG_FRAME', rendered, name, flush=True)
            if args.limit and rendered >= args.limit: break
        if args.limit and rendered >= args.limit: break
    if args.limit and rendered >= args.limit: break
pose(1, 0)
for obj in gear: obj.hide_render = False
scene.frame_start, scene.frame_end = 1, 36
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'hero-rig.blend'), compress=True)
(out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
(out / 'manifest.js').write_text('globalThis.RiggedHeroManifest = '+json.dumps(manifest, separators=(',', ':'))+';\n', encoding='utf-8')
print('RIG_BUILD_COMPLETE', rendered, flush=True)
