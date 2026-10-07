// Рельеф карты: холмы только ВВЕРХ и только там, где ничего не стоит
// (перенос relief.gd).
//
// Весь мир построен на нулевой высоте: форт, дворец, дороги, спавны, шахты.
// Маска гасит холмы на дорогах, в зонах, у шахт, на плато императора и у края
// карты, а за ними плавно отпускает. Уклон считан под потолок навигации в 45°:
// волны длинные (сотни метров) при небольшой высоте. Подробности и история
// ошибок («зелёные тарелки», закопанный пандус) — в Godot-версии.
//
// Шум свой (двумерный симплекс), а не FastNoiseLite: холмы в Unity-версии
// делаются заново, повторять их точь-в-точь не нужно — нужны те же правила.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public struct FlatSpot
    {
        public readonly float X;
        public readonly float Z;
        public readonly float Flat;
        public readonly float Fade;

        public FlatSpot(float x, float z, float flat, float fade)
        {
            X = x;
            Z = z;
            Flat = flat;
            Fade = fade;
        }
    }

    public class Relief
    {
        /// Сторона клетки сетки рельефа: 75×75 клеток на мир в 1200 метров.
        public const float Cell = 16f;
        public const float BigHeight = 22f;
        public const float BigWave = 340f;
        public const float SmallHeight = 5f;
        public const float SmallWave = 120f;
        // РАСТУШЁВКИ ШИРЕ, ЧЕМ В GODOT-ВЕРСИИ. Склон у края плоского пятна —
        // это высота холма, делённая на ширину растушёвки (smoothstep даёт ×1.5
        // в середине). Шум FastNoiseLite редко доходил до краёв, и узкие полосы
        // сходили с рук; здешний симплекс доходит до ±1, и у дорог выходило 39°
        // при потолке навигации 45°. Ширина теперь не меньше 80 м: худший
        // уклон ~25°, холмистой земли — около 38% карты.
        public const float RoadFlat = 26f;
        public const float RoadFade = 106f;
        public const float ZoneFlat = 120f;
        public const float ZoneFade = 200f;
        public const float SpotFlat = 70f;
        public const float SpotFade = 150f;
        public const float EdgeFlat = 80f;
        /// Плато императора — 360 м в поперечнике, приглаживается целиком (с углом квадрата).
        public const float PlateauFlat = 262f;
        public const float PlateauFade = 320f;

        readonly SimplexNoise _big = new SimplexNoise(20260829);
        readonly SimplexNoise _small = new SimplexNoise(771177);
        readonly List<FlatSpot> _spots = new List<FlatSpot>();
        readonly float _half;

        public Relief(float worldSize, IEnumerable<FlatSpot> spots)
        {
            _half = worldSize * 0.5f;
            _spots.AddRange(spots);
        }

        /// Рельеф стандартной карты: зоны, лавки, верстак, перекрёсток, плато, шахты и их входы.
        public static Relief ForMap()
        {
            var spots = new List<FlatSpot>();
            foreach (var zone in MapLayout.ZoneCenters) spots.Add(new FlatSpot(zone.X, zone.Z, ZoneFlat, ZoneFade));
            foreach (var trader in MapLayout.Traders) spots.Add(Spot(trader));
            spots.Add(Spot(MapLayout.Workbench));
            spots.Add(Spot(MapLayout.Crossroads));
            var emperor = MapLayout.PalaceCentre;
            spots.Add(new FlatSpot(emperor.X, emperor.Z, PlateauFlat, PlateauFade));
            var fort = MapLayout.FortCentre;
            spots.Add(new FlatSpot(fort.X, fort.Z, ZoneFlat + 40f, ZoneFade + 20f));
            spots.Add(Spot(MapLayout.MicroMine));
            spots.Add(Spot(MapLayout.VillainPass));
            spots.Add(Spot(MapLayout.CastleFork));
            foreach (var hamlet in MapLayout.Hamlets) spots.Add(Spot(hamlet));
            foreach (var mark in new[] { MapLayout.Watchtower, MapLayout.AncientRuins, MapLayout.AncientPortal,
                         MapLayout.MilitaryCamp, MapLayout.ElfCampEast, MapLayout.VillainCamp, MapLayout.Port, WorldPlan.ElfCampWest })
                spots.Add(Spot(mark));
            foreach (var mine in MapLayout.Mines)
            {
                spots.Add(Spot(mine.At));
                spots.Add(Spot(MapLayout.MineEntrance(mine.At)));
            }
            return new Relief(MapLayout.WorldSize, spots);
        }

        static FlatSpot Spot(V3 at) { return new FlatSpot(at.X, at.Z, SpotFlat, SpotFade); }

        /// Высота земли в точке; ноль — плоско. Этой же функцией кладут траву,
        /// камни и деревья: высоту нельзя считать дважды и по-разному.
        public float Height(float x, float z)
        {
            float mask = Mask(x, z);
            if (mask <= 0f) return 0f;
            // Шум переводится в 0..1 СДВИГОМ, а не обрезкой: обрезка даёт плоские
            // блюдца с видимой кромкой. Степень 1.6 — низины шире, вершины уже.
            // Шум берётся по −z: холмы — те же, что были в осях Godot-версии
            // (ядро перешло на оси Unity отражением z).
            float big = (float)Math.Pow(_big.Sample(x / BigWave, -z / BigWave) * 0.5f + 0.5f, 1.6);
            float small = (float)Math.Pow(_small.Sample(x / SmallWave, -z / SmallWave) * 0.5f + 0.5f, 1.6);
            return (big * BigHeight + small * SmallHeight) * mask;
        }

        /// 0 — земле подниматься нельзя, 1 — вся высота, между — плавно.
        public float Mask(float x, float z)
        {
            float m = 1f;
            // Дороги и река — отрезки MapLayout.Roads и MapLayout.River.
            m = Math.Min(m, Ramp(MapLayout.DistanceToRoad(x, z), RoadFlat, RoadFade));
            m = Math.Min(m, Ramp(MapLayout.DistanceToRiver(x, z), RoadFlat, RoadFade));
            foreach (var spot in _spots)
            {
                float dx = x - spot.X;
                float dz = z - spot.Z;
                m = Math.Min(m, Ramp((float)Math.Sqrt(dx * dx + dz * dz), spot.Flat, spot.Fade));
            }
            // Край карты: там стоят стены мира.
            float edge = _half - Math.Max(Math.Abs(x), Math.Abs(z));
            m = Math.Min(m, Ramp(edge, 0f, EdgeFlat));
            // Море у западного края и плоский берег за ним.
            m = Math.Min(m, Ramp(x + _half - MapLayout.SeaWidth, 0f, EdgeFlat));
            // Поля людей у моря — равнина: холмы начинаются у кромки леса.
            m = Math.Min(m, Ramp(x - (MapLayout.FieldsEdgeX - 40f), 0f, 80f));
            return Math.Max(0f, Math.Min(1f, m));
        }

        /// 0 при value <= flat, 1 при value >= fade, плавно (smoothstep) между.
        public static float Ramp(float value, float flat, float fade)
        {
            if (value <= flat) return 0f;
            if (value >= fade) return 1f;
            float t = (value - flat) / (fade - flat);
            return t * t * (3f - 2f * t);
        }

        /// Уклон в градусах по конечной разности: для проверок и расстановки.
        public float SlopeDegrees(float x, float z, float step)
        {
            float dx = (Height(x + step, z) - Height(x - step, z)) / (2f * step);
            float dz = (Height(x, z + step) - Height(x, z - step)) / (2f * step);
            return (float)(Math.Atan(Math.Sqrt(dx * dx + dz * dz)) * 180.0 / Math.PI);
        }
    }

    /// Двумерный симплекс-шум (схема Густавсона) с перестановкой от зерна. Выход — примерно -1..1.
    public class SimplexNoise
    {
        static readonly int[] GradX = { 1, -1, 1, -1, 1, -1, 0, 0 };
        static readonly int[] GradY = { 1, 1, -1, -1, 0, 0, 1, -1 };
        const float F2 = 0.36602540378f;
        const float G2 = 0.2113248654f;
        readonly int[] _perm = new int[512];

        public SimplexNoise(int seed)
        {
            var p = new int[256];
            for (int i = 0; i < 256; i++) p[i] = i;
            var random = new Rng(seed);
            for (int i = 255; i > 0; i--)
            {
                int j = random.Next(i + 1);
                int t = p[i];
                p[i] = p[j];
                p[j] = t;
            }
            for (int i = 0; i < 512; i++) _perm[i] = p[i & 255];
        }

        public float Sample(float x, float y)
        {
            float s = (x + y) * F2;
            int i = (int)Math.Floor(x + s);
            int j = (int)Math.Floor(y + s);
            float t = (i + j) * G2;
            float x0 = x - (i - t);
            float y0 = y - (j - t);
            int i1 = x0 > y0 ? 1 : 0;
            int j1 = 1 - i1;
            float x1 = x0 - i1 + G2;
            float y1 = y0 - j1 + G2;
            float x2 = x0 - 1f + 2f * G2;
            float y2 = y0 - 1f + 2f * G2;
            int ii = i & 255;
            int jj = j & 255;
            float n = Corner(_perm[ii + _perm[jj]], x0, y0)
                + Corner(_perm[ii + i1 + _perm[jj + j1]], x1, y1)
                + Corner(_perm[ii + 1 + _perm[jj + 1]], x2, y2);
            return 70f * n;
        }

        static float Corner(int hash, float x, float y)
        {
            float t = 0.5f - x * x - y * y;
            if (t < 0f) return 0f;
            int g = hash & 7;
            t *= t;
            return t * t * (GradX[g] * x + GradY[g] * y);
        }
    }
}
