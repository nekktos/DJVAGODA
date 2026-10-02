// Модели оружия и снарядов — свои, кодом (решение автора от 02.10). Ось
// оружия — +y от рукояти к острию/бойку (держат за начало координат); лук —
// дуга в плоскости yz, тетива сзади; арбалет — ложе вдоль +z.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class WeaponShapes
    {
        static Transform Root(string name)
        {
            return new GameObject(name).transform;
        }

        static Transform P(Transform root, string name, Mesh mesh, string material, Vector3 at, Vector3 scale, Vector3? euler = null)
        {
            return BodyShapes.Part(root, name, mesh, material, at, scale, euler.HasValue ? Quaternion.Euler(euler.Value) : (Quaternion?)null);
        }

        static Mesh Grip() { return BodyShapes.Loft("рукоять", new[] { new BodyShapes.Ring(-0.12f, 0.018f, 0.018f), new BodyShapes.Ring(0.12f, 0.016f, 0.016f) }, 6); }

        public static Transform Build(WeaponKind kind)
        {
            var root = Root("Оружие: " + Weapons.Names[(int)kind]);
            var e = BodyShapes.Ellipsoid(8, 6);
            switch (kind)
            {
                case WeaponKind.Sword:
                    P(root, "Рукоять", Grip(), "leather", new Vector3(0f, 0.02f, 0f), Vector3.one);
                    P(root, "Навершие", e, "dark_metal", new Vector3(0f, -0.12f, 0f), new Vector3(0.05f, 0.05f, 0.05f));
                    P(root, "Гарда", BodyShapes.Loft("гарда", new[] { new BodyShapes.Ring(-0.13f, 0.018f, 0.018f), new BodyShapes.Ring(0.13f, 0.014f, 0.014f) }, 6),
                        "dark_metal", new Vector3(0f, 0.15f, 0f), Vector3.one, new Vector3(0f, 0f, 90f));
                    // Клинок: плоский, сужается к острию, по середине — дол (рёбра сечения).
                    P(root, "Клинок", BodyShapes.Loft("клинок", new[]
                    {
                        new BodyShapes.Ring(0f, 0.032f, 0.007f), new BodyShapes.Ring(0.7f, 0.026f, 0.006f), new BodyShapes.Ring(0.86f, 0.0005f, 0.0005f),
                    }, 6), "metal", new Vector3(0f, 0.16f, 0f), Vector3.one);
                    break;
                case WeaponKind.Axe:
                    P(root, "Топорище", BodyShapes.Loft("топорище", new[] { new BodyShapes.Ring(-0.1f, 0.022f, 0.022f), new BodyShapes.Ring(0.62f, 0.018f, 0.018f) }, 6),
                        "wood", Vector3.zero, Vector3.one);
                    // Лезвие: клин с полукруглым краем.
                    P(root, "Обух", Box(), "dark_metal", new Vector3(0f, 0.55f, 0f), new Vector3(0.06f, 0.08f, 0.05f));
                    P(root, "Лезвие", BodyShapes.Dome(10, 4), "metal", new Vector3(0f, 0.55f, 0.03f), new Vector3(0.025f, 0.2f, 0.22f), new Vector3(90f, 0f, 0f));
                    break;
                case WeaponKind.Hammer:
                    P(root, "Рукоять", BodyShapes.Loft("молот рукоять", new[] { new BodyShapes.Ring(-0.1f, 0.025f, 0.025f), new BodyShapes.Ring(0.7f, 0.022f, 0.022f) }, 6),
                        "wood", Vector3.zero, Vector3.one);
                    P(root, "Боёк", BodyShapes.Loft("молот боёк", new[]
                    {
                        new BodyShapes.Ring(-0.17f, 0.075f, 0.075f), new BodyShapes.Ring(-0.12f, 0.085f, 0.085f), new BodyShapes.Ring(0.12f, 0.085f, 0.085f),
                        new BodyShapes.Ring(0.17f, 0.075f, 0.075f),
                    }, 8), "dark_metal", new Vector3(0f, 0.72f, 0f), Vector3.one, new Vector3(0f, 0f, 90f));
                    break;
                case WeaponKind.Bow:
                    Bow(root);
                    break;
                case WeaponKind.Crossbow:
                    P(root, "Ложе", Box(), "wood", new Vector3(0f, 0f, 0.25f), new Vector3(0.06f, 0.07f, 0.7f));
                    P(root, "Дуга", BodyShapes.Loft("арбалет дуга", new[]
                    {
                        new BodyShapes.Ring(-0.34f, 0.012f, 0.012f, 0.06f), new BodyShapes.Ring(0f, 0.022f, 0.022f), new BodyShapes.Ring(0.34f, 0.012f, 0.012f, 0.06f),
                    }, 6), "dark_metal", new Vector3(0f, 0.02f, 0.55f), Vector3.one, new Vector3(0f, 0f, 90f));
                    P(root, "Тетива", Box(), "linen", new Vector3(0f, 0.02f, 0.47f), new Vector3(0.66f, 0.008f, 0.008f));
                    P(root, "Болт", Box(), "dark_metal", new Vector3(0f, 0.06f, 0.4f), new Vector3(0.015f, 0.015f, 0.35f));
                    break;
                default:
                    // Огненный шар в ладони.
                    var fire = P(root, "Пламя", e, "dark_metal", new Vector3(0f, 0.12f, 0.05f), Vector3.one * 0.22f);
                    fire.GetComponent<MeshRenderer>().sharedMaterial = Palette.Glow("fire");
                    break;
            }
            return root;
        }

        /// Лук: дуга из коротких отрезков по окружности, тетива — прямая сзади.
        static void Bow(Transform root)
        {
            const int pieces = 7;
            const float radius = 0.75f, span = 1.2f;
            var limb = BodyShapes.Loft("лук отрезок", new[] { new BodyShapes.Ring(-0.5f, 0.016f, 0.02f), new BodyShapes.Ring(0.5f, 0.016f, 0.02f) }, 6);
            for (int i = 0; i < pieces; i++)
            {
                float a = ((i + 0.5f) / pieces - 0.5f) * span;
                var at = new Vector3(0f, Mathf.Sin(a) * radius, Mathf.Cos(a) * radius - radius + 0.06f);
                float length = span * radius / pieces;
                P(root, "Плечо лука", limb, "wood", at, new Vector3(1f, length, 1f), new Vector3(-a * Mathf.Rad2Deg, 0f, 0f));
            }
            float tip = Mathf.Sin(span * 0.5f) * radius;
            float back = Mathf.Cos(span * 0.5f) * radius - radius + 0.06f;
            P(root, "Тетива", Box(), "linen", new Vector3(0f, 0f, back), new Vector3(0.006f, tip * 2f, 0.006f));
            P(root, "Рукоять лука", Grip(), "leather", new Vector3(0f, 0f, 0.06f), new Vector3(1.4f, 0.5f, 1.4f));
        }

        /// Стрела или болт в полёте: древко, наконечник, оперение; ось — +z.
        public static Transform Arrow(bool bolt)
        {
            var root = Root(bolt ? "Болт" : "Стрела");
            float length = bolt ? 0.45f : 0.8f;
            P(root, "Древко", Box(), "wood", Vector3.zero, new Vector3(0.018f, 0.018f, length));
            P(root, "Наконечник", BodyShapes.Cone(6), "dark_metal", new Vector3(0f, 0f, length * 0.5f), new Vector3(0.05f, 0.1f, 0.05f), new Vector3(90f, 0f, 0f));
            for (int i = 0; i < 3; i++)
                P(root, "Перо", Box(), bolt ? "leather" : "linen", new Vector3(0f, 0f, -length * 0.45f), new Vector3(0.004f, 0.07f, 0.12f), new Vector3(0f, 0f, i * 120f));
            return root;
        }

        static Mesh _box;

        static Mesh Box()
        {
            if (_box == null)
            {
                var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
                _box = cube.GetComponent<MeshFilter>().sharedMesh;
                Object.Destroy(cube);
            }
            return _box;
        }
    }
}
