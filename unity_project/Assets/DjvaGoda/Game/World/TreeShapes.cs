// Процедурные деревья: ели и лиственные, по нескольку вариантов каждой породы.
//
// Стиль — GDD: low-poly с плоской заливкой (у каждой грани свои вершины,
// нормаль грани — общая), без текстур. Формы считает генератор ядра (Rng) по
// зерну варианта: на всех машинах деревья одинаковы.
//
// Дерево — меш высотой Forest.CrownTop от основания (y = 0); размер дерева
// задаётся равномерным масштабом, как в Godot-версии (forest.gd). Две части
// меша: 0 — кора, 1 — листва/хвоя.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public enum TreeKind { Spruce, Broadleaf }

    public static class TreeShapes
    {
        public const int Variants = 8;
        /// Доля елей в лесу эльфов.
        public const float SpruceShare = 0.6f;
        static readonly Dictionary<int, Mesh> Cache = new Dictionary<int, Mesh>();

        /// Порода и вариант дерева по его номеру — одинаково у всех.
        public static void Pick(int index, out TreeKind kind, out int variant)
        {
            var rng = new Rng(91011L + index * 7919L);
            kind = rng.NextDouble() < SpruceShare ? TreeKind.Spruce : TreeKind.Broadleaf;
            variant = rng.Next(Variants);
        }

        public static Mesh Get(TreeKind kind, int variant)
        {
            int key = (int)kind * 100 + variant;
            Mesh mesh;
            if (Cache.TryGetValue(key, out mesh) && mesh != null) return mesh;
            var b = new Builder();
            var rng = new Rng(5000L + key * 104729L);
            if (kind == TreeKind.Spruce) Spruce(b, rng);
            else Broadleaf(b, rng);
            mesh = b.ToMesh((kind == TreeKind.Spruce ? "Ель " : "Лиственное ") + variant);
            Cache[key] = mesh;
            return mesh;
        }

        static float Range(Rng rng, float low, float high) { return low + (float)rng.NextDouble() * (high - low); }

        /// Ель: прямой ствол, ярусы-конусы с рваным краем, к верху уже.
        static void Spruce(Builder b, Rng rng)
        {
            float h = Forest.CrownTop;
            var lean = new Vector3(Range(rng, -0.4f, 0.4f), 0f, Range(rng, -0.4f, 0.4f));
            b.Tube(0, Vector3.zero, new Vector3(0f, h * 0.9f, 0f) + lean, 0.55f, 0.08f, 6, 3, lean * 0.3f);
            int tiers = 4 + rng.Next(3);
            float bottom = h * Range(rng, 0.18f, 0.28f);
            float span = h - bottom;
            for (int i = 0; i < tiers; i++)
            {
                float t = (float)i / tiers;
                float baseY = bottom + span * t * 0.92f;
                float tierHeight = span / tiers * 1.9f;
                if (baseY + tierHeight > h) tierHeight = h - baseY;
                float radius = Mathf.Lerp(4.2f, 1.1f, t) * Range(rng, 0.85f, 1.1f);
                var centre = new Vector3(0f, baseY, 0f) + lean * (baseY / h);
                b.Cone(1, centre, radius, tierHeight, 9, rng, 0.22f);
            }
        }

        /// Лиственное: ствол с изгибом, 3–5 ветвей вверх-наружу, крона из
        /// комков на концах ветвей и на макушке.
        static void Broadleaf(Builder b, Rng rng)
        {
            float h = Forest.CrownTop;
            var top = new Vector3(Range(rng, -0.8f, 0.8f), h * 0.62f, Range(rng, -0.8f, 0.8f));
            var bend = new Vector3(Range(rng, -0.6f, 0.6f), 0f, Range(rng, -0.6f, 0.6f));
            b.Tube(0, Vector3.zero, top, 0.7f, 0.32f, 7, 4, bend);
            var tips = new List<Vector3> { top + new Vector3(0f, 2.5f, 0f) };
            int branches = 3 + rng.Next(3);
            float turn = Range(rng, 0f, Mathf.PI * 2f);
            for (int i = 0; i < branches; i++)
            {
                float a = turn + Mathf.PI * 2f * i / branches + Range(rng, -0.3f, 0.3f);
                float from = Range(rng, 0.55f, 0.95f);
                var start = Vector3.Lerp(Vector3.zero, top, from) + bend * Mathf.Sin(from * Mathf.PI);
                var dir = new Vector3(Mathf.Cos(a), Range(rng, 0.7f, 1.2f), Mathf.Sin(a)).normalized;
                var end = start + dir * Range(rng, 4f, 6.5f);
                b.Tube(0, start, end, 0.3f, 0.1f, 5, 2, Vector3.zero);
                tips.Add(end);
            }
            foreach (var tip in tips)
            {
                float r = Range(rng, 3f, 4.3f);
                // Комки не выше макушки дерева: высота меша — ровно CrownTop.
                var at = tip;
                if (at.y + r * 0.8f > h) at.y = h - r * 0.8f;
                b.Lump(1, at, new Vector3(r, r * 0.8f, r), rng, 0.25f);
            }
        }

        /// Сборщик меша с плоской заливкой: у каждого треугольника свои вершины.
        class Builder
        {
            readonly List<Vector3> _vertices = new List<Vector3>();
            readonly List<int>[] _parts = { new List<int>(), new List<int>() };

            /// Треугольник лицом наружу — от точки inside. Лицо в Unity — куда
            /// смотрит cross(b − a, c − a) (проверено на валунах, Shapes.Quad).
            public void Tri(int part, Vector3 a, Vector3 b, Vector3 c, Vector3 inside)
            {
                var n = Vector3.Cross(b - a, c - a);
                if (Vector3.Dot(n, (a + b + c) / 3f - inside) < 0f)
                {
                    var swap = b;
                    b = c;
                    c = swap;
                }
                int s = _vertices.Count;
                _vertices.Add(a);
                _vertices.Add(b);
                _vertices.Add(c);
                _parts[part].Add(s);
                _parts[part].Add(s + 1);
                _parts[part].Add(s + 2);
            }

            /// Сужающаяся труба от p0 к p1 с изгибом (смещение середины на bend).
            public void Tube(int part, Vector3 p0, Vector3 p1, float r0, float r1, int sides, int rings, Vector3 bend)
            {
                var axis = (p1 - p0).normalized;
                var u = Vector3.Cross(axis, Mathf.Abs(axis.y) < 0.9f ? Vector3.up : Vector3.right).normalized;
                var v = Vector3.Cross(axis, u);
                var centres = new Vector3[rings + 1];
                var ring = new Vector3[rings + 1, sides];
                for (int k = 0; k <= rings; k++)
                {
                    float t = (float)k / rings;
                    centres[k] = Vector3.Lerp(p0, p1, t) + bend * Mathf.Sin(t * Mathf.PI);
                    float r = Mathf.Lerp(r0, r1, t);
                    for (int j = 0; j < sides; j++)
                    {
                        float a = Mathf.PI * 2f * j / sides;
                        ring[k, j] = centres[k] + (u * Mathf.Cos(a) + v * Mathf.Sin(a)) * r;
                    }
                }
                for (int k = 0; k < rings; k++)
                {
                    var inside = (centres[k] + centres[k + 1]) * 0.5f;
                    for (int j = 0; j < sides; j++)
                    {
                        int n = (j + 1) % sides;
                        Tri(part, ring[k, j], ring[k, n], ring[k + 1, n], inside);
                        Tri(part, ring[k, j], ring[k + 1, n], ring[k + 1, j], inside);
                    }
                }
                // Торец сверху: у ветви он виден.
                var cap = centres[rings] - axis * 0.01f;
                for (int j = 0; j < sides; j++)
                    Tri(part, centres[rings], ring[rings, j], ring[rings, (j + 1) % sides], cap);
            }

            /// Ярус ели: конус с рваным краем и днищем.
            public void Cone(int part, Vector3 baseCentre, float radius, float height, int sides, Rng rng, float jitter)
            {
                var apex = baseCentre + new Vector3(0f, height, 0f);
                var inside = baseCentre + new Vector3(0f, height * 0.3f, 0f);
                var rim = new Vector3[sides];
                float turn = (float)rng.NextDouble() * Mathf.PI * 2f;
                for (int j = 0; j < sides; j++)
                {
                    float a = turn + Mathf.PI * 2f * j / sides;
                    float r = radius * (1f + ((float)rng.NextDouble() * 2f - 1f) * jitter);
                    // Край свисает: зубцы ниже основания.
                    float droop = (float)rng.NextDouble() * height * 0.12f;
                    rim[j] = baseCentre + new Vector3(Mathf.Cos(a) * r, -droop, Mathf.Sin(a) * r);
                }
                for (int j = 0; j < sides; j++)
                {
                    int n = (j + 1) % sides;
                    Tri(part, apex, rim[j], rim[n], inside);
                    Tri(part, baseCentre, rim[n], rim[j], inside + new Vector3(0f, height, 0f));
                }
            }

            static readonly Vector3[] Ico;
            static readonly int[] IcoFaces =
            {
                0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
                3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
            };

            static Builder()
            {
                float t = (1f + Mathf.Sqrt(5f)) * 0.5f;
                Ico = new[]
                {
                    new Vector3(-1, t, 0), new Vector3(1, t, 0), new Vector3(-1, -t, 0), new Vector3(1, -t, 0),
                    new Vector3(0, -1, t), new Vector3(0, 1, t), new Vector3(0, -1, -t), new Vector3(0, 1, -t),
                    new Vector3(t, 0, -1), new Vector3(t, 0, 1), new Vector3(-t, 0, -1), new Vector3(-t, 0, 1),
                };
                for (int i = 0; i < Ico.Length; i++) Ico[i] = Ico[i].normalized;
            }

            /// Комок кроны: икосаэдр со сдвинутыми вершинами, сплюснутый по radii.
            public void Lump(int part, Vector3 centre, Vector3 radii, Rng rng, float jitter)
            {
                var points = new Vector3[Ico.Length];
                for (int i = 0; i < Ico.Length; i++)
                {
                    float push = 1f + ((float)rng.NextDouble() * 2f - 1f) * jitter;
                    points[i] = centre + Vector3.Scale(Ico[i], radii) * push;
                }
                for (int f = 0; f < IcoFaces.Length; f += 3)
                    Tri(part, points[IcoFaces[f]], points[IcoFaces[f + 1]], points[IcoFaces[f + 2]], centre);
            }

            public Mesh ToMesh(string name)
            {
                var mesh = new Mesh { name = name };
                mesh.SetVertices(_vertices);
                mesh.subMeshCount = 2;
                mesh.SetTriangles(_parts[0], 0);
                mesh.SetTriangles(_parts[1], 1);
                mesh.RecalculateNormals();
                mesh.RecalculateBounds();
                return mesh;
            }
        }
    }
}
