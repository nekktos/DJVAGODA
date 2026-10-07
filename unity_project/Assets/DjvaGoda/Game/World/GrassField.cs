// Трава пучками вокруг камеры (решение автора от 02.10: трава — своя, кодом).
//
// Объектов в сцене нет: пучок — одна сетка (несколько тонких стеблей-конусов
// веером), рисуется инстансингом по клеткам 16 м в радиусе ~70 м от камеры,
// без теней. Расстановка в клетке — от номера клетки, одинакова у всех и при
// каждом заходе. На дорогах травы нет; высота — по рельефу.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class GrassField : MonoBehaviour
    {
        public const float Cell = 16f;
        public const int Radius = 5;
        /// Низкая графика (меню): трава только вблизи.
        public static int RadiusNow { get { return GameMenu.LowGraphics ? 3 : Radius; } }
        public const int TuftsPerCell = 70;
        const float RoadHalf = 8.5f;

        World _world;
        Mesh _tuft;
        Material _material;
        RenderParams _params;
        readonly Dictionary<long, Matrix4x4[]> _cells = new Dictionary<long, Matrix4x4[]>();

        void Start()
        {
            _world = Object.FindAnyObjectByType<World>();
            _tuft = Tuft();
            _material = Palette.Of("grass_blades");
            _params = new RenderParams(_material)
            {
                shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off,
                receiveShadows = true,
            };
        }

        /// Пучок: семь стеблей-конусов веером, разной высоты и наклона.
        static Mesh Tuft()
        {
            var combine = new List<CombineInstance>();
            var blade = BodyShapes.Cone(4);
            var rng = new System.Random(5);
            for (int i = 0; i < 7; i++)
            {
                float a = i * 51f;
                float tilt = 10f + (float)rng.NextDouble() * 25f;
                float h = 0.35f + (float)rng.NextDouble() * 0.35f;
                var m = Matrix4x4.TRS(new Vector3(((float)rng.NextDouble() - 0.5f) * 0.25f, 0f, ((float)rng.NextDouble() - 0.5f) * 0.25f),
                    Quaternion.Euler(0f, a, tilt), new Vector3(0.05f, h, 0.025f));
                combine.Add(new CombineInstance { mesh = blade, transform = m });
            }
            var mesh = new Mesh { name = "пучок травы" };
            mesh.CombineMeshes(combine.ToArray(), true, true);
            mesh.RecalculateBounds();
            return mesh;
        }

        Matrix4x4[] CellTufts(int cx, int cz)
        {
            long key = ((long)cx << 32) ^ (uint)cz;
            Matrix4x4[] tufts;
            if (_cells.TryGetValue(key, out tufts)) return tufts;
            var list = new List<Matrix4x4>(TuftsPerCell);
            var rng = new System.Random(cx * 73856093 ^ cz * 19349663);
            float half = MapLayout.WorldSize * 0.5f;
            for (int i = 0; i < TuftsPerCell; i++)
            {
                float x = (cx + (float)rng.NextDouble()) * Cell, z = (cz + (float)rng.NextDouble()) * Cell;
                float yaw = (float)rng.NextDouble() * 360f, size = 0.7f + (float)rng.NextDouble() * 0.8f;
                if (Mathf.Abs(x) > half || Mathf.Abs(z) > half || MapLayout.DistanceToRoad(x, z) < RoadHalf
                    || MapLayout.DistanceToRiver(x, z) < MapLayout.RiverWidth * 0.5f + 1f || MapLayout.InSea(x, z, 1f)
                    || MapLayout.InVillainRing(x, z, -15f)) continue;
                float y = _world.Relief.Height(x, z);
                list.Add(Matrix4x4.TRS(new Vector3(x, y - 0.02f, z), Quaternion.Euler(0f, yaw, 0f), Vector3.one * size));
            }
            tufts = list.ToArray();
            _cells[key] = tufts;
            return tufts;
        }

        void Update()
        {
            if (_world == null || _world.Relief == null || _tuft == null) return;
            var cam = Camera.main;
            if (cam == null) return;
            var at = cam.transform.position;
            // Сверху (вид стратега) трава не видна, а клеток вокруг — сотни: не рисуем.
            if (at.y - _world.Relief.Height(at.x, at.z) > 40f) return;
            int ox = Mathf.FloorToInt(at.x / Cell), oz = Mathf.FloorToInt(at.z / Cell);
            int radius = RadiusNow;
            for (int dx = -radius; dx <= radius; dx++)
                for (int dz = -radius; dz <= radius; dz++)
                {
                    if (dx * dx + dz * dz > radius * radius) continue;
                    var tufts = CellTufts(ox + dx, oz + dz);
                    if (tufts.Length > 0) Graphics.RenderMeshInstanced(_params, _tuft, 0, tufts);
                }
            // Память клеток не растёт без меры: дальние забываем.
            if (_cells.Count > 600) _cells.Clear();
        }
    }
}
