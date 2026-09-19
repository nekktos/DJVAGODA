"""
Кузница четвероногих: волк и лошадь целиком из кода.

ЧЕМ ОТЛИЧАЕТСЯ ОТ ЛЮДСКОЙ. У зверя договор с игрой куда короче. Зон попадания
по костям у него нет — `unit.gd` вешает волку ОДНУ капсулу на всё тело («один
скиннутый меш, делить нечем»), расчленения нет тоже. Значит имена костей
свободны, и обязательны только анимации: волку `Idle` и `Walk`, лошади `Idle`.
`Run` делаем сверх: `model_anim.gd` умеет его попросить, а без него бегущий
волк шёл бы шагом.

ГАБАРИТ — ЧАСТЬ ДОГОВОРА, и единственная жёсткая его часть. Масштабы в игре
заданы под покупные модели: волк ужимается в 0.35 (`unit.gd::BEAST_MODEL_SCALE`),
лошадь в 0.45 (`horse.gd::MODEL_SCALE`). Свой зверь обязан быть того же размера
в единицах Blender, иначе в мире он окажется щенком или слоном, и править
придётся уже игру.

Запуск:
  blender --background --factory-startup --python tools/asset_forge/animal.py -- \
      --preset wolf --out godot_project/assets/animals/Wolf.glb
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Quaternion

sys.path.insert(0, str(Path(__file__).parent))
import character as forge  # noqa: E402  — цвет, фаска, запекание и рендер общие

# Обязательные анимации. Короче людского списка: зверю не нужны ни замах
# оружием, ни поза сидя.
REQUIRED_ACTIONS = ["Idle", "Walk", "Run", "Death"]

# Габариты покупных моделей, под которые посчитаны масштабы в игре.
# (длина, высота в холке, ширина корпуса)
PRESETS = {
    "wolf": {
        "length": 3.30, "withers": 2.05, "width": 0.95,
        "head": 1.25, "muzzle": 0.68, "leg": 0.23, "tail": 1.30,
        "ears": 0.34, "mane": False, "head_rise": 0.95,
        "fur": (0.52, 0.49, 0.47), "belly": (0.72, 0.69, 0.65),
        "dark": (0.16, 0.15, 0.15), "eye": (0.72, 0.55, 0.12),
    },
    "horse": {
        "length": 3.90, "withers": 3.05, "width": 1.25,
        "head": 1.35, "muzzle": 0.92, "leg": 0.27, "tail": 1.15,
        "ears": 0.26, "mane": True, "head_rise": 1.34,
        "fur": (0.52, 0.34, 0.20), "belly": (0.66, 0.47, 0.30),
        "dark": (0.14, 0.10, 0.07), "eye": (0.10, 0.08, 0.07),
    },
}

P = forge.P
S = forge.S


def build_armature(preset):
    """Скелет четвероногого. Имена свои: договора по ним у зверя нет."""
    back = preset["withers"] * 0.78        # высота линии спины
    half = preset["length"] / 2.0

    arm_data = bpy.data.armatures.new("AnimalArmature")
    arm_obj = bpy.data.objects.new("AnimalArmature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent is not None:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("Root", P(0, 0), P(0, back * 0.3))
    # Хребет идёт от крупа вперёд к холке: так поворот корпуса читается
    # естественно, а хвост остаётся на конце цепи, а не в её начале.
    bone("Spine", P(0, back, -half * 0.75), P(0, back, half * 0.10), "Root")
    bone("Chest", P(0, back, half * 0.10), P(0, back, half * 0.72), "Spine", True)
    bone("Neck", P(0, back, half * 0.72),
         P(0, preset["withers"] * preset["head_rise"], half * 1.02), "Chest", True)
    bone("Head", P(0, preset["withers"] * preset["head_rise"], half * 1.02),
         P(0, preset["withers"] * (preset["head_rise"] - 0.10),
           half * 1.02 + preset["muzzle"]), "Neck", True)
    bone("Tail", P(0, back, -half * 0.75),
         P(0, back * 0.55, -half * 0.75 - preset["tail"]), "Spine")

    knee = back * 0.45
    for side, sx in (("L", 1.0), ("R", -1.0)):
        x = sx * preset["width"] * 0.32
        for end, z, parent in (("F", half * 0.58, "Chest"), ("B", -half * 0.60, "Spine")):
            bone("UpperLeg.%s%s" % (end, side), P(x, back * 0.92, z),
                 P(x, knee, z), parent)
            bone("LowerLeg.%s%s" % (end, side), P(x, knee, z),
                 P(x, preset["leg"] * 0.6, z), "UpperLeg.%s%s" % (end, side), True)

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def build_mesh(preset, arm_obj):
    back = preset["withers"] * 0.78
    half = preset["length"] / 2.0
    w = preset["width"]

    verts, faces, groups = [], [], {}
    slots = []

    def part(bone_name, center, size, slot, taper=1.0):
        before = len(faces)
        forge.add_box(verts, faces, groups, bone_name, center, size, taper)
        slots.extend([slot] * (len(faces) - before))

    # 0 мех, 1 брюхо, 2 тёмное (копыта, нос, грива), 3 глаз
    body_h = back * 0.58
    part("Spine", P(0, back, -half * 0.33),
         S(w, body_h, half * 0.92), 0, taper=1.0)
    part("Chest", P(0, back + body_h * 0.04, half * 0.40),
         S(w * 1.08, body_h * 1.06, half * 0.78), 0, taper=1.0)
    # Брюхо светлее спины — у зверей так всегда, и силуэт от этого объёмнее.
    part("Spine", P(0, back - body_h * 0.42, -half * 0.20),
         S(w * 0.86, body_h * 0.30, half * 1.30), 1, taper=1.0)

    neck_len = half * 0.34
    top = preset["withers"] * preset["head_rise"]
    part("Neck", P(0, (back + top) / 2, half * 0.86),
         S(w * 0.62, top - back + neck_len * 0.5, neck_len), 0, taper=0.82)
    if preset.get("mane"):
        # Грива: узкая тёмная полоса по гребню шеи. Одна коробка, а лошадь
        # сразу перестаёт быть безликим телом.
        part("Neck", P(0, (back + top) / 2 + (top - back) * 0.12, half * 0.80),
             S(w * 0.24, top - back, neck_len * 0.55), 2, taper=0.7)

    head_z = half * 1.02
    head_y = preset["withers"] * preset["head_rise"] * 0.99
    part("Head", P(0, head_y, head_z + preset["head"] * 0.18),
         S(w * 0.52, preset["head"] * 0.62, preset["head"] * 0.78), 0, taper=0.9)
    part("Head", P(0, head_y - preset["head"] * 0.10,
                   head_z + preset["head"] * 0.5 + preset["muzzle"] * 0.4),
         S(w * 0.36, preset["head"] * 0.40, preset["muzzle"]), 0, taper=0.82)
    # Нос тёмный: единственная точка, по которой видно, где у зверя перед.
    part("Head", P(0, head_y - preset["head"] * 0.12,
                   head_z + preset["head"] * 0.5 + preset["muzzle"] * 0.92),
         S(w * 0.22, preset["head"] * 0.20, preset["muzzle"] * 0.16), 2)
    for ex in (-1.0, 1.0):
        part("Head", P(ex * w * 0.20, head_y + preset["head"] * 0.42, head_z),
             S(w * 0.16, preset["ears"], w * 0.12), 0, taper=0.4)
        part("Head", P(ex * w * 0.21, head_y + preset["head"] * 0.06,
                       head_z + preset["head"] * 0.38),
             S(w * 0.10, preset["head"] * 0.13, 0.04), 3)

    # Хвост двумя коленами со сносом вниз: одной горизонтальной коробкой он
    # торчал доской и читался как палка, приклеенная к крупу.
    part("Tail", P(0, back * 0.92, -half * 0.75 - preset["tail"] * 0.25),
         S(w * 0.30, w * 0.30, preset["tail"] * 0.55), 0, taper=0.8)
    part("Tail", P(0, back * 0.70, -half * 0.75 - preset["tail"] * 0.72),
         S(w * 0.24, w * 0.42, preset["tail"] * 0.55), 0, taper=0.6)

    knee = back * 0.45
    for side, sx in (("L", 1.0), ("R", -1.0)):
        x = sx * w * 0.32
        for end, z in (("F", half * 0.58), ("B", -half * 0.60)):
            upper = "UpperLeg.%s%s" % (end, side)
            lower = "LowerLeg.%s%s" % (end, side)
            part(upper, P(x, (back * 0.92 + knee) / 2, z),
                 S(preset["leg"] * 1.5, back * 0.92 - knee + forge.JOINT_OVERLAP * 2,
                   preset["leg"] * 1.6), 0, taper=1.25)
            part(lower, P(x, (knee + preset["leg"] * 0.6) / 2, z),
                 S(preset["leg"], knee - preset["leg"] * 0.6 + forge.JOINT_OVERLAP * 2,
                   preset["leg"] * 1.1), 0, taper=1.15)
            # Копыто или лапа — тёмное пятно внизу, по нему нога «стоит».
            part(lower, P(x, preset["leg"] * 0.45, z + preset["leg"] * 0.2),
                 S(preset["leg"] * 1.25, preset["leg"] * 0.9, preset["leg"] * 1.7), 2)

    mesh = bpy.data.meshes.new("Body")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Body", mesh)
    bpy.context.collection.objects.link(obj)

    for name, rgb in (("Fur", preset["fur"]), ("Belly", preset["belly"]),
                      ("Dark", preset["dark"]), ("Eye", preset["eye"])):
        obj.data.materials.append(forge.make_material(name, rgb))
    for i, slot in enumerate(slots):
        mesh.polygons[i].material_index = slot
    for poly in mesh.polygons:
        poly.use_smooth = False

    for bone_name, indices in groups.items():
        obj.vertex_groups.new(name=bone_name).add(indices, 1.0, "REPLACE")

    forge._bevel(obj)
    obj.parent = arm_obj
    obj.modifiers.new("Armature", "ARMATURE").object = arm_obj
    return obj


# --- движение ----------------------------------------------------------------

LEGS = ["UpperLeg.FL", "UpperLeg.FR", "UpperLeg.BL", "UpperLeg.BR",
        "LowerLeg.FL", "LowerLeg.FR", "LowerLeg.BL", "LowerLeg.BR"]
ALL = ["Root", "Spine", "Chest", "Neck", "Head", "Tail"] + LEGS


def _key(arm_obj, frame):
    for name in ALL:
        pb = arm_obj.pose.bones[name]
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if name == "Root":
            pb.keyframe_insert(data_path="location", frame=frame)


def anim_idle(arm_obj):
    forge.new_action(arm_obj, "Idle")
    for frame, sway in ((1, 0.0), (40, 1.5), (80, 0.0)):
        forge.clear_pose(arm_obj)
        forge.rot(arm_obj.pose.bones["Neck"], (1, 0, 0), sway)
        forge.rot(arm_obj.pose.bones["Head"], (1, 0, 0), -sway * 1.4)
        forge.rot(arm_obj.pose.bones["Tail"], (1, 0, 0), sway * 3.0)
        _key(arm_obj, frame)


def _gait(arm_obj, name, swing, knee, length, drop):
    """Шаг четвероногого: диагональные пары идут противофазой.

    Передняя левая ходит вместе с задней правой — иначе зверь не идёт, а
    прыгает как кролик, и это первое, что видно в движении.
    """
    forge.new_action(arm_obj, name)
    half = length // 2
    for step, sign in ((1, 1.0), (1 + half, -1.0), (1 + length, 1.0)):
        forge.clear_pose(arm_obj)
        pairs = (("FL", sign), ("BR", sign), ("FR", -sign), ("BL", -sign))
        for end, s in pairs:
            forge.rot(arm_obj.pose.bones["UpperLeg.%s" % end], (1, 0, 0), swing * s)
            forge.rot(arm_obj.pose.bones["LowerLeg.%s" % end], (1, 0, 0),
                      -knee * max(0.0, -s))
        forge.rot(arm_obj.pose.bones["Neck"], (1, 0, 0), -swing * 0.12)
        forge.rot(arm_obj.pose.bones["Tail"], (1, 0, 0), swing * 0.25 * sign)
        _key(arm_obj, step)
    for step in (1 + half // 2, 1 + half + half // 2):
        forge.clear_pose(arm_obj)
        arm_obj.pose.bones["Root"].location = Vector((0, drop, 0))
        arm_obj.pose.bones["Root"].keyframe_insert(data_path="location", frame=step)


def anim_walk(arm_obj):
    _gait(arm_obj, "Walk", swing=17.0, knee=22.0, length=34, drop=0.04)


def anim_run(arm_obj):
    _gait(arm_obj, "Run", swing=34.0, knee=46.0, length=20, drop=0.14)


def anim_death(arm_obj):
    forge.new_action(arm_obj, "Death")
    for frame, roll, drop, legs in ((1, 0.0, 0.0, 0.0), (10, 24.0, -0.18, 18.0),
                                    (24, 78.0, -0.62, 52.0), (34, 90.0, -0.78, 60.0)):
        forge.clear_pose(arm_obj)
        pb = arm_obj.pose.bones["Spine"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((0, 0, 1), math.radians(roll))
        forge.rot(arm_obj.pose.bones["Neck"], (1, 0, 0), -roll * 0.3)
        for leg in LEGS:
            forge.rot(arm_obj.pose.bones[leg], (1, 0, 0), legs)
        arm_obj.pose.bones["Root"].location = Vector((0, drop, 0))
        _key(arm_obj, frame)


def build_animations(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    arm_obj.animation_data_create()
    anim_idle(arm_obj)
    anim_walk(arm_obj)
    anim_run(arm_obj)
    anim_death(arm_obj)
    arm_obj.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")


def verify(arm_obj, body, preset):
    acts = {a.name for a in bpy.data.actions}
    lost = [n for n in REQUIRED_ACTIONS if n not in acts]
    if lost:
        raise SystemExit("нет обязательных анимаций: %s" % ", ".join(lost))
    for act in bpy.data.actions:
        for fc in forge.action_fcurves(act):
            if "scale" in fc.data_path:
                raise SystemExit("в анимации %s есть дорожка масштаба" % act.name)
    # Габарит — единственная жёсткая часть договора: масштабы в игре посчитаны
    # под покупные размеры, и промах здесь виден сразу, а исправляется в игре.
    #
    # Меряем ПО ВЕРШИНАМ, а не через `obj.dimensions`: последний берётся из
    # пересчитанной сцены, а сразу после сборки она ещё не пересчитана — первый
    # заход отчитался длиной 1.03 при настоящих 5.24 и уронил сборку на ровном
    # месте.
    xs = [v.co.x for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    if not (preset["length"] < size[1] < preset["length"] * 2.4):
        raise SystemExit("длина %.2f вне ожидаемого около %.2f"
                         % (size[1], preset["length"] * 1.6))
    return size


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", required=True, choices=sorted(PRESETS))
    ap.add_argument("--out", required=True)
    ap.add_argument("--render", default="")
    ap.add_argument("--bake", action="store_true")
    args = ap.parse_args(argv)

    preset = PRESETS[args.preset]
    forge.clear_scene()
    arm_obj = build_armature(preset)
    body = build_mesh(preset, arm_obj)
    build_animations(arm_obj)
    if args.bake:
        forge.bake_texture(body, args.preset)
    size = verify(arm_obj, body, preset)

    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB",
                              export_animation_mode="ACTIONS", export_yup=True,
                              export_apply=False, use_selection=False)

    if args.render:
        outdir = Path(args.render)
        outdir.mkdir(parents=True, exist_ok=True)
        cam = forge.setup_render(512)
        target = (0.0, 0.0, preset["withers"] * 0.55)
        reach = preset["length"] * 3.6
        forge.shoot(cam, target, (-reach * 0.7, -reach * 0.8, reach * 0.35),
                    outdir / ("%s_три_четверти.png" % args.preset))
        forge.shoot(cam, target, (reach, 0.0, reach * 0.2),
                    outdir / ("%s_сбоку.png" % args.preset))
        print("FORGE_SHOTS %s" % outdir)

    print("FORGE_OK %s габарит %.2f x %.2f x %.2f анимаций=%d" % (
        out, size[0], size[1], size[2], len(bpy.data.actions)))


if __name__ == "__main__":
    main()
