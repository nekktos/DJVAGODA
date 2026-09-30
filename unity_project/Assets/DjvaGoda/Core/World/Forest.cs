// Лес зоны эльфов (перенос forest.gd): 1700 деревьев кольцом вокруг поселения,
// с неровной кромкой, поляной посередине и полянами под шахты.
//
// Дерево адресуется НОМЕРОМ: хост рубит по номеру, клиенты валят по номеру,
// опоздавшему досылают список поваленных. Зерно одно — лес одинаков у всех.
// Рядом с живыми — твёрдые стволы (70 м, отпускание 88), у камеры — объёмные
// (110/135); дальше — плоские двойники. Разница радиусов входа и выхода —
// чтобы дерево на границе не мигало.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public class Forest
    {
        public const int TreeCount = 1700;
        public const int Seed = 3615;
        public const float Clearing = 70f;
        public const float SolidRadius = 70f;
        public const float SolidRelease = 88f;
        public const float VisualRadius = 110f;
        public const float VisualRelease = 135f;
        public const float UpdateInterval = 0.125f;
        public const float Cell = 32f;
        public const float TrunkHeight = 11f;
        public const float TrunkRadius = 1.1f;
        public const float CrownRadius = 4.4f;
        public const float CrownBase = 10f;
        public const float CrownTop = 22f;

        public readonly List<V3> Positions = new List<V3>();
        public readonly List<float> Scales = new List<float>();
        readonly List<int> _hits = new List<int>();
        readonly List<bool> _felled = new List<bool>();
        readonly Dictionary<long, List<int>> _cells = new Dictionary<long, List<int>>();

        /// Лес карты: кольцо в зоне эльфов, поляны под все четыре шахты.
        public static Forest ForMap()
        {
            var holes = new List<KeyValuePair<V3, float>>();
            foreach (var mine in MapLayout.Mines) holes.Add(new KeyValuePair<V3, float>(mine.At, MapLayout.MineClearing));
            return new Forest(MapLayout.ZoneCenters[(int)Zone.Elves], MapLayout.ZoneHalf - 30f, Clearing, Seed, holes);
        }

        public Forest(V3 centre, float radius, float clearing, int seed, IList<KeyValuePair<V3, float>> holes)
        {
            var rng = new Random(seed);
            int attempts = 0;
            while (Positions.Count < TreeCount && attempts < TreeCount * 4)
            {
                attempts++;
                double a = rng.NextDouble() * 2.0 * Math.PI;
                // Кромка леса волнистая, а не циркульная: три гармоники.
                double wobble = 0.85 - 0.15 * (Math.Sin(a * 3.0) * 0.5 + Math.Sin(a * 7.0 + 2.1) * 0.3 + Math.Sin(a * 11.0 + 4.7) * 0.2);
                float r = (float)(Math.Sqrt(rng.NextDouble()) * radius * wobble);
                if (r < clearing) continue;
                var p = new V3(centre.X + (float)Math.Cos(a) * r, 0f, centre.Z + (float)Math.Sin(a) * r);
                if (InHole(p, holes)) continue;
                Positions.Add(p);
                Scales.Add(0.75f + (float)rng.NextDouble() * 0.7f);
                _hits.Add(Res.SourceHits);
                _felled.Add(false);
            }
            for (int i = 0; i < Positions.Count; i++)
            {
                long key = CellKey(Positions[i]);
                List<int> bucket;
                if (!_cells.TryGetValue(key, out bucket)) _cells[key] = bucket = new List<int>();
                bucket.Add(i);
            }
        }

        static bool InHole(V3 p, IList<KeyValuePair<V3, float>> holes)
        {
            if (holes == null) return false;
            foreach (var hole in holes)
                if (p.FlatDistance(hole.Key) < hole.Value) return true;
            return false;
        }

        static long CellKey(V3 p) { return CellKey((int)Math.Floor(p.X / Cell), (int)Math.Floor(p.Z / Cell)); }
        static long CellKey(int cx, int cz) { return ((long)cx << 32) ^ (uint)cz; }

        public int Count { get { return Positions.Count; } }
        public bool IsFelled(int index) { return index >= 0 && index < _felled.Count && _felled[index]; }
        public int HitsLeft(int index) { return index >= 0 && index < _hits.Count ? _hits[index] : -1; }

        /// Удар по дереву. Возвращает, сколько ударов осталось; 0 — валить.
        public int Hit(int index)
        {
            if (index < 0 || index >= _hits.Count || _felled[index]) return -1;
            _hits[index] = Math.Max(0, _hits[index] - 1);
            return _hits[index];
        }

        public void Fell(int index)
        {
            if (index < 0 || index >= _felled.Count) return;
            _felled[index] = true;
            _hits[index] = 0;
        }

        public List<int> FelledIndices()
        {
            var result = new List<int>();
            for (int i = 0; i < _felled.Count; i++)
                if (_felled[i]) result.Add(i);
            return result;
        }

        /// Стоящие деревья вокруг точки: новые — в радиусе, уже взятые (current) —
        /// до радиуса отпускания. Итог дописывается в out.
        public void CollectAround(V3 point, float radius, float release, HashSet<int> current, HashSet<int> result)
        {
            int reach = (int)Math.Ceiling(release / Cell);
            int bx = (int)Math.Floor(point.X / Cell), bz = (int)Math.Floor(point.Z / Cell);
            for (int cx = bx - reach; cx <= bx + reach; cx++)
                for (int cz = bz - reach; cz <= bz + reach; cz++)
                {
                    List<int> bucket;
                    if (!_cells.TryGetValue(CellKey(cx, cz), out bucket)) continue;
                    foreach (int index in bucket)
                    {
                        if (_felled[index] || result.Contains(index)) continue;
                        float limit = current != null && current.Contains(index) ? release : radius;
                        if (Positions[index].Distance(point) <= limit) result.Add(index);
                    }
                }
        }

        /// Ближайшее стоящее дерево к точке не дальше radius; -1 — нет.
        public int Nearest(V3 point, float radius)
        {
            var found = new HashSet<int>();
            CollectAround(point, radius, radius, null, found);
            int best = -1;
            float bestDistance = float.MaxValue;
            foreach (int index in found)
            {
                float d = Positions[index].FlatDistance(point);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = index;
                }
            }
            return best;
        }
    }
}
