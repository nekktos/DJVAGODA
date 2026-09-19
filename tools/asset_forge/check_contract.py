"""
Сторож договора между кузницей и игрой.

ЗАЧЕМ. Кузница обещает ровно два списка: кости, которые ищет
`godot_project/scripts/combat/rig.gd`, и анимации, которые переводит
`godot_project/scripts/model_anim.gd`. Оба списка продублированы в
`character.py`, а два описания одного расходятся при первой же правке — это в
проекте уже случалось, и не раз.

Расхождение молчит там, где больнее всего. Уехавшее имя кости не роняет игру:
просто в руку нельзя попасть. Анимация, которой игра не умеет попросить, не
ругается: она честно лежит в файле и никогда не играет. Оба случая находятся
глазами, случайно, через недели.

Здесь мы это читаем ИЗ ИСХОДНИКОВ игры и сверяем. Скрипт не знает Blender и не
запускает Godot — нужен только Python.

Запуск из корня проекта:
    python tools/asset_forge/check_contract.py

Выход 0 — договор цел. Выход 1 — расхождение, и оно напечатано.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RIG = ROOT / "godot_project" / "scripts" / "combat" / "rig.gd"
ANIM = ROOT / "godot_project" / "scripts" / "model_anim.gd"
FORGE = Path(__file__).with_name("character.py")


def read(path):
    if not path.exists():
        sys.exit("нет файла: %s" % path)
    return path.read_text(encoding="utf-8")


def block(text, name):
    """Тело константы `name` — от её строки до строки, где кончается скобка."""
    start = text.find("const %s" % name)
    if start < 0:
        return ""
    line_end = text.find("\n", start)
    head = text[start:line_end]
    # Однострочная константа: всё уже здесь.
    if head.count("[") == head.count("]") and head.count("{") == head.count("}"):
        return head
    depth = head.count("[") - head.count("]") + head.count("{") - head.count("}")
    out = [head]
    pos = line_end + 1
    while depth > 0 and pos < len(text):
        nl = text.find("\n", pos)
        if nl < 0:
            nl = len(text)
        line = text[pos:nl]
        out.append(line)
        depth += line.count("[") - line.count("]") + line.count("{") - line.count("}")
        pos = nl + 1
    return "\n".join(out)


def game_bones():
    """Кости, без которых игра теряет зону попадания, отрыв или хват."""
    text = read(RIG)
    wanted = set()
    # ["UpperArm.L", ...] — кости отрыва.
    for name in re.findall(r'"([A-Za-z][A-Za-z0-9_.]*)"', block(text, "SEVER_BONES")):
        wanted.add(name)
    # [["Head", 0.32], ...] — кость и радиус. Ключи зон («head») сюда не попадают.
    for name in re.findall(r'\["([A-Za-z][A-Za-z0-9_.]*)"\s*,\s*[\d.]+\]',
                           block(text, "ZONE_BONES")):
        wanted.add(name)
    for name in re.findall(r'"([A-Za-z][A-Za-z0-9_.]*)"', block(text, "WEAPON_BONE")):
        wanted.add(name)
    return wanted


def game_animation_words():
    """Все имена анимаций, которые игра вообще способна попросить."""
    text = read(ANIM)
    return set(re.findall(r'"([A-Za-z][A-Za-z0-9_.\-]*)"', block(text, "SYNONYMS")))


def forge_list(name):
    text = read(FORGE)
    start = text.find("%s = [" % name)
    if start < 0:
        sys.exit("в кузнице нет списка %s" % name)
    end = text.find("\n]", start)
    return set(re.findall(r'"([^"]+)"', text[start:end]))


def main():
    problems = []

    need_bones = game_bones()
    have_bones = forge_list("REQUIRED_BONES")
    missing = sorted(need_bones - have_bones)
    if missing:
        problems.append(
            "Игра ищет кости, которых кузница не обещает: %s.\n"
            "  Это не падение, а тихая потеря: в такую часть тела просто нельзя\n"
            "  попасть, и заметно это станет в бою." % ", ".join(missing))

    words = game_animation_words()
    have_actions = forge_list("REQUIRED_ACTIONS")
    unreachable = sorted(a for a in have_actions if a not in words)
    if unreachable:
        problems.append(
            "Кузница делает анимации, которых игра не умеет попросить: %s.\n"
            "  `resolve` их не найдёт, они будут лежать в файле и никогда не\n"
            "  сыграют. Либо добавь имя в SYNONYMS в model_anim.gd, либо убери\n"
            "  анимацию из кузницы." % ", ".join(unreachable))

    if problems:
        print("ДОГОВОР РАЗОШЁЛСЯ\n")
        for i, text in enumerate(problems, 1):
            print("%d. %s\n" % (i, text))
        return 1

    print("договор цел: костей %d, анимаций %d" % (len(have_bones), len(have_actions)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
