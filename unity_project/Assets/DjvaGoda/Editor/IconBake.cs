// Иконки интерфейса — свои, кодом (решение автора от 02.10). Каждая иконка —
// набор простых фигур на поле [−1, 1]² (y вверх): круг, капсула, повёрнутый
// прямоугольник, дуга, полумесяц. У фигуры тёмный контур и лёгкий объём
// (светлее к верхнему левому краю); края сглажены пересчётом 4×4 на пиксель.
//
// «ДжваГода → Собрать иконки» (и вместе с текстурами): PNG 128² с
// прозрачностью в Resources/Icons — HUD берёт их по имени.
using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace DjvaGoda.EditorTools
{
    public static class IconBake
    {
        public const string Folder = "Assets/DjvaGoda/Resources/Icons";
        const int Size = 128;
        const int Sub = 4;
        const float Outline = 0.06f;
        static readonly Color Ink = new Color(0.08f, 0.06f, 0.05f, 1f);

        class Canvas
        {
            public readonly List<KeyValuePair<Func<Vector2, float>, Color>> Shapes = new List<KeyValuePair<Func<Vector2, float>, Color>>();
            public void Add(Func<Vector2, float> sdf, Color color) { Shapes.Add(new KeyValuePair<Func<Vector2, float>, Color>(sdf, color)); }

            public void Circle(float x, float y, float r, Color c) { Add(p => (p - new Vector2(x, y)).magnitude - r, c); }

            public void Ellipse(float x, float y, float rx, float ry, Color c)
            {
                Add(p =>
                {
                    var q = new Vector2((p.x - x) / rx, (p.y - y) / ry);
                    return (q.magnitude - 1f) * Mathf.Min(rx, ry);
                }, c);
            }

            public void Capsule(float ax, float ay, float bx, float by, float r, Color c)
            {
                var a = new Vector2(ax, ay);
                var b = new Vector2(bx, by);
                Add(p =>
                {
                    var pa = p - a;
                    var ba = b - a;
                    float h = Mathf.Clamp01(Vector2.Dot(pa, ba) / Vector2.Dot(ba, ba));
                    return (pa - ba * h).magnitude - r;
                }, c);
            }

            public void Box(float x, float y, float hw, float hh, float degrees, Color c)
            {
                float s = Mathf.Sin(-degrees * Mathf.Deg2Rad), co = Mathf.Cos(-degrees * Mathf.Deg2Rad);
                Add(p =>
                {
                    var d = p - new Vector2(x, y);
                    var q = new Vector2(Mathf.Abs(d.x * co - d.y * s) - hw, Mathf.Abs(d.x * s + d.y * co) - hh);
                    return new Vector2(Mathf.Max(q.x, 0f), Mathf.Max(q.y, 0f)).magnitude + Mathf.Min(Mathf.Max(q.x, q.y), 0f);
                }, c);
            }

            /// Дуга кольца радиусом r и толщиной w от угла a0 до a1 (градусы, против часовой от +x).
            public void Arc(float x, float y, float r, float w, float a0, float a1, Color c)
            {
                Add(p =>
                {
                    var d = p - new Vector2(x, y);
                    float a = Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg;
                    while (a < a0) a += 360f;
                    if (a <= a1) return Mathf.Abs(d.magnitude - r) - w;
                    var e0 = new Vector2(Mathf.Cos(a0 * Mathf.Deg2Rad), Mathf.Sin(a0 * Mathf.Deg2Rad)) * r;
                    var e1 = new Vector2(Mathf.Cos(a1 * Mathf.Deg2Rad), Mathf.Sin(a1 * Mathf.Deg2Rad)) * r;
                    return Mathf.Min((d - e0).magnitude, (d - e1).magnitude) - w;
                }, c);
            }

            /// Полумесяц: круг (x, y, r) без круга (cx, cy, cr) — лезвие топора.
            public void Crescent(float x, float y, float r, float cx, float cy, float cr, Color c)
            {
                Add(p => Mathf.Max((p - new Vector2(x, y)).magnitude - r, cr - (p - new Vector2(cx, cy)).magnitude), c);
            }
        }

        [MenuItem("ДжваГода/Собрать иконки")]
        public static void BakeAll()
        {
            Directory.CreateDirectory(Folder);
            var wood = new Color(0.55f, 0.36f, 0.2f);
            var woodLight = new Color(0.82f, 0.64f, 0.42f);
            var steel = new Color(0.78f, 0.8f, 0.84f);
            var darkSteel = new Color(0.35f, 0.36f, 0.4f);
            var gold = new Color(1f, 0.8f, 0.25f);
            var leather = new Color(0.42f, 0.27f, 0.15f);

            Save("res_0", c => // дерево — бревно
            {
                c.Capsule(-0.6f, -0.2f, 0.45f, 0.15f, 0.3f, wood);
                c.Ellipse(0.45f, 0.15f, 0.2f, 0.3f, woodLight);
                c.Ellipse(0.45f, 0.15f, 0.09f, 0.14f, wood);
            });
            Save("res_1", c => // камень
            {
                var grey = new Color(0.6f, 0.6f, 0.62f);
                c.Circle(-0.25f, -0.15f, 0.42f, grey);
                c.Circle(0.25f, -0.2f, 0.38f, new Color(0.52f, 0.52f, 0.55f));
                c.Circle(0.05f, 0.25f, 0.36f, new Color(0.68f, 0.68f, 0.7f));
            });
            Save("res_2", c => // золото — монеты
            {
                c.Circle(-0.3f, -0.3f, 0.36f, gold);
                c.Circle(0.32f, -0.25f, 0.36f, gold);
                c.Circle(0f, 0.25f, 0.38f, gold);
                c.Circle(0f, 0.25f, 0.2f, new Color(0.95f, 0.65f, 0.15f));
            });
            Save("res_3", c => // железо — слиток
            {
                c.Box(0f, -0.12f, 0.7f, 0.3f, 0f, darkSteel);
                c.Box(0f, 0.12f, 0.5f, 0.12f, 0f, steel);
            });
            Save("res_4", c => // еда — каравай
            {
                c.Ellipse(0f, -0.05f, 0.75f, 0.45f, new Color(0.78f, 0.5f, 0.22f));
                for (int i = -1; i <= 1; i++) c.Capsule(i * 0.3f - 0.1f, -0.2f, i * 0.3f + 0.12f, 0.15f, 0.04f, new Color(0.95f, 0.75f, 0.45f));
            });
            Save("res_5", c => // уголь
            {
                var coal = new Color(0.16f, 0.16f, 0.18f);
                c.Circle(-0.3f, -0.25f, 0.34f, coal);
                c.Circle(0.3f, -0.2f, 0.32f, coal);
                c.Circle(0f, 0.2f, 0.34f, new Color(0.24f, 0.24f, 0.27f));
            });

            Save("wpn_0", c => // меч
            {
                c.Capsule(-0.25f, -0.25f, 0.7f, 0.7f, 0.1f, steel);
                c.Capsule(-0.5f, -0.05f, -0.05f, -0.5f, 0.07f, darkSteel);
                c.Capsule(-0.32f, -0.32f, -0.62f, -0.62f, 0.06f, leather);
                c.Circle(-0.68f, -0.68f, 0.09f, gold);
            });
            Save("wpn_1", c => // лук
            {
                c.Arc(0.35f, 0f, 0.85f, 0.07f, 110f, 250f, wood);
                c.Capsule(0.06f, 0.8f, 0.06f, -0.8f, 0.02f, new Color(0.92f, 0.9f, 0.82f));
                c.Capsule(-0.35f, 0f, 0.45f, 0f, 0.035f, woodLight);
                c.Box(0.5f, 0f, 0.1f, 0.06f, 0f, darkSteel);
            });
            Save("wpn_2", c => // заклинание — огненный шар
            {
                c.Circle(0f, -0.1f, 0.55f, new Color(1f, 0.45f, 0.1f));
                c.Circle(0.05f, -0.05f, 0.33f, new Color(1f, 0.8f, 0.3f));
                c.Capsule(-0.2f, 0.3f, -0.05f, 0.75f, 0.12f, new Color(1f, 0.55f, 0.12f));
                c.Capsule(0.25f, 0.3f, 0.3f, 0.65f, 0.1f, new Color(1f, 0.55f, 0.12f));
            });
            Save("wpn_3", c => // топор
            {
                c.Capsule(-0.6f, -0.7f, 0.35f, 0.6f, 0.08f, wood);
                c.Crescent(0.25f, 0.45f, 0.45f, -0.25f, 0.85f, 0.4f, steel);
            });
            Save("wpn_4", c => // молот
            {
                c.Capsule(-0.6f, -0.7f, 0.25f, 0.4f, 0.08f, wood);
                c.Box(0.32f, 0.5f, 0.42f, 0.22f, 52f, darkSteel);
            });
            Save("wpn_5", c => // арбалет
            {
                c.Box(0f, -0.15f, 0.12f, 0.65f, 0f, wood);
                c.Arc(0f, -0.15f, 0.7f, 0.07f, 25f, 155f, darkSteel);
                c.Capsule(-0.63f, 0.15f, 0.63f, 0.15f, 0.02f, new Color(0.92f, 0.9f, 0.82f));
                c.Capsule(0f, -0.2f, 0f, 0.75f, 0.04f, darkSteel);
            });

            Save("ab_0", c => // лечение
            {
                var green = new Color(0.35f, 0.85f, 0.4f);
                c.Box(0f, 0f, 0.22f, 0.65f, 0f, green);
                c.Box(0f, 0f, 0.65f, 0.22f, 0f, green);
            });
            Save("ab_1", c => // клич — горн
            {
                c.Capsule(-0.55f, -0.35f, 0.3f, 0.2f, 0.12f, gold);
                c.Circle(0.42f, 0.28f, 0.28f, gold);
                c.Circle(0.42f, 0.28f, 0.14f, new Color(0.5f, 0.35f, 0.1f));
                c.Capsule(-0.7f, -0.45f, -0.55f, -0.35f, 0.08f, leather);
            });
            Save("ab_2", c => // призыв стаи белок — белка с хвостом-завитком
            {
                var fur = new Color(0.82f, 0.42f, 0.16f);
                var belly = new Color(0.96f, 0.86f, 0.68f);
                c.Circle(0.38f, 0.2f, 0.42f, fur);
                c.Circle(0.48f, 0.58f, 0.24f, fur);
                c.Ellipse(-0.18f, -0.28f, 0.34f, 0.4f, fur);
                c.Ellipse(-0.1f, -0.32f, 0.18f, 0.26f, belly);
                c.Circle(-0.32f, 0.22f, 0.24f, fur);
                c.Box(-0.4f, 0.48f, 0.06f, 0.12f, 15f, fur);
                c.Circle(-0.5f, 0.18f, 0.1f, belly);
                c.Circle(-0.27f, 0.28f, 0.075f, Ink);
                c.Ellipse(-0.05f, -0.68f, 0.22f, 0.07f, belly);
            });
            Save("ab_3", c => // паралич — цепь
            {
                var purple = new Color(0.65f, 0.35f, 0.95f);
                c.Arc(-0.28f, -0.2f, 0.32f, 0.08f, 0f, 360f, purple);
                c.Arc(0.28f, 0.2f, 0.32f, 0.08f, 0f, 360f, purple);
            });
            Save("ab_4", c => // увядание — череп
            {
                var bone = new Color(0.92f, 0.9f, 0.82f);
                c.Circle(0f, 0.15f, 0.55f, bone);
                c.Box(0f, -0.45f, 0.3f, 0.2f, 0f, bone);
                c.Circle(-0.22f, 0.12f, 0.15f, Ink);
                c.Circle(0.22f, 0.12f, 0.15f, Ink);
                c.Box(0f, -0.15f, 0.05f, 0.09f, 0f, Ink);
            });
            Save("ab_5", c => // ослепление — перечёркнутый глаз
            {
                c.Ellipse(0f, 0f, 0.75f, 0.42f, new Color(0.95f, 0.95f, 0.92f));
                c.Circle(0f, 0f, 0.26f, new Color(0.45f, 0.25f, 0.65f));
                c.Circle(0f, 0f, 0.11f, Ink);
                c.Capsule(-0.7f, -0.6f, 0.7f, 0.6f, 0.08f, new Color(0.9f, 0.2f, 0.2f));
            });

            Save("potion_heal", c => Flask(c, new Color(0.9f, 0.2f, 0.2f)));
            Save("potion_mana", c => Flask(c, new Color(0.25f, 0.45f, 0.95f)));
            Save("bandage", c =>
            {
                c.Circle(0f, 0f, 0.6f, new Color(0.95f, 0.94f, 0.9f));
                c.Arc(0f, 0f, 0.35f, 0.04f, 0f, 300f, new Color(0.75f, 0.73f, 0.7f));
                c.Box(0f, 0f, 0.08f, 0.2f, 0f, new Color(0.85f, 0.2f, 0.2f));
                c.Box(0f, 0f, 0.2f, 0.08f, 0f, new Color(0.85f, 0.2f, 0.2f));
            });
            Save("horse", c => c.Arc(0f, 0.05f, 0.55f, 0.15f, -50f, 230f, darkSteel));
            Save("arrows", c =>
            {
                for (int i = -1; i <= 1; i++)
                {
                    c.Capsule(-0.6f + i * 0.15f, -0.6f, 0.45f + i * 0.15f, 0.55f, 0.04f, woodLight);
                    c.Box(0.52f + i * 0.15f, 0.62f, 0.1f, 0.1f, 45f, darkSteel);
                }
            });

            AssetDatabase.Refresh();
            foreach (var path in Directory.GetFiles(Folder, "*.png")) Configure(path.Replace('\\', '/'));
            Debug.Log("[иконки] собрано в " + Folder);
        }

        static void Flask(Canvas c, Color liquid)
        {
            var glass = new Color(0.8f, 0.9f, 0.95f);
            c.Circle(0f, -0.25f, 0.5f, glass);
            c.Box(0f, 0.35f, 0.16f, 0.25f, 0f, glass);
            c.Circle(0f, -0.3f, 0.4f, liquid);
            c.Box(0f, 0.68f, 0.2f, 0.1f, 0f, new Color(0.55f, 0.36f, 0.2f));
            c.Circle(-0.15f, -0.15f, 0.08f, new Color(1f, 1f, 1f, 0.8f));
        }

        static void Save(string name, Action<Canvas> paint)
        {
            var canvas = new Canvas();
            paint(canvas);
            var texture = new Texture2D(Size, Size, TextureFormat.RGBA32, false);
            var pixels = new Color[Size * Size];
            for (int py = 0; py < Size; py++)
                for (int px = 0; px < Size; px++)
                {
                    var sum = new Color(0f, 0f, 0f, 0f);
                    for (int sy = 0; sy < Sub; sy++)
                        for (int sx = 0; sx < Sub; sx++)
                        {
                            var p = new Vector2(((px + (sx + 0.5f) / Sub) / Size) * 2f - 1f, ((py + (sy + 0.5f) / Sub) / Size) * 2f - 1f) * 1.1f;
                            sum += Sample(canvas, p);
                        }
                    pixels[py * Size + px] = sum / (Sub * Sub);
                }
            texture.SetPixels(pixels);
            texture.Apply();
            File.WriteAllBytes(Folder + "/" + name + ".png", texture.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(texture);
        }

        /// Цвет точки: фигуры по порядку, сверху — поздние; контур — тёмная кайма.
        static Color Sample(Canvas canvas, Vector2 p)
        {
            var result = new Color(0f, 0f, 0f, 0f);
            foreach (var shape in canvas.Shapes)
            {
                float d = shape.Key(p);
                if (d > Outline) continue;
                Color c;
                if (d > 0f) c = Ink;
                else
                {
                    // Объём: светлее к верхнему левому краю, темнее к нижнему правому.
                    float light = 1f + Mathf.Clamp((p.y - p.x) * 0.12f, -0.15f, 0.15f) + Mathf.Clamp(-d * 0.6f, 0f, 0.1f);
                    c = new Color(Mathf.Clamp01(shape.Value.r * light), Mathf.Clamp01(shape.Value.g * light), Mathf.Clamp01(shape.Value.b * light), shape.Value.a);
                }
                result = Over(c, result);
            }
            return result;
        }

        static Color Over(Color top, Color under)
        {
            float a = top.a + under.a * (1f - top.a);
            if (a <= 0f) return new Color(0f, 0f, 0f, 0f);
            return new Color((top.r * top.a + under.r * under.a * (1f - top.a)) / a, (top.g * top.a + under.g * under.a * (1f - top.a)) / a,
                (top.b * top.a + under.b * under.a * (1f - top.a)) / a, a);
        }

        static void Configure(string path)
        {
            var importer = AssetImporter.GetAtPath(path) as TextureImporter;
            if (importer == null) return;
            importer.textureType = TextureImporterType.Default;
            importer.alphaIsTransparency = true;
            importer.mipmapEnabled = false;
            importer.wrapMode = TextureWrapMode.Clamp;
            importer.filterMode = FilterMode.Bilinear;
            importer.SaveAndReimport();
        }
    }
}
