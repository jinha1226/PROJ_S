"""Read-only audit of generated .blend, run with Blender --python-exit-code 1."""
import bpy
import json
from pathlib import Path

path = Path(__file__).resolve().parents[1] / 'docs/art/handcrafted-stages/rigged-hero'
bpy.ops.wm.open_mainfile(filepath=str(path / 'hero-rig.blend'))
manifest = json.loads((path / 'manifest.json').read_text())
rig = bpy.data.objects['HeroRig']
assert rig.type == 'ARMATURE'
assert set(rig.data.bones.keys()) == set(manifest['bones'])
assert len(rig.data.bones) == 16
assert rig.animation_data and rig.animation_data.action
assert tuple(rig.animation_data.action.frame_range) == (1.0, 36.0)
for obj in [o for o in bpy.data.objects if o.type == 'MESH']:
    assert len(obj.vertex_groups) == 1, obj.name
    assert obj.vertex_groups[0].name in rig.data.bones
    assert all(len(v.groups) == 1 and v.groups[0].weight == 1 for v in obj.data.vertices)
    assert any(m.type == 'ARMATURE' and m.object == rig for m in obj.modifiers)
for name, bone in manifest['equipment_bones'].items():
    assert bpy.data.objects[name].vertex_groups[0].name == bone
assert manifest['equipment_bones']['Sword blade'] == 'hand.R'
assert manifest['equipment_bones']['Shield'] == 'forearm.L'
gear = [bpy.data.objects[name] for name in manifest['equipment_bones']]
body = [o for o in bpy.data.objects if o.type == 'MESH' and o not in gear]

def body_geometry():
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return tuple(tuple(tuple(v.co) for v in o.evaluated_get(depsgraph).data.vertices) for o in body)

head_positions = []
for frame in [1, 10, 16, 28, 36]:
    bpy.context.scene.frame_set(frame)
    head_positions.append(tuple(rig.pose.bones['hand.R'].tail))
    for obj in gear: obj.hide_render = True
    without = body_geometry()
    for obj in gear: obj.hide_render = False
    assert body_geometry() == without, 'equipment must not alter the base mesh or bone pose'
assert len(set(head_positions)) > 2, 'animation and direction must change actual bone coordinates'
print('RIGGED_HERO_BLEND PASS: 16 bones, rigid weights, 36 poses, hand attachments, invariant base geometry')
