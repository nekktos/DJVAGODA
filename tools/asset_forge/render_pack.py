"""
Снять ПОКУПНУЮ модель тем же светом и той же камерой, что и свою.

ЗАЧЕМ. «Довести кузницу до качества паков» — это сравнение, а сравнивать по
памяти нельзя: свой персонаж всегда кажется хуже, пока не поставишь рядом. Здесь
Quaternius рендерится ровно тем же кодом просмотра, что и своя модель, и разница
видна честно, а не на ощупь.

Запуск:
  blender --background --factory-startup --python tools/asset_forge/render_pack.py -- \
      --model godot_project/assets/people/Warrior.gltf --render C:/куда/класть
"""

import argparse
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).parent))
import character as forge  # noqa: E402  — рендер берём оттуда, чтобы свет совпал


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--render", required=True)
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.model).resolve()))

    outdir = Path(args.render)
    outdir.mkdir(parents=True, exist_ok=True)
    cam = forge.setup_render(512)
    target = (0.0, 0.0, 1.45)
    forge.shoot(cam, target, (0.0, -5.8, 0.40), outdir / "pack_спереди.png")
    forge.shoot(cam, target, (-3.9, -4.4, 0.75), outdir / "pack_три_четверти.png")
    print("PACK_SHOTS %s" % outdir)


if __name__ == "__main__":
    main()
