// План мира из примитивов (перенос world_builder.gd): что где стоит.
//
// Unity-слой ставит по плану серые коробки, цилиндры, конусы, пандус и
// камни — до ассетов автора это и есть мир. Размеры и места — из Godot-версии;
// почему именно так (проём ворот дворца, плато 360 м, пандус с парапетами,
// гряда за фортом) — в её комментариях. Случайное (гряда, роща, хутора)
// строится генератором ядра: мир одинаков на всех машинах, но не повторяет
// Godot-версию камень в камень — ассеты всё равно делаются заново.
//
// Трава, кусты и мелкие камни — украшение без коллизии; их Unity-слой
// раскидывает сам по высоте рельефа.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum PieceShape { Box, Cylinder, Cone, Ramp, Peak, Rock, Tree }

    /// Кусок мира. Box — размер по осям; Cylinder/Cone — Size.X радиус, Size.Y высота;
    /// Ramp — Size = ширина, подъём, длина по земле, Center — подножие;
    /// Peak, Rock — габарит; Tree — Size.Y высота ствола.
    public class Piece
    {
        public string Group;
        public PieceShape Shape;
        public V3 Center;
        public V3 Size;
        public float Yaw;
        public string Material;
        /// Можно добывать: дерево, камень, золото.
        public ResourceKind? Harvest;
        public int Hits;
        /// Зерно формы камня или вершины.
        public int ShapeSeed;
        /// Без коллизии (конус крыши, дорога): только вид.
        public bool Decor;
    }

    public class WorldPlan
    {
        public readonly List<Piece> Pieces = new List<Piece>();
        readonly Relief _relief;
        string _group = "";

        public WorldPlan(Relief relief) { _relief = relief; }

        public static WorldPlan ForMap(Relief relief)
        {
            var plan = new WorldPlan(relief);
            plan.Build();
            return plan;
        }

        public IEnumerable<Piece> InGroup(string group)
        {
            foreach (var piece in Pieces)
                if (piece.Group == group) yield return piece;
        }

        public void Build()
        {
            BuildGround();
            BuildRoads();
            BuildElves();
            BuildEmperor(MapLayout.ZoneCenters[(int)Zone.Emperor]);
            BuildVillain(MapLayout.ZoneCenters[(int)Zone.Villain]);
            BuildHumans(MapLayout.ZoneCenters[(int)Zone.Humans]);
            BuildMines();
            BuildCrossroads();
            BuildHamlets();
            BuildHillTrees();
        }

        Piece Add(PieceShape shape, V3 center, V3 size, string material, float yaw)
        {
            var piece = new Piece { Group = _group, Shape = shape, Center = center, Size = size, Material = material, Yaw = yaw };
            Pieces.Add(piece);
            return piece;
        }

        Piece Box(V3 center, V3 size, string material, float yaw = 0f) { return Add(PieceShape.Box, center, size, material, yaw); }

        Piece Cylinder(V3 center, float radius, float height, string material)
        {
            return Add(PieceShape.Cylinder, center, new V3(radius, height, radius), material, 0f);
        }

        void Cone(V3 center, float radius, float height, string material)
        {
            Add(PieceShape.Cone, center, new V3(radius, height, radius), material, 0f).Decor = true;
        }

        Piece Rock(V3 foot, V3 size, float yaw, int seed)
        {
            var piece = Add(PieceShape.Rock, new V3(foot.X, foot.Y + size.Y * 0.42f, foot.Z), size, "rock", yaw);
            piece.ShapeSeed = seed;
            return piece;
        }

        Piece Tree(float x, float z, float height)
        {
            return Add(PieceShape.Tree, new V3(x, _relief.Height(x, z), z), new V3(1.1f, height, 1.1f), "trunk", 0f);
        }

        static Piece Harvestable(Piece piece, ResourceKind kind, int hits)
        {
            piece.Harvest = kind;
            piece.Hits = hits > 0 ? hits : Res.SourceHits;
            return piece;
        }

        static float Range(Rng rng, float low, float high) { return low + (float)rng.NextDouble() * (high - low); }

        void BuildGround()
        {
            _group = "Ground";
            float size = MapLayout.WorldSize;
            Box(new V3(0f, -1.05f, 0f), new V3(size, 2f, size), "ground");
            // Стены мира по краю.
            float h = size * 0.5f;
            for (int i = 0; i < 4; i++)
            {
                float yaw = (float)(Math.PI * 0.5 * i);
                var dir = new V3((float)Math.Sin(yaw), 0f, -(float)Math.Cos(yaw));
                Box(dir * h + new V3(0f, 10f, 0f), new V3(size, 20f, 4f), "dark_stone", -yaw);
            }
        }

        void BuildRoads()
        {
            _group = "Roads";
            Box(new V3(0f, 0.05f, 0f), new V3(MapLayout.WorldSize, 0.1f, 14f), "road").Decor = true;
            Box(new V3(0f, 0.05f, 0f), new V3(14f, 0.1f, MapLayout.WorldSize), "road").Decor = true;
        }

        void BuildElves()
        {
            _group = "ZoneElves";
            Trader(MapLayout.Traders[1]);
        }

        void Trader(V3 at)
        {
            Box(at + new V3(0f, 1f, 0f), new V3(7f, 2f, 4f), "wood");
            Box(at + new V3(0f, 2.3f, 0f), new V3(8f, 0.6f, 5f), "stone");
            for (int corner = 0; corner < 4; corner++)
            {
                float ox = corner % 2 == 0 ? 3.4f : -3.4f;
                float oz = corner < 2 ? -2f : 2f;
                Cylinder(at + new V3(ox, 3.4f, oz), 0.25f, 2.2f, "wood");
            }
            Box(at + new V3(0f, 4.7f, 0f), new V3(9f, 0.4f, 6f), "accent");
        }

        /// Дворец: плато 360×360 высотой 6, пандус с фасада, стена двора с
        /// проёмом, сам дворец с воротами.
        public const float PalaceHalfWidth = 45f;
        public const float PalaceHalfDepth = 30f;
        public const float PalaceWallHeight = 24f;
        public const float PalaceGateHalf = 16f;
        public const float CourtWall = 130f;

        void BuildEmperor(V3 c)
        {
            _group = "ZoneEmperor";
            Trader(MapLayout.Traders[2]);
            float top = MapLayout.PlateauHeight;
            Box(new V3(c.X, top * 0.5f, c.Z), new V3(360f, top, 360f), "stone");
            Add(PieceShape.Ramp, new V3(c.X, -1f, c.Z - 225f),
                new V3(MapLayout.RampWidth, top, MapLayout.RampRun), "stone", 0f);

            float w = CourtWall;
            Box(new V3(c.X, 12f, c.Z + w), new V3(w * 2f, 12f, 6f), "marble");
            Box(new V3(c.X - w, 12f, c.Z), new V3(6f, 12f, w * 2f), "marble");
            Box(new V3(c.X + w, 12f, c.Z), new V3(6f, 12f, w * 2f), "marble");
            Box(new V3(c.X - 75f, 12f, c.Z - w), new V3(116f, 12f, 6f), "marble");
            Box(new V3(c.X + 75f, 12f, c.Z - w), new V3(116f, 12f, 6f), "marble");
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                    Cylinder(new V3(c.X + sx * w, 16f, c.Z - sz * w), 9f, 20f, "marble");

            float pw = PalaceHalfWidth, pd = PalaceHalfDepth, ph = PalaceWallHeight, wall = 4f, gate = PalaceGateHalf;
            Box(new V3(c.X, top + ph * 0.5f, c.Z + pd), new V3(pw * 2f, ph, wall), "marble");
            Box(new V3(c.X - pw, top + ph * 0.5f, c.Z), new V3(wall, ph, pd * 2f), "marble");
            Box(new V3(c.X + pw, top + ph * 0.5f, c.Z), new V3(wall, ph, pd * 2f), "marble");
            float jamb = (pw - gate) * 0.5f;
            for (int side = -1; side <= 1; side += 2)
                Box(new V3(c.X + side * (gate + jamb), top + ph * 0.5f, c.Z - pd), new V3(jamb * 2f, ph, wall), "marble");
            Box(new V3(c.X, top + ph - 3f, c.Z - pd), new V3(gate * 2f, 6f, wall), "marble");
            Box(new V3(c.X, top + ph + 1f, c.Z), new V3(pw * 2f, 2f, pd * 2f), "marble");
            Box(new V3(c.X, 33f, c.Z), new V3(60f, 6f, 40f), "marble");
            Cylinder(new V3(c.X, 44f, c.Z), 12f, 28f, "marble");
            Cone(new V3(c.X, 62f, c.Z), 15f, 14f, "accent");
        }

        /// Форт злодея: квадрат 160 м с воротами на юг, донжон, башни, руины у ворот,
        /// роща для лесорубов и гряда гор за спиной.
        public const float FortHalf = 80f;
        public static readonly V3 FortOffset = new V3(0f, 0f, 40f);

        void BuildVillain(V3 c)
        {
            _group = "ZoneVillain";
            Trader(MapLayout.Traders[0]);
            MicroMine();
            BuildRidge(c, new Rng(2989));

            var f = c + FortOffset;
            float w = FortHalf;
            Box(new V3(f.X, 8f, f.Z + w), new V3(w * 2f, 16f, 5f), "dark_stone");
            Box(new V3(f.X - w, 8f, f.Z), new V3(5f, 16f, w * 2f), "dark_stone");
            Box(new V3(f.X + w, 8f, f.Z), new V3(5f, 16f, w * 2f), "dark_stone");
            Box(new V3(f.X - 50f, 8f, f.Z - w), new V3(65f, 16f, 5f), "dark_stone");
            Box(new V3(f.X + 50f, 8f, f.Z - w), new V3(65f, 16f, 5f), "dark_stone");
            for (int sx = -1; sx <= 1; sx += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                    Cylinder(new V3(f.X + sx * w, 11f, f.Z - sz * w), 8f, 22f, "dark_stone");
            Box(new V3(f.X, 16f, f.Z + 20f), new V3(40f, 32f, 40f), "dark_stone");
            for (int side = -1; side <= 1; side += 2) Ruin(new V3(f.X + side * 45f, 0f, f.Z - 30f));

            var grove = new Rng(4231);
            for (int i = 0; i < 26; i++)
            {
                double a = Range(grove, 0.18f, 0.82f) * Math.PI;
                float r = Range(grove, 96f, 132f);
                float x = f.X + (float)Math.Cos(a) * r, z = f.Z - (float)Math.Sin(a) * r;
                Harvestable(Tree(x, z, Range(grove, 9f, 15f)), ResourceKind.Wood, 0);
            }
        }

        void MicroMine()
        {
            var at = MapLayout.MicroMine;
            for (int i = 0; i < MapLayout.MicroMineStone.Length; i++)
                Harvestable(Rock(at + MapLayout.MicroMineStone[i], new V3(4f, 3f, 4f), -i * 1.3f, 90 + i),
                    ResourceKind.Stone, Res.MicroStoneHitsEach);
            for (int i = 0; i < MapLayout.MicroMineGold.Length; i++)
                Harvestable(Rock(at + MapLayout.MicroMineGold[i], new V3(2.6f, 2.2f, 2.6f), -i * 2.1f, 190 + i),
                    ResourceKind.Gold, Res.MicroGoldHitsEach);
        }

        void Ruin(V3 at)
        {
            float[][] pieces =
            {
                new[] { -12f, -9f, 9f, 1.6f, 1.2f }, new[] { 4f, -9f, 6f, 0.9f, 1.2f },
                new[] { -14.5f, -2f, 1.2f, 1.3f, 8f }, new[] { 14.5f, 5f, 1.2f, 2f, 6f },
                new[] { -3f, 9.5f, 7f, 1.1f, 1.2f },
            };
            foreach (var p in pieces)
                Box(new V3(at.X + p[0], p[3] * 0.5f, at.Z - p[1]), new V3(p[2], p[3], p[4]), "dark_stone");
            for (int i = 0; i < 2; i++)
                Box(new V3(at.X - 4f + i * 7f, 0.25f, at.Z - 1f + i * 3f), new V3(0.5f, 0.5f, 7f), "trunk", -(0.4f + i * 0.9f));
        }

        /// Гряда гор полукругом за фортом, с наружной стороны зоны.
        void BuildRidge(V3 c, Rng rng)
        {
            var outward = new V3(c.X, 0f, c.Z).Normalized();
            // Угол обходит по часовой стрелке, если смотреть сверху: тот же
            // обход, что в Godot-версии, — и та же гряда.
            double mid = Math.Atan2(-outward.Z, outward.X);
            double span = Math.PI * 1.05;
            float radius = MapLayout.ZoneHalf - 60f;
            const int peaks = 15;
            for (int i = 0; i < peaks; i++)
            {
                float t = (float)i / (peaks - 1);
                double a = mid + (t - 0.5) * span;
                float crest = (float)Math.Sin(t * Math.PI);
                float height = 16f + crest * 52f + Range(rng, -5f, 5f);
                float width = 52f + crest * 30f + Range(rng, -6f, 6f);
                float x = c.X + (float)Math.Cos(a) * radius + Range(rng, -14f, 14f);
                float z = c.Z - (float)Math.Sin(a) * radius - Range(rng, -14f, 14f);
                var peak = Add(PieceShape.Peak, new V3(x, 0f, z), new V3(width, height, width * Range(rng, 0.8f, 1.15f)),
                    "rock", -(float)(rng.NextDouble() * 2 * Math.PI));
                peak.ShapeSeed = rng.Next(1 << 30);
            }
            for (int i = 0; i < 22; i++)
            {
                float t = (float)rng.NextDouble();
                double a = mid + (t - 0.5) * span;
                float crest = (float)Math.Sin(t * Math.PI);
                float back = radius - Range(rng, 34f, 62f);
                float s = 7f + crest * 9f + Range(rng, -2f, 3f);
                Rock(new V3(c.X + (float)Math.Cos(a) * back, 0f, c.Z - (float)Math.Sin(a) * back),
                    new V3(s, s * Range(rng, 0.5f, 0.8f), s * Range(rng, 0.7f, 1.2f)),
                    -(float)(rng.NextDouble() * 2 * Math.PI), rng.Next(1 << 30));
            }
        }

        /// Шахты: глыба 34×16 на рельефе, вход прочь от поселения, куча руды сбоку.
        void BuildMines()
        {
            _group = "Mines";
            foreach (var mine in MapLayout.Mines)
            {
                var at = mine.At;
                var dir = MapLayout.MineFacing(at);
                // Как в Godot-версии: к dir смотрит отражённая +Z глыбы (здесь −Z).
                // Глыба и вход симметричны, вид от этого не меняется.
                float yaw = (float)Math.Atan2(-dir.X, -dir.Z);
                float y = _relief.Height(at.X, at.Z);
                Box(new V3(at.X, y + MapLayout.MineHeight * 0.5f, at.Z), new V3(MapLayout.MineRock, MapLayout.MineHeight, MapLayout.MineRock), "rock", yaw);
                var door = at + dir * (MapLayout.MineRock * 0.5f + 1f);
                Box(new V3(door.X, y + 4f, door.Z), new V3(12f, 8f, 4f), "dark_stone", yaw);
                var heap = at + dir * (MapLayout.MineRock * 0.5f + 6f) + new V3(dir.Z, 0f, -dir.X) * 8f;
                Box(new V3(heap.X, y + 0.8f, heap.Z), new V3(4f, 1.6f, 4f), "ore_" + (int)mine.Kind, yaw - 0.4f);
            }
        }

        void BuildCrossroads()
        {
            _group = "Crossroads";
            var bench = MapLayout.Workbench;
            Box(new V3(bench.X, 1.2f, bench.Z), new V3(6f, 2.4f, 3f), "wood");
            Box(new V3(bench.X, 2.7f, bench.Z), new V3(6.6f, 0.6f, 3.6f), "stone");
            Cylinder(new V3(bench.X - 3.6f, 2f, bench.Z), 0.4f, 4f, "accent");
            Cylinder(new V3(0f, 6f, 0f), 3f, 12f, "marble");
            Box(new V3(0f, 13f, 0f), new V3(4f, 2f, 4f), "accent");
            for (int i = 0; i < 3; i++)
                Box(new V3(30f + i * 12f, 0.4f + i * 0.8f, -25f), new V3(10f, 0.8f + i * 1.6f, 10f), "stone");

            // Стартовое сырьё у перекрёстка: четырнадцать деревьев и девять камней.
            var rng = new Rng(7717);
            for (int i = 0; i < 14; i++)
            {
                double a = rng.NextDouble() * 2 * Math.PI;
                float r = Range(rng, 26f, 60f);
                Harvestable(Tree((float)Math.Cos(a) * r, -((float)Math.Sin(a) * r + 30f), Range(rng, 9f, 15f)), ResourceKind.Wood, 0);
            }
            for (int i = 0; i < 9; i++)
            {
                double a = rng.NextDouble() * 2 * Math.PI;
                float r = Range(rng, 30f, 65f);
                float s = Range(rng, 3f, 5.5f);
                var foot = new V3((float)Math.Cos(a) * r - 35f, 0f, -((float)Math.Sin(a) * r + 5f));
                Harvestable(Rock(foot, new V3(s, s * 0.75f, s * Range(rng, 0.75f, 1.15f)), -(float)(rng.NextDouble() * 2 * Math.PI), rng.Next(1 << 30)),
                    ResourceKind.Stone, 0);
            }
        }

        /// Хутора — «древние земли» для заданий эльфов: пять домиков вокруг колодца.
        void BuildHamlets()
        {
            _group = "Hamlets";
            var rng = new Rng(4477);
            foreach (var centre in MapLayout.Hamlets)
            {
                for (int i = 0; i < 5; i++)
                {
                    double angle = 2 * Math.PI * i / 5.0 + Range(rng, -0.3f, 0.3f);
                    float radius = Range(rng, 14f, 26f);
                    var at = centre + new V3((float)Math.Cos(angle) * radius, 0f, -(float)Math.Sin(angle) * radius);
                    float yaw = -(float)(rng.NextDouble() * 2 * Math.PI);
                    float size = Range(rng, 0.85f, 1.25f);
                    float h = 3.4f * size;
                    Box(new V3(at.X, h * 0.5f, at.Z), new V3(6f * size, h, 5f * size), "wood", yaw);
                }
                Cylinder(new V3(centre.X, 0.6f, centre.Z), 1.6f, 1.2f, "stone");
                Box(new V3(centre.X, 2.4f, centre.Z), new V3(3.2f, 0.3f, 3.2f), "wood");
            }
        }

        void BuildHumans(V3 c)
        {
            _group = "ZoneHumans";
            var rng = new Rng(273);
            for (int i = 0; i < 14; i++)
            {
                float row = i < 7 ? -1f : 1f;
                float t = i % 7 - 3f;
                var p = c + new V3(t * 34f, 0f, -row * 26f);
                float hh = Range(rng, 7f, 11f);
                Box(new V3(p.X, hh * 0.5f, p.Z), new V3(18f, hh, 14f), "wood");
                Cone(new V3(p.X, hh + 3f, p.Z), 14f, 6f, "accent");
            }
            Box(new V3(c.X, 0.1f, c.Z), new V3(80f, 0.2f, 20f), "road").Decor = true;
            Cylinder(new V3(c.X, 1.5f, c.Z), 4f, 3f, "stone");
            for (int i = 0; i < 10; i++)
            {
                var p = c + new V3(Range(rng, -260f, 260f), 0f, -Range(rng, -260f, 260f));
                if (p.FlatDistance(c) < 90f) continue;
                Box(new V3(p.X, 0.15f, p.Z), new V3(60f, 0.3f, 40f), "foliage", -(float)(rng.NextDouble() * Math.PI)).Decor = true;
            }
        }

        /// Деревья на холмах: 170 штук там, где земля выше 3 м.
        public const int HillTrees = 170;

        void BuildHillTrees()
        {
            _group = "Scatter";
            var rng = new Rng(90210);
            int placed = 0;
            float half = MapLayout.WorldSize * 0.5f;
            for (int i = 0; i < 900 && placed < HillTrees; i++)
            {
                float x = Range(rng, -half, half), z = -Range(rng, -half, half);
                if (_relief.Height(x, z) < 3f) continue;
                placed++;
                Tree(x, z, Range(rng, 8f, 13f));
            }
        }
    }
}
