"""
Кузница персонажей: модель, скелет и анимации — целиком из кода.

ЗАЧЕМ. Чужие паки дают готовое, но чужое: у Quaternius Ranger нет ни одной
анимации замаха оружием, и эльф махал невидимо. Своего персонажа можно править
там, где он не устраивает, а не искать пак, где это уже сделали.

ГЛАВНОЕ ПРАВИЛО. Персонаж обязан быть ЗАМЕНОЙ, а не отдельной веткой: кости
зовутся ровно так, как их ищет `godot_project/scripts/combat/rig.gd`, а
анимации — так, как их переводит `godot_project/scripts/model_anim.gd`. Тогда
зоны попадания, расчленение (схлопывание кости) и хват оружия работают на нём
без единой правки в игре. Разойтись этим двум спискам нельзя — см. проверку
`tools/asset_forge/check_contract.py`.

МАСШТАБ ТОЖЕ ЧАСТЬ ДОГОВОРА. Радиусы зон в `rig.gd` подобраны по позе покоя
Quaternius: голова на 2.10, торс 1.54, бедро 1.01, колено 0.60. Поэтому кости
ставятся на те же высоты — иначе шары зон повиснут мимо тела.

МАСШТАБА В АНИМАЦИЯХ НЕТ НАМЕРЕННО. `rig.gd` отрывает конечность, схлопывая
кость в ноль, и это работает ровно потому, что дорожек масштаба в анимациях нет
ни одной: масштаб — единственный канал позы, который никто, кроме игры, не
трогает. Здесь мы пишем только вращение и смещение корня. Добавишь scale —
сломаешь расчленение.

Запуск:
  blender --background --factory-startup --python tools/asset_forge/character.py -- \
      --name Elf --preset elf --out godot_project/assets/people/Elf.glb
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Quaternion

# --- договор с игрой ---------------------------------------------------------

# Высоты костей в позе покоя. Менять только вместе с ZONE_BONES в rig.gd.
HEIGHTS = {
    "foot": 0.08,
    "knee": 0.60,
    "hip": 1.01,
    "torso": 1.54,
    "neck": 1.85,
    "head": 2.10,
    "shoulder": 1.72,
    "elbow": 1.36,
    "fist": 1.05,
}

# Обязательные кости: без любой из них игра потеряет зону попадания или хват.
REQUIRED_BONES = [
    "Hips", "Torso", "Head",
    "UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R",
    "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R",
    "Weapon.R",
]

# Обязательные анимации: имена ровно те, что знает model_anim.gd::SYNONYMS.
REQUIRED_ACTIONS = [
    "Idle", "Walk", "Run", "Sword_Attack", "Death",
    # Этих в паках нет или они там не те. «Sit» — самая нужная: игра играет её
    # безногому, а Quaternius подставлял ему стойку смирно.
    #
    # Боевой стойки здесь НЕТ намеренно, хотя нарисовать её просто: персонаж в
    # этой игре всегда с оружием в руках, состояния «в бою / не в бою» не
    # существует, и попросить её неоткуда. Анимация, которую нечем вызвать, —
    # мёртвый груз; заводить её надо вместе с тем, что её включает.
    "Bow_Shoot", "RecieveHit", "Sit",
]


# --- пресеты сторон ----------------------------------------------------------
#
# Пресет — это НЕ новая модель, а набор чисел к одной и той же. Ради этого
# конвейер и пишется: эльф отличается от стража ростом, шириной плеч и цветом,
# а не отдельным файлом, который потом расходится с остальными.

PRESETS = {
    # ЦВЕТА НАСЫЩЕННЫЕ И ТЁМНЫЕ НАМЕРЕННО. Первый набор был выцветшим, и в игре
    # это увидели сразу: на ярком зелёном поле персонаж читался как бледный
    # призрак, а светлые волосы сливались с кожей и голова выглядела голым
    # белым кубом. Свет на карте яркий — базовый цвет обязан быть темнее, чем
    # кажется правильным в редакторе.
    #
    # Второе правило: кожа, волосы и одежда обязаны РАЗЛИЧАТЬСЯ по светлоте, а
    # не только по оттенку. Блондин с телесной кожей — это один силуэт без лица.
    "villain": {
        "height": 1.04, "shoulders": 1.06, "limb": 0.98,
        "skin": (0.58, 0.52, 0.52), "cloth": (0.10, 0.09, 0.13),
        "trim": (0.36, 0.08, 0.11), "hair": (0.07, 0.06, 0.08),
        "cloak": True, "long_hair": False, "pauldrons": True, "ears": 0.02,
    },
    "elf": {
        "height": 1.00, "shoulders": 0.92, "limb": 0.85,
        "skin": (0.70, 0.54, 0.40), "cloth": (0.12, 0.26, 0.15),
        "trim": (0.33, 0.22, 0.11), "hair": (0.55, 0.32, 0.14),
        "cloak": True, "long_hair": True, "pauldrons": False,
        "ears": 0.075,   # длинные уши: единственная деталь, делающая эльфа эльфом
    },
    "guard": {
        "height": 1.02, "shoulders": 1.14, "limb": 1.05,
        "skin": (0.66, 0.48, 0.36), "cloth": (0.19, 0.21, 0.27),
        "trim": (0.52, 0.54, 0.60), "hair": (0.16, 0.12, 0.09),
        "cloak": False, "long_hair": False, "pauldrons": True, "ears": 0.02,
    },
    # --- пешки: их видно ТОЛПОЙ, и различать надо издали ---------------------
    "swordsman": {
        "height": 0.99, "shoulders": 1.08, "limb": 1.00,
        "skin": (0.64, 0.47, 0.35), "cloth": (0.25, 0.17, 0.13),
        "trim": (0.44, 0.45, 0.50), "hair": (0.14, 0.11, 0.09),
        "cloak": False, "long_hair": False, "pauldrons": True, "ears": 0.02,
    },
    "archer": {
        "height": 0.97, "shoulders": 0.94, "limb": 0.90,
        "skin": (0.68, 0.52, 0.39), "cloth": (0.17, 0.24, 0.16),
        "trim": (0.34, 0.25, 0.14), "hair": (0.30, 0.20, 0.12),
        "cloak": True, "long_hair": False, "pauldrons": False, "ears": 0.02,
    },
    "champion": {
        "height": 1.06, "shoulders": 1.20, "limb": 1.10,
        "skin": (0.62, 0.45, 0.33), "cloth": (0.20, 0.16, 0.24),
        "trim": (0.62, 0.52, 0.22), "hair": (0.13, 0.10, 0.08),
        "cloak": True, "long_hair": False, "pauldrons": True, "ears": 0.02,
    },
    # --- батраки: роль видно по цвету, оружия у них нет -----------------------
    "peasant": {
        "height": 0.96, "shoulders": 0.94, "limb": 0.92,
        "skin": (0.67, 0.50, 0.37), "cloth": (0.42, 0.34, 0.22),
        "trim": (0.28, 0.22, 0.15), "hair": (0.24, 0.17, 0.11),
        "cloak": False, "long_hair": False, "pauldrons": False, "ears": 0.02,
    },
    "miner": {
        "height": 0.95, "shoulders": 1.02, "limb": 0.96,
        "skin": (0.58, 0.44, 0.34), "cloth": (0.28, 0.26, 0.24),
        "trim": (0.20, 0.19, 0.18), "hair": (0.12, 0.10, 0.09),
        "cloak": False, "long_hair": False, "pauldrons": False, "ears": 0.02,
    },
    "woodcutter": {
        "height": 1.00, "shoulders": 1.06, "limb": 1.00,
        "skin": (0.66, 0.49, 0.36), "cloth": (0.30, 0.22, 0.14),
        "trim": (0.45, 0.33, 0.18), "hair": (0.33, 0.22, 0.12),
        "cloak": False, "long_hair": False, "pauldrons": False, "ears": 0.02,
    },
    "mason": {
        "height": 0.98, "shoulders": 1.04, "limb": 0.98,
        "skin": (0.63, 0.47, 0.35), "cloth": (0.36, 0.35, 0.33),
        "trim": (0.50, 0.48, 0.44), "hair": (0.18, 0.14, 0.11),
        "cloak": False, "long_hair": False, "pauldrons": False, "ears": 0.02,
    },
}


def P(side, up, forward=0.0):
    """Точка в понятных словах → координаты Blender.

    ЗАЧЕМ ЭТО ОТДЕЛЬНО. В Blender вверх — это Z, а не Y, и «вперёд» — это
    минус Y. Первый заход я написал высоту в Y, экспорт честно повернул сцену,
    и в Godot персонаж приехал лежащим на спине: рост 2.44 стоял в третьей
    координате. Глазами в консоли это не видно — видно только пробником.
    Поэтому координаты больше нигде не пишутся руками.
    """
    return (side, -forward, up)


def S(width, height, depth):
    """Габарит коробки в тех же словах, что и `P`."""
    return (width, depth, height)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_to_linear(c):
    """Цвет, как его видит человек → цвет, как его ждёт Blender.

    ЗАЧЕМ. Base Color в Blender ЛИНЕЙНЫЙ, а числа палитры подбираются глазами,
    то есть в sRGB. Без перевода 0.12 («тёмная зелень») выводится как 0.37 —
    светлее втрое. Первый набор цветов из-за этого оказался выцветшим, и в игре
    персонаж читался бледным призраком на ярком поле: подбирать палитру темнее
    «на глаз» было бы лечением симптома.
    """
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    lin = [srgb_to_linear(c) for c in rgb]
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


# --- скелет ------------------------------------------------------------------


def build_armature(preset):
    """Скелет с именами, которые ищет rig.gd."""
    h = preset["height"]
    sh = preset["shoulders"]
    y = {k: v * h for k, v in HEIGHTS.items()}

    arm_data = bpy.data.armatures.new("CharacterArmature")
    arm_obj = bpy.data.objects.new("CharacterArmature", arm_data)
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

    # Корень на полу: по нему игра двигает персонажа, и он же — общий родитель.
    bone("Root", P(0, 0), P(0, 0.18 * h))
    bone("Hips", P(0, y["hip"]), P(0, y["torso"]), "Root")
    bone("Torso", P(0, y["torso"]), P(0, y["neck"]), "Hips", True)
    bone("Neck", P(0, y["neck"]), P(0, y["head"]), "Torso", True)
    bone("Head", P(0, y["head"]), P(0, y["head"] + 0.30 * h), "Neck", True)

    for side, sx in (("L", 1.0), ("R", -1.0)):
        sx_sh = sx * 0.29 * sh
        bone(f"Shoulder.{side}", P(0, y["shoulder"]),
             P(sx_sh, y["shoulder"]), "Torso")
        bone(f"UpperArm.{side}", P(sx_sh, y["shoulder"]),
             P(sx_sh, y["elbow"]), f"Shoulder.{side}", True)
        bone(f"LowerArm.{side}", P(sx_sh, y["elbow"]),
             P(sx_sh, y["fist"]), f"UpperArm.{side}", True)
        bone(f"Fist.{side}", P(sx_sh, y["fist"]),
             P(sx_sh, y["fist"] - 0.12 * h), f"LowerArm.{side}", True)

        sx_hip = sx * 0.10 * h
        bone(f"UpperLeg.{side}", P(sx_hip, y["hip"]),
             P(sx_hip, y["knee"]), "Hips")
        bone(f"LowerLeg.{side}", P(sx_hip, y["knee"]),
             P(sx_hip, y["foot"]), f"UpperLeg.{side}", True)
        bone(f"Foot.{side}", P(sx_hip, y["foot"]),
             P(sx_hip, y["foot"], 0.16 * h), f"LowerLeg.{side}", True)

    # Точка хвата. Оружие вешается СЮДА (rig.gd::WEAPON_BONE), поэтому кость
    # смотрит ВПЕРЁД: weapon_visual.gd кладёт оружие вдоль этой оси.
    hand_x = -0.29 * sh
    bone("Weapon.R", P(hand_x, y["fist"] - 0.06 * h, 0.04),
         P(hand_x, y["fist"] - 0.06 * h, 0.24), "Fist.R")

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


# --- меш ---------------------------------------------------------------------


## Насколько куски залезают друг в друга на стыках.
##
## Вес 1.0 на одну кость означает, что соседние коробки поворачиваются вокруг
## РАЗНЫХ точек, и точно состыкованные края на повороте расходятся. В первом
## рендере замаха голова улетела от плеч, а предплечье отделилось от локтя —
## тело буквально разваливалось на куски в кадре удара. Перекрытие прячет шов:
## на стыке всегда есть лишний сантиметр, который уходит внутрь соседа.
JOINT_OVERLAP = 0.07

## Насколько голова СЪЕЗЖАЕТ вниз, на плечи.
##
## У покупных моделей голова не стоит на шее, а надвинута на плечи — шеи почти
## не видно, и от этого силуэт крепкий. Поставленная ровно на кость, крупная
## голова висит на палке и выглядит приклеенной. Кость при этом не двигается:
## она часть договора с `rig.gd`, съезжает только меш.
HEAD_SINK = 0.20


def add_box(verts, faces, groups, bone_name, center, size, taper=1.0):
    """Коробка (или усечённая пирамида), привязанная к одной кости.

    Привязка по коробке, а не автоматическими весами, и это не лень: игра
    отрывает конечность, схлопывая кость: вес 1.0 на одну кость даёт чистый
    отрыв, а размазанные веса растянули бы соседние части в нитку.

    `taper` — во сколько раз верх уже низа. Ради него всё и переписано: из
    одинаковых кирпичей тело читается как стопка коробок, а не как человек.
    Бедро сужается к колену, грудь расширяется к плечам — и силуэт появляется
    без единого лишнего полигона.
    """
    cx, cy, cz = center
    sx, sy, sz = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    base = len(verts)
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                k = taper if dz > 0 else 1.0
                verts.append((cx + dx * sx * k, cy + dy * sy * k, cz + dz * sz))
    # Порядок вершин куба: индексы по (dx,dy,dz) в том же порядке, что выше.
    idx = {(-1, -1, -1): 0, (-1, -1, 1): 1, (-1, 1, -1): 2, (-1, 1, 1): 3,
           (1, -1, -1): 4, (1, -1, 1): 5, (1, 1, -1): 6, (1, 1, 1): 7}
    quads = [
        [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)],
        [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
        [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
        [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],
        [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)],
        [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
    ]
    for q in quads:
        faces.append(tuple(base + idx[c] for c in q))
    groups.setdefault(bone_name, []).extend(range(base, base + 8))
    return base


def build_mesh(preset, arm_obj):
    h = preset["height"]
    sh = preset["shoulders"]
    lb = preset["limb"]
    y = {k: v * h for k, v in HEIGHTS.items()}

    verts, faces = [], []
    groups = {}
    # Какой кусок какого цвета: индекс материала на каждую грань.
    part_of_face = []

    def part(bone_name, center, size, slot, taper=1.0):
        before = len(faces)
        add_box(verts, faces, groups, bone_name, center, size, taper)
        part_of_face.extend([slot] * (len(faces) - before))

    # 0 — кожа, 1 — одежда, 2 — отделка, 3 — волосы.
    # ПРОПОРЦИИ МЕША НЕ ОБЯЗАНЫ ПОВТОРЯТЬ ДЛИНЫ КОСТЕЙ. Кости стоят на высотах,
    # которых требует `rig.gd`, и двигать их нельзя. А тело поверх них лепится
    # свободно: первый заход честно повторил кости и дал длинную шею, огромный
    # таз и короткую грудь — человек так не выглядит.
    waist = y["hip"] + 0.30 * h        # где таз переходит в грудь
    chest_top = y["shoulder"] + 0.12 * h
    # ГОЛОВА КРУПНАЯ, И ЭТО НЕ ВКУСОВЩИНА. Покупная модель ростом 2.89 при
    # кости головы на 2.10 — голова занимает почти треть роста, это канон
    # Quaternius, под который посчитан MODEL_SCALE = 0.63 (рост 1.84 м). Голова
    # «по-человечески» дала бы персонажа 2.31 в высоту, то есть коротышку 1.46 м
    # рядом со всеми остальными, и пришлось бы заводить свой масштаб на модель.
    #
    # Кость головы — НИЗ черепа, как у них: зона попадания радиусом 0.32 висит
    # там же и накрывает ту же часть головы, что у покупных.
    head_half = 0.42 * h
    head_low = y["head"]               # низ головы садится прямо на кость
    boot_top = 0.22 * h                # голенище: сапог, а не нога целиком

    # Куски СМЫКАЮТСЯ, а не стоят рядом. Первый заход оставил между головой и
    # грудью пять сантиметров воздуха — на рендере голова висела отдельно от
    # тела, и это единственное, что было видно на картинке.
    # Таз сужается кверху, грудь кверху расширяется — между ними талия, и она
    # одна делает из столба фигуру.
    part("Hips", P(0, (y["hip"] + waist) / 2),
         S(0.42 * sh, waist - y["hip"], 0.32), 1, taper=0.88)
    part("Torso", P(0, (waist + chest_top) / 2),
         S(0.46 * sh, chest_top - waist, 0.32), 1, taper=1.18)
    # Пояс: узкая полоса отделки — она задаёт силуэт сильнее, чем кажется.
    part("Torso", P(0, waist), S(0.48 * sh, 0.07 * h, 0.34), 2)

    # Шея нарочно длиннее промежутка: она уходит и в грудь, и в голову.
    neck_mid = (chest_top + head_low) / 2
    part("Neck", P(0, neck_mid),
         S(0.15, head_low - chest_top + JOINT_OVERLAP * 3, 0.15), 0)

    head_mid = y["head"] + head_half - HEAD_SINK
    part("Head", P(0, head_mid), S(0.66, head_half * 2, 0.62), 0, taper=0.94)
    # Волосы шапкой поверх макушки, чуть сдвинуты назад — открывают лицо.
    part("Head", P(0, head_mid + head_half * 0.78, -0.03),
         S(0.67, head_half * 0.52, 0.63), 3, taper=0.90)
    if preset.get("long_hair"):
        # Длинные волосы по спине. Читаются со спины и сзади-сбоку — там, где
        # лица не видно, а отличить сторону всё равно надо.
        part("Head", P(0, head_mid - head_half * 0.25, -0.30),
             S(0.46, head_half * 1.25, 0.10), 3, taper=1.0)
    # Глаза. Две тёмные плашки на лице — самая дешёвая деталь, которая
    # превращает коробку в голову: без них персонаж читается как манекен, и
    # непонятно даже, куда он смотрит.
    for ex in (-0.145, 0.145):
        part("Head", P(ex, head_mid + 0.05, 0.285), S(0.095, 0.095, 0.03), 4)
    # Нос: одна коробка, но именно она задаёт, куда повёрнута голова. Без него
    # лицо и затылок отличаются только цветом глаз.
    part("Head", P(0, head_mid - 0.06, 0.295), S(0.09, 0.13, 0.06), 0)
    # Уши. У эльфа длинные и подняты — это его единственный видовой признак,
    # и другого способа показать «это эльф» в low-poly нет.
    ear: float = float(preset.get("ears", 0.02))
    for ex in (-1.0, 1.0):
        part("Head", P(ex * 0.315, head_mid + 0.02 + ear * 1.2, -0.02),
             S(0.06, 0.16 + ear * 3.4, 0.16), 0, taper=0.55)

    if preset.get("cloak"):
        # Плащ от плеч до колен, на кости торса — едет с корпусом, а не висит
        # в воздухе. Он же закрывает спину, где деталей нет вовсе.
        cloak_h = chest_top - y["knee"] * 0.9
        part("Torso", P(0, (chest_top + y["knee"] * 0.9) / 2, -0.19),
             S(0.44 * sh, cloak_h, 0.07), 2, taper=0.78)

    for side, sx in (("L", 1.0), ("R", -1.0)):
        ax = sx * 0.29 * sh
        part(f"Shoulder.{side}", P(ax, y["shoulder"] + 0.02 * h),
             S(0.21 * sh, 0.19, 0.26), 2)
        if preset.get("pauldrons"):
            # Наплечник поверх плеча: расширяет силуэт вверху, и сторона с ним
            # читается как «доспешная» с любого расстояния.
            part(f"Shoulder.{side}", P(ax * 1.04, y["shoulder"] + 0.09 * h),
                 S(0.26 * sh, 0.10, 0.30), 2, taper=0.72)
        # Габарит задаёт УЗКИЙ конец (локоть, запястье), taper расширяет верх.
        upper_h = y["shoulder"] - y["elbow"]
        part(f"UpperArm.{side}", P(ax, y["elbow"] + upper_h / 2, 0.035),
             S(0.165 * lb, upper_h + JOINT_OVERLAP * 2, 0.175 * lb), 1, taper=1.20)
        lower_h = y["elbow"] - y["fist"]
        part(f"LowerArm.{side}", P(ax, y["fist"] + lower_h / 2, 0.055),
             S(0.145 * lb, lower_h + JOINT_OVERLAP * 2, 0.15 * lb), 0, taper=1.16)
        part(f"Fist.{side}", P(ax, y["fist"] - 0.07 * h, 0.065),
             S(0.16, 0.15, 0.17), 0)

        hx = sx * 0.11 * h
        thigh_h = y["hip"] - y["knee"]
        part(f"UpperLeg.{side}", P(hx, y["knee"] + thigh_h / 2),
             S(0.185 * lb, thigh_h + JOINT_OVERLAP * 2, 0.200 * lb), 1, taper=1.24)
        # Голень штаниной, и только низ — сапогом. Раньше вся голень была
        # цветом отделки, и нога читалась как ботфорт до колена.
        shin_h = y["knee"] - boot_top
        part(f"LowerLeg.{side}", P(hx, boot_top + shin_h / 2),
             S(0.165 * lb, shin_h, 0.180 * lb), 1, taper=1.14)
        part(f"LowerLeg.{side}", P(hx, boot_top / 2 + y["foot"] / 2),
             S(0.18 * lb, boot_top - y["foot"], 0.18 * lb), 2)
        # Стопа выдаётся ВПЕРЁД: без неё силуэт читается как столб на палках.
        part(f"Foot.{side}", P(hx, y["foot"] / 2, 0.06),
             S(0.18, y["foot"] * 1.6, 0.30), 2)

    mesh = bpy.data.meshes.new("Body")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new("Body", mesh)
    bpy.context.collection.objects.link(obj)

    for name, rgb in (("Skin", preset["skin"]), ("Cloth", preset["cloth"]),
                      ("Trim", preset["trim"]), ("Hair", preset["hair"]),
                      ("Eye", (0.10, 0.09, 0.11))):
        obj.data.materials.append(make_material(name, rgb))
    for i, slot in enumerate(part_of_face):
        mesh.polygons[i].material_index = slot

    # Плоские грани: стиль low-poly держится именно на них.
    for poly in mesh.polygons:
        poly.use_smooth = False

    for bone_name, indices in groups.items():
        vg = obj.vertex_groups.new(name=bone_name)
        vg.add(indices, 1.0, "REPLACE")

    _bevel(obj)

    obj.parent = arm_obj
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    return obj


## Снять острые рёбра.
##
## Это самое дешёвое, что отличает свою модель от покупной. Рендер Quaternius
## тем же светом показал: у них не коробки, а слегка огранённые тела — свет
## ловится на фасках, и силуэт перестаёт быть «сделанным из кубиков». Разница
## видна с первого взгляда и стоит одного модификатора.
##
## Фаска безопасна для расчленения: куски не сварены между собой, каждая
## коробка — отдельная оболочка со своей костью, и новые вершины наследуют её
## вес. Приваривать их друг к другу нельзя — тогда отрыв растянет соседа.
## Размер запекаемой текстуры. 512 хватает: у персонажа нет ни надписей, ни
## мелкого узора, а вес файла растёт квадратом.
BAKE_SIZE = 512
## Насколько сильно затенение давит цвет. Единица — как посчитал Blender, и это
## слишком черно для стилизованной картинки.
AO_STRENGTH = 0.65


def bake_texture(obj, name):
    """Запечь цвет и затенение в одну текстуру.

    ЗАЧЕМ. Плоская заливка — главное, чем своя модель отличалась от покупной:
    у Quaternius нарисованы складки, оторочка и тени в стыках, и именно они
    читаются как «сделано художником». Нарисовать я не умею, но затенение
    рисовать и не надо — оно СЧИТАЕТСЯ по геометрии. Запечённый ambient
    occlusion кладёт тень в подмышки, под пояс, между пальцами и по швам, и
    модель перестаёт выглядеть пластмассовой.

    КАК. Развёртка, потом два запекания: цвет материалов и затенение. Потом
    перемножаем их попиксельно и вешаем один материал с одной текстурой —
    заодно вместо пяти материалов остаётся один, что для пешек в толпе не
    лишнее.

    Запекает Cycles: EEVEE запекать не умеет. Сэмплов берём мало — затенение
    мягкое, шум в нём не виден, а время растёт линейно.
    """
    scene = bpy.context.scene
    prev_engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Развёртка. Углы швов по умолчанию режут коробки по рёбрам — ровно то,
    # что нужно: каждая грань ложится своим островом и не тянется.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")

    albedo = bpy.data.images.new("%s_albedo" % name, BAKE_SIZE, BAKE_SIZE)
    shade = bpy.data.images.new("%s_ao" % name, BAKE_SIZE, BAKE_SIZE)

    def target(image):
        """Куда печь: у КАЖДОГО материала свой узел-приёмник, и он активен."""
        for slot in obj.data.materials:
            nodes = slot.node_tree.nodes
            node = nodes.get("BakeTarget")
            if node is None:
                node = nodes.new("ShaderNodeTexImage")
                node.name = "BakeTarget"
            node.image = image
            nodes.active = node

    target(albedo)
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)

    target(shade)
    bpy.ops.object.bake(type="AO", use_clear=True)

    # Перемножаем. Работаем со списком пикселей целиком: по одному — минуты.
    base = list(albedo.pixels)
    dark = list(shade.pixels)
    for i in range(0, len(base), 4):
        k = 1.0 - (1.0 - dark[i]) * AO_STRENGTH
        base[i] *= k
        base[i + 1] *= k
        base[i + 2] *= k
        base[i + 3] = 1.0
    albedo.pixels = base

    # Один материал на всю модель вместо пяти.
    baked = bpy.data.materials.new("%s_baked" % name)
    baked.use_nodes = True
    bsdf = baked.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    tex = baked.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = albedo
    baked.node_tree.links.new(bsdf.inputs["Base Color"], tex.outputs["Color"])

    obj.data.materials.clear()
    obj.data.materials.append(baked)
    for poly in obj.data.polygons:
        poly.material_index = 0

    scene.render.engine = prev_engine
    return albedo


def _bevel(obj):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.055
    mod.segments = 2
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40.0)
    mod.harden_normals = False
    bpy.ops.object.modifier_apply(modifier=mod.name)


# --- анимации ----------------------------------------------------------------


def rot(pose_bone, axis, degrees):
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.rotation_quaternion = Quaternion(axis, math.radians(degrees))


def key(arm_obj, names, frame):
    for name in names:
        pb = arm_obj.pose.bones[name]
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if name == "Root":
            pb.keyframe_insert(data_path="location", frame=frame)


def new_action(arm_obj, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm_obj.animation_data.action = act
    # Blender 4.4+ хранит дорожки в слотах: без привязки слота ключи уходят в
    # никуда, и экспорт отдаёт пустую анимацию.
    if hasattr(arm_obj.animation_data, "action_slot"):
        slot = act.slots.new(id_type="OBJECT", name="Pose")
        arm_obj.animation_data.action_slot = slot
    return act


def clear_pose(arm_obj):
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))


ARMS = ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]
LEGS = ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R"]
ALL = ["Root", "Hips", "Torso", "Head"] + ARMS + LEGS


def anim_idle(arm_obj):
    new_action(arm_obj, "Idle")
    for frame, lean in ((1, 0.0), (24, 1.6), (48, 0.0)):
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["Torso"], (1, 0, 0), lean)
        rot(arm_obj.pose.bones["Head"], (1, 0, 0), -lean * 0.4)
        rot(arm_obj.pose.bones["UpperArm.L"], (1, 0, 0), lean * 1.2)
        rot(arm_obj.pose.bones["UpperArm.R"], (1, 0, 0), lean * 1.2)
        key(arm_obj, ALL, frame)


def _gait(arm_obj, name, swing, knee, bounce, length):
    new_action(arm_obj, name)
    half = length // 2
    for step, sign in ((1, 1.0), (1 + half, -1.0), (1 + length, 1.0)):
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["UpperLeg.L"], (1, 0, 0), swing * sign)
        rot(arm_obj.pose.bones["UpperLeg.R"], (1, 0, 0), -swing * sign)
        rot(arm_obj.pose.bones["LowerLeg.L"], (1, 0, 0), -knee * max(0.0, -sign))
        rot(arm_obj.pose.bones["LowerLeg.R"], (1, 0, 0), -knee * max(0.0, sign))
        # Руки ходят навстречу ногам — без этого походка выглядит деревянной.
        rot(arm_obj.pose.bones["UpperArm.L"], (1, 0, 0), -swing * sign * 0.8)
        rot(arm_obj.pose.bones["UpperArm.R"], (1, 0, 0), swing * sign * 0.8)
        arm_obj.pose.bones["Root"].location = Vector((0, 0, 0))
        key(arm_obj, ALL, step)
    # Подпрыгивание корпуса на середине шага.
    for step in (1 + half // 2, 1 + half + half // 2):
        clear_pose(arm_obj)
        arm_obj.pose.bones["Root"].location = Vector((0, bounce, 0))
        arm_obj.pose.bones["Root"].keyframe_insert(data_path="location", frame=step)


def anim_walk(arm_obj):
    _gait(arm_obj, "Walk", swing=24.0, knee=28.0, bounce=0.03, length=32)


def anim_run(arm_obj):
    _gait(arm_obj, "Run", swing=42.0, knee=54.0, bounce=0.07, length=22)


def anim_sword_attack(arm_obj):
    """Замах с правой: занос за плечо, рубящий удар вниз, возврат.

    Тот самый кадр, которого не было ни в одной модели: у Ranger анимации
    ближнего боя нет вовсе, и удар эльфа не рисовался ничем.
    """
    new_action(arm_obj, "Sword_Attack")
    poses = [
        # кадр, плечо, локоть, корпус, поворот корпуса
        # Поворот корпуса держим маленьким НАМЕРЕННО: на жёсткой привязке
        # каждый лишний градус — это разошедшийся шов на шее и плече. Замах
        # рисует рука, корпус только поддерживает.
        (1, 0.0, -10.0, 0.0, 0.0),
        (5, -92.0, -64.0, -8.0, 12.0),     # занос
        (11, 58.0, -6.0, 11.0, -14.0),     # удар
        (15, 40.0, -14.0, 7.0, -9.0),      # отдача
        (24, 0.0, -10.0, 0.0, 0.0),        # возврат в стойку
    ]
    for frame, shoulder, elbow, lean, twist in poses:
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["UpperArm.R"], (1, 0, 0), shoulder)
        rot(arm_obj.pose.bones["LowerArm.R"], (1, 0, 0), elbow)
        rot(arm_obj.pose.bones["UpperArm.L"], (1, 0, 0), -shoulder * 0.25)
        pb = arm_obj.pose.bones["Torso"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (Quaternion((1, 0, 0), math.radians(lean))
                                  @ Quaternion((0, 1, 0), math.radians(twist)))
        rot(arm_obj.pose.bones["Head"], (0, 1, 0), twist * 0.4)
        key(arm_obj, ALL, frame)


def anim_death(arm_obj):
    new_action(arm_obj, "Death")
    poses = [
        (1, 0.0, 0.0, 0.0),
        (8, -18.0, 0.10, 12.0),
        (20, -72.0, -0.55, 40.0),
        (30, -90.0, -0.86, 46.0),
    ]
    for frame, lean, drop, knees in poses:
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["Hips"], (1, 0, 0), lean * 0.4)
        rot(arm_obj.pose.bones["Torso"], (1, 0, 0), lean * 0.6)
        rot(arm_obj.pose.bones["Head"], (1, 0, 0), -lean * 0.3)
        for leg in ("UpperLeg.L", "UpperLeg.R"):
            rot(arm_obj.pose.bones[leg], (1, 0, 0), knees)
        for leg in ("LowerLeg.L", "LowerLeg.R"):
            rot(arm_obj.pose.bones[leg], (1, 0, 0), -knees * 1.2)
        arm_obj.pose.bones["Root"].location = Vector((0, drop, 0))
        key(arm_obj, ALL, frame)


def anim_bow_shoot(arm_obj):
    """Натянул и отпустил. Левая держит лук, правая тянет тетиву к щеке."""
    new_action(arm_obj, "Bow_Shoot")
    poses = [
        # кадр, левая (держит), правая (тянет), локоть правой, корпус
        (1, -70.0, -40.0, -30.0, 0.0),
        (9, -84.0, -22.0, -96.0, -8.0),    # натяг
        (13, -84.0, -20.0, -92.0, -8.0),   # выдержка
        (17, -80.0, -62.0, -40.0, -4.0),   # отпустил
        (28, -70.0, -40.0, -30.0, 0.0),
    ]
    for frame, left, right, elbow, twist in poses:
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["UpperArm.L"], (1, 0, 0), left)
        rot(arm_obj.pose.bones["UpperArm.R"], (1, 0, 0), right)
        rot(arm_obj.pose.bones["LowerArm.R"], (1, 0, 0), elbow)
        pb = arm_obj.pose.bones["Torso"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((0, 1, 0), math.radians(twist))
        key(arm_obj, ALL, frame)


def anim_recieve_hit(arm_obj):
    """Вздрогнул от попадания. Короткая, иначе из боя не выйти."""
    new_action(arm_obj, "RecieveHit")
    for frame, lean, arms in ((1, 0.0, 0.0), (4, -22.0, -26.0), (8, -9.0, -12.0),
                              (16, 0.0, 0.0)):
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["Torso"], (1, 0, 0), lean)
        rot(arm_obj.pose.bones["Head"], (1, 0, 0), lean * 0.6)
        for a in ("UpperArm.L", "UpperArm.R"):
            rot(arm_obj.pose.bones[a], (1, 0, 0), arms)
        key(arm_obj, ALL, frame)


def anim_sit(arm_obj):
    """Сидит на земле: ноги вперёд, корпус чуть назад.

    ЭТО ТА САМАЯ ПОЗА, КОТОРОЙ НЕТ НИ В ОДНОМ ПАКЕ. Игра играет «sit» безногому
    (`model_anim.gd`: ползания в паках нет, и подставлялся `Idle`) — то есть
    ползающий стоял по стойке смирно, просто опущенный под землю. Своя поза
    закрывает и ползание, и коляску.
    """
    new_action(arm_obj, "Sit")
    for frame, sway in ((1, 0.0), (36, 1.8), (72, 0.0)):
        clear_pose(arm_obj)
        rot(arm_obj.pose.bones["Hips"], (1, 0, 0), -14.0)
        rot(arm_obj.pose.bones["Torso"], (1, 0, 0), 8.0 + sway)
        for leg in ("UpperLeg.L", "UpperLeg.R"):
            rot(arm_obj.pose.bones[leg], (1, 0, 0), 78.0)
        for leg in ("LowerLeg.L", "LowerLeg.R"):
            rot(arm_obj.pose.bones[leg], (1, 0, 0), -16.0)
        for a in ("UpperArm.L", "UpperArm.R"):
            rot(arm_obj.pose.bones[a], (1, 0, 0), 26.0 - sway)
        key(arm_obj, ALL, frame)


def build_animations(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    arm_obj.animation_data_create()
    anim_idle(arm_obj)
    anim_walk(arm_obj)
    anim_run(arm_obj)
    anim_sword_attack(arm_obj)
    anim_death(arm_obj)
    anim_bow_shoot(arm_obj)
    anim_recieve_hit(arm_obj)
    anim_sit(arm_obj)
    arm_obj.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")


# --- сборка ------------------------------------------------------------------


# --- просмотр ----------------------------------------------------------------
#
# Без картинки кузница слепая. Пробник в Godot отвечает «кость на месте», но не
# отвечает «на это можно смотреть»; ровно на этом уже обожглись однажды, когда
# верные координаты спавна ничего не сказали про то, что видит человек.


def setup_render(res):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.17, 0.19, 1)
    scene.world = world

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(58), 0.0, math.radians(38))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 55
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    return cam


def shoot(cam, target, offset, path):
    cam.location = Vector(target) + Vector(offset)
    aim = Vector(target) - cam.location
    cam.rotation_euler = aim.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_sheet(arm_obj, outdir, res=512):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    cam = setup_render(res)
    target = (0.0, 0.0, 1.45)

    # Поза покоя: спереди и сбоку. Силуэт проверяется именно здесь.
    arm_obj.animation_data.action = None
    shoot(cam, target, (0.0, -5.8, 0.40), outdir / "01_покой_спереди.png")
    shoot(cam, target, (5.8, 0.0, 0.40), outdir / "02_покой_сбоку.png")
    shoot(cam, target, (-3.9, -4.4, 0.75), outdir / "02b_покой_три_четверти.png")
    shoot(cam, target, (2.0, 5.5, 0.75), outdir / "02c_покой_со_спины.png")

    # Замах: занос, удар, возврат. Три кадра, по которым видно, что это удар.
    attack = bpy.data.actions.get("Sword_Attack")
    if attack is not None:
        arm_obj.animation_data.action = attack
        if hasattr(arm_obj.animation_data, "action_slot") and attack.slots:
            arm_obj.animation_data.action_slot = attack.slots[0]
        for frame, label in ((5, "03_замах_занос"), (11, "04_замах_удар"),
                             (15, "05_замах_отдача")):
            bpy.context.scene.frame_set(frame)
            shoot(cam, target, (-4.2, -3.8, 0.65), outdir / ("%s.png" % label))
        arm_obj.animation_data.action = None
    bpy.context.scene.frame_set(1)

    # Позы, которых нет ни в одном паке, — их и надо смотреть глазами.
    for act_name, frame, label in (
        ("Sit", 1, "07_сидит_ползёт"),
        ("Bow_Shoot", 9, "09_натянул_лук"),
        ("RecieveHit", 4, "10_вздрогнул"),
    ):
        act = bpy.data.actions.get(act_name)
        if act is None:
            continue
        arm_obj.animation_data.action = act
        if hasattr(arm_obj.animation_data, "action_slot") and act.slots:
            arm_obj.animation_data.action_slot = act.slots[0]
        bpy.context.scene.frame_set(frame)
        shoot(cam, target, (-3.9, -4.4, 0.75), outdir / ("%s.png" % label))
        arm_obj.animation_data.action = None
    bpy.context.scene.frame_set(1)

    # Шаг: середина цикла, чтобы видеть развод ног.
    walk = bpy.data.actions.get("Walk")
    if walk is not None:
        arm_obj.animation_data.action = walk
        if hasattr(arm_obj.animation_data, "action_slot") and walk.slots:
            arm_obj.animation_data.action_slot = walk.slots[0]
        bpy.context.scene.frame_set(9)
        shoot(cam, target, (5.0, -2.9, 0.45), outdir / "06_шаг.png")
        arm_obj.animation_data.action = None
    bpy.context.scene.frame_set(1)


def action_fcurves(act):
    """Дорожки анимации, где бы их ни держала текущая версия Blender.

    До 4.4 они лежали прямо в `action.fcurves`. С появлением слоёв и слотов их
    убрали в `layers -> strips -> channelbags`, и старое поле исчезло совсем.
    Проверка масштаба (она охраняет расчленение) обязана работать в обеих.
    """
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    found = []
    for layer in getattr(act, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                found.extend(bag.fcurves)
    return found


def verify(arm_obj):
    """Договор с игрой проверяем ЗДЕСЬ, до экспорта.

    Молча уехавшее имя кости — это потерянная зона попадания, и в игре оно
    проявится не ошибкой, а тем, что в руку нельзя попасть. Дешевле упасть тут.
    """
    have = {b.name for b in arm_obj.data.bones}
    missing = [n for n in REQUIRED_BONES if n not in have]
    if missing:
        raise SystemExit("нет обязательных костей: %s" % ", ".join(missing))
    acts = {a.name for a in bpy.data.actions}
    lost = [n for n in REQUIRED_ACTIONS if n not in acts]
    if lost:
        raise SystemExit("нет обязательных анимаций: %s" % ", ".join(lost))
    for act in bpy.data.actions:
        for fc in action_fcurves(act):
            if "scale" in fc.data_path:
                raise SystemExit(
                    "в анимации %s есть дорожка масштаба — она сломает "
                    "расчленение (см. rig.gd)" % act.name)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="Forged")
    ap.add_argument("--preset", default="elf", choices=sorted(PRESETS))
    ap.add_argument("--out", required=True)
    ap.add_argument("--render", default="", help="папка для картинок-просмотра")
    ap.add_argument("--bake", action="store_true",
                    help="запечь цвет и затенение в текстуру (медленно, для финала)")
    args = ap.parse_args(argv)

    preset = PRESETS[args.preset]
    clear_scene()
    arm_obj = build_armature(preset)
    body = build_mesh(preset, arm_obj)
    if args.bake:
        bake_texture(body, args.name)
    build_animations(arm_obj)
    arm_obj.name = "CharacterArmature"
    verify(arm_obj)

    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_animation_mode="ACTIONS",
        export_yup=True,
        export_apply=False,
        use_selection=False,
    )
    if args.render:
        render_sheet(arm_obj, args.render)
        print("FORGE_SHOTS %s" % args.render)

    print("FORGE_OK %s костей=%d анимаций=%d" % (
        out, len(arm_obj.data.bones), len(bpy.data.actions)))


if __name__ == "__main__":
    main()
