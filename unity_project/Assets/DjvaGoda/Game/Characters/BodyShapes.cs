// Процедурные сетки для людей и зверей (решение автора от 02.10: модели —
// свои, кодом). Всё собирается из немногих примитивов, каждый — одна сетка на
// все копии (кэш по ключу):
//   Loft — тело вращения по профилю колец с эллиптическим сечением: руки,
//          ноги, торс, шея, юбка рубахи, сапоги, хвост;
//   Ellipsoid — голова, кисти, ступни, морды; Dome — шлем, капюшон, наплечник;
//   Cone — рога, уши, шляпа, наконечники; Cape — изогнутое полотно плаща.
// Развёртки нет: материалы трипланарные (Palette.Moving).
using System.Collections.Generic;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class BodyShapes
    {
        /// Кольцо профиля: высота, полуоси сечения, сдвиг центра вперёд (z).
        public struct Ring
        {
            public float Y, Rx, Rz, Z;

            public Ring(float y, float rx, float rz, float z = 0f)
            {
                Y = y;
                Rx = rx;
                Rz = rz;
                Z = z;
            }
        }

        static readonly Dictionary<string, Mesh> Cache = new Dictionary<string, Mesh>();

        static Mesh Cached(string key, System.Func<Mesh> make)
        {
            Mesh mesh;
            if (Cache.TryGetValue(key, out mesh) && mesh != null) return mesh;
            mesh = make();
            mesh.name = key;
            mesh.RecalculateBounds();
            Cache[key] = mesh;
            return mesh;
        }

        /// Тело вращения по кольцам снизу вверх (или сверху вниз — порядок любой),
        /// с крышками на концах.
        public static Mesh Loft(string key, Ring[] rings, int segments = 10)
        {
            return Cached("loft " + key, () =>
            {
                var vertices = new List<Vector3>();
                var triangles = new List<int>();
                for (int r = 0; r < rings.Length; r++)
                    for (int s = 0; s <= segments; s++)
                    {
                        float a = s * Mathf.PI * 2f / segments;
                        vertices.Add(new Vector3(Mathf.Cos(a) * rings[r].Rx, rings[r].Y, rings[r].Z + Mathf.Sin(a) * rings[r].Rz));
                    }
                bool up = rings[rings.Length - 1].Y >= rings[0].Y;
                for (int r = 0; r < rings.Length - 1; r++)
                    for (int s = 0; s < segments; s++)
                    {
                        int a = r * (segments + 1) + s, b = a + 1, c = a + segments + 1, d = c + 1;
                        if (up) { triangles.Add(a); triangles.Add(c); triangles.Add(b); triangles.Add(b); triangles.Add(c); triangles.Add(d); }
                        else { triangles.Add(a); triangles.Add(b); triangles.Add(c); triangles.Add(b); triangles.Add(d); triangles.Add(c); }
                    }
                Cap(vertices, triangles, rings[0], 0, segments, !up);
                Cap(vertices, triangles, rings[rings.Length - 1], (rings.Length - 1) * (segments + 1), segments, up);
                return Build(vertices, triangles);
            });
        }

        static void Cap(List<Vector3> vertices, List<int> triangles, Ring ring, int start, int segments, bool top)
        {
            if (ring.Rx <= 0.0001f && ring.Rz <= 0.0001f) return;
            int centre = vertices.Count;
            vertices.Add(new Vector3(0f, ring.Y, ring.Z));
            for (int s = 0; s < segments; s++)
            {
                if (top) { triangles.Add(centre); triangles.Add(start + s + 1); triangles.Add(start + s); }
                else { triangles.Add(centre); triangles.Add(start + s); triangles.Add(start + s + 1); }
            }
        }

        /// Эллипсоид диаметром 1 (масштаб задаёт форму).
        public static Mesh Ellipsoid(int segments = 12, int rings = 8)
        {
            return Cached("ellipsoid " + segments + "x" + rings, () => Sphere(segments, rings, 0f));
        }

        /// Купол: верхняя половина сферы диаметром 1, с донцем.
        public static Mesh Dome(int segments = 12, int rings = 5)
        {
            return Cached("dome " + segments + "x" + rings, () => Sphere(segments, rings, 0.5f));
        }

        /// Сфера: from — с какой доли высоты начинать (0 — целая, 0.5 — купол).
        static Mesh Sphere(int segments, int rings, float from)
        {
            var vertices = new List<Vector3>();
            var triangles = new List<int>();
            int total = from > 0f ? rings * 2 : rings;
            int first = from > 0f ? rings : 0;
            for (int r = first; r <= total; r++)
            {
                float phi = Mathf.PI * (1f - (float)r / total);
                for (int s = 0; s <= segments; s++)
                {
                    float a = s * Mathf.PI * 2f / segments;
                    vertices.Add(new Vector3(Mathf.Sin(phi) * Mathf.Cos(a) * 0.5f, Mathf.Cos(phi) * 0.5f, Mathf.Sin(phi) * Mathf.Sin(a) * 0.5f));
                }
            }
            int rowCount = total - first;
            for (int r = 0; r < rowCount; r++)
                for (int s = 0; s < segments; s++)
                {
                    int a = r * (segments + 1) + s, b = a + 1, c = a + segments + 1, d = c + 1;
                    triangles.Add(a); triangles.Add(c); triangles.Add(b);
                    triangles.Add(b); triangles.Add(c); triangles.Add(d);
                }
            if (from > 0f)
            {
                int centre = vertices.Count;
                vertices.Add(Vector3.zero);
                for (int s = 0; s < segments; s++) { triangles.Add(centre); triangles.Add(s); triangles.Add(s + 1); }
            }
            return Build(vertices, triangles);
        }

        /// Конус: основание радиусом 0.5 в y = 0, вершина в y = 1.
        public static Mesh Cone(int segments = 10)
        {
            return Cached("cone " + segments, () =>
                Raw(new[] { new Ring(0f, 0.5f, 0.5f), new Ring(1f, 0.0001f, 0.0001f) }, segments));
        }

        static Mesh Raw(Ring[] rings, int segments)
        {
            var vertices = new List<Vector3>();
            var triangles = new List<int>();
            for (int r = 0; r < rings.Length; r++)
                for (int s = 0; s <= segments; s++)
                {
                    float a = s * Mathf.PI * 2f / segments;
                    vertices.Add(new Vector3(Mathf.Cos(a) * rings[r].Rx, rings[r].Y, Mathf.Sin(a) * rings[r].Rz));
                }
            for (int s = 0; s < segments; s++)
            {
                int a = s, b = a + 1, c = a + segments + 1, d = c + 1;
                triangles.Add(a); triangles.Add(c); triangles.Add(b);
                triangles.Add(b); triangles.Add(c); triangles.Add(d);
            }
            Cap(vertices, triangles, rings[0], 0, segments, false);
            return Build(vertices, triangles);
        }

        /// Плащ: полотно шириной 1 и высотой 1 (верх в y = 0, вниз до −1),
        /// выгнутое назад (−z) и расширяющееся книзу; двустороннее.
        public static Mesh Cape()
        {
            return Cached("cape", () =>
            {
                const int cols = 8, rows = 8;
                var vertices = new List<Vector3>();
                var triangles = new List<int>();
                for (int side = 0; side < 2; side++)
                    for (int r = 0; r <= rows; r++)
                        for (int c = 0; c <= cols; c++)
                        {
                            float fx = (float)c / cols - 0.5f, fy = (float)r / rows;
                            float width = 1f + fy * 0.5f;
                            float bulge = -Mathf.Cos(fx * Mathf.PI) * 0.12f - fy * 0.15f;
                            vertices.Add(new Vector3(fx * width, -fy, bulge + (side == 0 ? 0f : 0.01f)));
                        }
                int stride = cols + 1, half = stride * (rows + 1);
                for (int r = 0; r < rows; r++)
                    for (int c = 0; c < cols; c++)
                    {
                        int a = r * stride + c, b = a + 1, d = a + stride, e = d + 1;
                        triangles.Add(a); triangles.Add(b); triangles.Add(d);
                        triangles.Add(b); triangles.Add(e); triangles.Add(d);
                        triangles.Add(half + a); triangles.Add(half + d); triangles.Add(half + b);
                        triangles.Add(half + b); triangles.Add(half + d); triangles.Add(half + e);
                    }
                return Build(vertices, triangles);
            });
        }

        static Mesh Build(List<Vector3> vertices, List<int> triangles)
        {
            var mesh = new Mesh();
            mesh.SetVertices(vertices);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateNormals();
            return mesh;
        }

        /// Часть тела: сетка с материалом под родителем.
        public static Transform Part(Transform parent, string name, Mesh mesh, string material, Vector3 at, Vector3 scale,
            Quaternion? rotation = null)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = at;
            go.transform.localScale = scale;
            if (rotation.HasValue) go.transform.localRotation = rotation.Value;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var view = go.AddComponent<MeshRenderer>();
            view.sharedMaterial = Palette.Moving(material);
            return go.transform;
        }

        /// Сустав: пустой узел, вокруг которого крутится часть.
        public static Transform Joint(Transform parent, string name, Vector3 at)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = at;
            return go.transform;
        }
    }
}
