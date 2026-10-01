// Процедурные меши заглушек: рельеф, конус, вершина гряды, валун.
//
// Формы — те же, что в Godot-версии (rocks.gd, relief.gd), только вмятины
// считает шум ядра: одинаково на всех машинах.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Shapes
    {
        const int Segments = 10;
        const int Rings = 6;
        const float Dent = 0.34f;
        const float PeakDent = 0.20f;
        static readonly Dictionary<int, Mesh> Cache = new Dictionary<int, Mesh>();

        /// Рельеф одним полотном: клетка 16 м, все клетки, даже плоские (иначе
        /// по краям островов — ступеньки), общие вершины — для гладких нормалей.
        /// Вершины — сразу в осях Unity: высоту берём в точке ядра (x, −z).
        public static Mesh Relief(Relief relief, float worldSize)
        {
            float half = worldSize * 0.5f;
            int steps = Mathf.RoundToInt(worldSize / DjvaGoda.Core.Relief.Cell);
            int side = steps + 1;
            var vertices = new Vector3[side * side];
            var uv = new Vector2[side * side];
            for (int ix = 0; ix < side; ix++)
                for (int iz = 0; iz < side; iz++)
                {
                    float x = -half + ix * DjvaGoda.Core.Relief.Cell;
                    float z = -half + iz * DjvaGoda.Core.Relief.Cell;
                    vertices[ix * side + iz] = new Vector3(x, relief.Height(x, -z), z);
                    uv[ix * side + iz] = new Vector2(x / 8f, z / 8f);
                }
            var triangles = new int[steps * steps * 6];
            int t = 0;
            for (int ix = 0; ix < steps; ix++)
                for (int iz = 0; iz < steps; iz++)
                {
                    int a = ix * side + iz, b = (ix + 1) * side + iz, c = (ix + 1) * side + iz + 1, d = ix * side + iz + 1;
                    // Порядок обхода — лицом вверх в Unity (по часовой, если смотреть сверху).
                    triangles[t++] = a; triangles[t++] = d; triangles[t++] = c;
                    triangles[t++] = a; triangles[t++] = c; triangles[t++] = b;
                }
            var mesh = new Mesh { name = "Рельеф" };
            if (vertices.Length > 65000) mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            mesh.vertices = vertices;
            mesh.uv = uv;
            mesh.triangles = triangles;
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }

        /// Конус: крыша, шпиль. Радиус основания 1, высота 1, основание в y = −0.5.
        public static Mesh Cone()
        {
            Mesh cached;
            if (Cache.TryGetValue(-1, out cached) && cached != null) return cached;
            const int n = 8;
            var vertices = new List<Vector3>();
            var triangles = new List<int>();
            var top = new Vector3(0f, 0.5f, 0f);
            var bottom = new Vector3(0f, -0.5f, 0f);
            for (int i = 0; i < n; i++)
            {
                float a0 = 2f * Mathf.PI * i / n, a1 = 2f * Mathf.PI * (i + 1) / n;
                var p0 = new Vector3(Mathf.Cos(a0), -0.5f, Mathf.Sin(a0));
                var p1 = new Vector3(Mathf.Cos(a1), -0.5f, Mathf.Sin(a1));
                int s = vertices.Count;
                vertices.Add(p0); vertices.Add(top); vertices.Add(p1);
                triangles.Add(s); triangles.Add(s + 1); triangles.Add(s + 2);
                s = vertices.Count;
                vertices.Add(p0); vertices.Add(p1); vertices.Add(bottom);
                triangles.Add(s); triangles.Add(s + 1); triangles.Add(s + 2);
            }
            var mesh = new Mesh { name = "Конус", vertices = vertices.ToArray(), triangles = triangles.ToArray() };
            mesh.RecalculateNormals();
            Cache[-1] = mesh;
            return mesh;
        }

        /// Валун: шар со вмятинами, низ приплюснут. Габарит ±1 (масштаб — size/2).
        public static Mesh Rock(int seed)
        {
            int key = seed % 12;
            Mesh cached;
            if (Cache.TryGetValue(key, out cached) && cached != null) return cached;
            var noise = new SimplexNoise(7000 + key * 131);
            var grid = new Vector3[Rings + 1, Segments + 1];
            for (int ring = 0; ring <= Rings; ring++)
            {
                float phi = (float)ring / Rings * Mathf.PI;
                for (int seg = 0; seg <= Segments; seg++)
                {
                    float theta = (float)(seg % Segments) / Segments * 2f * Mathf.PI;
                    var dir = new Vector3(Mathf.Sin(phi) * Mathf.Cos(theta), Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(theta));
                    float dent = noise.Sample(dir.x * 2f + dir.y * 1.3f, dir.z * 2f - dir.y * 0.7f) * 0.5f + 0.5f;
                    float push = 1f + dent * Dent;
                    float squash = dir.y > -0.2f ? 1f : 0.55f;
                    grid[ring, seg] = new Vector3(dir.x * push, dir.y * push * squash, dir.z * push);
                }
            }
            var mesh = Stitch("Валун", grid, false);
            Cache[key] = mesh;
            return mesh;
        }

        /// Вершина гряды: конус с рёбрами и буграми. Основание y = 0, вершина y = 1, радиус 1.
        public static Mesh Peak(int seed)
        {
            int key = 1000 + seed % 12;
            Mesh cached;
            if (Cache.TryGetValue(key, out cached) && cached != null) return cached;
            var noise = new SimplexNoise(4400 + key * 97);
            var grid = new Vector3[Rings + 1, Segments + 1];
            for (int ring = 0; ring <= Rings; ring++)
            {
                float t = (float)ring / Rings;
                float profile = Mathf.Pow(t, 0.62f);
                float y = 1f - t;
                for (int seg = 0; seg <= Segments; seg++)
                {
                    float theta = (float)(seg % Segments) / Segments * 2f * Mathf.PI;
                    float ridged = 1f + Mathf.Cos(theta * 3f + key) * 0.16f * t;
                    float lump = 1f + (noise.Sample(Mathf.Cos(theta) * 2f + y, Mathf.Sin(theta) * 2f - y) * 0.5f + 0.5f) * PeakDent;
                    float r = profile * ridged * lump;
                    grid[ring, seg] = new Vector3(Mathf.Cos(theta) * r, y, Mathf.Sin(theta) * r);
                }
            }
            var mesh = Stitch("Вершина", grid, true);
            Cache[key] = mesh;
            return mesh;
        }

        static Mesh Stitch(string name, Vector3[,] grid, bool floor)
        {
            var vertices = new List<Vector3>();
            var triangles = new List<int>();
            for (int ring = 0; ring < Rings; ring++)
                for (int seg = 0; seg < Segments; seg++)
                {
                    var a = grid[ring, seg];
                    var b = grid[ring, seg + 1];
                    var c = grid[ring + 1, seg + 1];
                    var d = grid[ring + 1, seg];
                    Quad(vertices, triangles, a, b, c, d);
                }
            if (floor)
            {
                var centre = new Vector3(0f, -0.02f, 0f);
                for (int seg = 0; seg < Segments; seg++)
                {
                    int s = vertices.Count;
                    // Дно смотрит вниз.
                    vertices.Add(centre); vertices.Add(grid[Rings, seg]); vertices.Add(grid[Rings, seg + 1]);
                    triangles.Add(s); triangles.Add(s + 1); triangles.Add(s + 2);
                }
            }
            var mesh = new Mesh { name = name, vertices = vertices.ToArray(), triangles = triangles.ToArray() };
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }

        /// Грань из двух треугольников. Лицо в Unity — куда смотрит
        /// cross(v1 − v0, v2 − v0). Кольца идут сверху вниз, угол растёт — тогда
        /// (a, b, c) смотрит наружу; проверено на экваторе валуна и боку вершины.
        static void Quad(List<Vector3> vertices, List<int> triangles, Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            int s = vertices.Count;
            vertices.Add(a); vertices.Add(b); vertices.Add(c); vertices.Add(d);
            triangles.Add(s); triangles.Add(s + 1); triangles.Add(s + 2);
            triangles.Add(s); triangles.Add(s + 2); triangles.Add(s + 3);
        }
    }
}
