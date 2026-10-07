// Раскладка карты «Изумрудный Разлом» (концепт автора от 07.10, уточнение:
// «лес на всю карту, замок людей в левый верхний угол, форт злодея в правый
// нижний, горы должны окружать форт злодея»):
//   северо-запад — замок людей на плато, к югу вдоль моря — поля и деревни;
//   всё остальное — лес эльфов, поселение посреди, шахты только в лесу,
//   через лес течёт река;
//   юго-восток — цитадель злодея в кольце тёмных гор, выход — перевал к лесу.
// Геометрию строит Unity-слой; здесь — где что стоит. Всё, что стоит у
// стороны, считается от центра её зоны: зону можно сдвинуть одной строкой.
//
// Оси Unity: +x — восток, +z — север.
using System;

namespace DjvaGoda.Core
{
    public enum Zone { Elves, Emperor, Villain, Humans }

    public struct MineSite
    {
        public readonly ResourceKind Kind;
        public readonly V3 At;
        public readonly string Name;
        /// Куда смотрит вход (к своей дороге); нуль — прочь от поселения эльфов.
        public readonly V3 Facing;

        public MineSite(ResourceKind kind, V3 at, string name = "", V3 facing = default(V3))
        {
            Kind = kind;
            At = at;
            Name = name;
            Facing = facing;
        }
    }

    /// Отрезок дороги или реки на плоскости.
    public struct RoadSegment
    {
        public readonly V3 From;
        public readonly V3 To;

        public RoadSegment(V3 from, V3 to)
        {
            From = from;
            To = to;
        }
    }

    public static class MapLayout
    {
        public const float WorldSize = 1200f;
        public const float ZoneSize = 600f;
        public const float ZoneHalf = ZoneSize * 0.5f;

        // --- центры зон --------------------------------------------------------

        /// Поселение эльфов посреди леса.
        public static readonly V3 ElvesCentre = new V3(0f, 0f, 60f);
        /// Замок людей (дворец стражи) на плато — левый верхний угол.
        public static readonly V3 PalaceCentre = new V3(-370f, 0f, 370f);
        /// Зона злодея — правый нижний угол; сам форт — FortCentre.
        public static readonly V3 VillainCentre = new V3(340f, 0f, -300f);
        /// Поля и деревня людей — к югу от замка, вдоль моря.
        public static readonly V3 HumansCentre = new V3(-370f, 0f, -230f);

        public static readonly V3[] ZoneCenters = { ElvesCentre, PalaceCentre, VillainCentre, HumansCentre };

        public static readonly string[] ZoneNames = { "Эльфийский лес", "Замок людей", "Цитадель Злодея", "Земли людей" };

        // --- замок -------------------------------------------------------------

        /// Плато замка и пандус на него (с юга, с парапетами).
        public static readonly V3 RampFoot = PalaceCentre + new V3(0f, 0f, -225f);
        public const float PlateauHeight = 6f;
        public const float RampWidth = 40f;
        public const float RampRun = 45f;
        /// Квадрат плато замка (половина стороны).
        public const float PlateauHalf = 180f;

        public static bool OnPlateau(float x, float z, float margin)
        {
            return Math.Abs(x - PalaceCentre.X) <= PlateauHalf + margin && Math.Abs(z - PalaceCentre.Z) <= PlateauHalf + margin;
        }

        // --- цитадель и горы ---------------------------------------------------

        /// Центр форта: квадрат 160 м, ворота — на север, к лесу.
        public static readonly V3 FortCentre = VillainCentre + new V3(0f, 0f, -40f);
        public const float FortHalf = 80f;
        public static readonly V3 VillainGate = FortCentre + new V3(0f, 0f, FortHalf);
        /// Кольцо тёмных гор вокруг форта; единственный проход — перевал на
        /// северо-западе кольца, к лесу.
        public const float RingRadius = 215f;
        public static readonly V3 VillainPass = FortCentre + new V3(-152f, 0f, 158f);
        /// Полуширина прохода в кольце, в радианах.
        public const float PassHalfAngle = 0.3f;

        /// Внутри кольца гор (с запасом margin наружу).
        public static bool InVillainRing(float x, float z, float margin)
        {
            float dx = x - FortCentre.X, dz = z - FortCentre.Z;
            return dx * dx + dz * dz <= (RingRadius + margin) * (RingRadius + margin);
        }

        // --- дороги --------------------------------------------------------------

        /// Развилка у подножия замка: на юг — к полям, на восток — караванный путь.
        public static readonly V3 CastleFork = new V3(RampFoot.X, 0f, 40f);
        /// Перекрёсток: тропа эльфов выходит на тракт; рядом — верстак.
        public static readonly V3 Crossroads = new V3(0f, 0f, -40f);
        public static readonly V3 Workbench = Crossroads + new V3(-24f, 0f, -22f);

        /// Главные дороги: замок — поля, караванный путь, тракт через перевал к
        /// воротам цитадели, тропа в поселение эльфов.
        public static readonly RoadSegment[] MainRoads =
        {
            new RoadSegment(RampFoot, CastleFork),
            new RoadSegment(CastleFork, HumansCentre),
            new RoadSegment(CastleFork, Crossroads),
            new RoadSegment(Crossroads, VillainPass),
            new RoadSegment(VillainPass, VillainGate + new V3(0f, 0f, 50f)),
            new RoadSegment(VillainGate + new V3(0f, 0f, 50f), VillainGate),
            new RoadSegment(Crossroads, ElvesCentre + new V3(0f, 0f, -45f)),
        };
        public const float RoadWidth = 14f;

        /// Расстояние по плоскости до ближайшей дороги.
        public static float DistanceToRoad(float x, float z) { return DistanceTo(Roads, x, z); }

        // --- вода --------------------------------------------------------------

        /// Река с севера через лес на юг (концепт): вода по колено, переходится
        /// вброд; на дорогах — мосты.
        public static readonly RoadSegment[] River =
        {
            new RoadSegment(new V3(-30f, 0f, 600f), new V3(-10f, 0f, 440f)),
            new RoadSegment(new V3(-10f, 0f, 440f), new V3(70f, 0f, 300f)),
            new RoadSegment(new V3(70f, 0f, 300f), new V3(90f, 0f, 160f)),
            new RoadSegment(new V3(90f, 0f, 160f), new V3(75f, 0f, 20f)),
            new RoadSegment(new V3(75f, 0f, 20f), new V3(100f, 0f, -80f)),
            new RoadSegment(new V3(100f, 0f, -80f), new V3(80f, 0f, -230f)),
            new RoadSegment(new V3(80f, 0f, -230f), new V3(25f, 0f, -380f)),
            new RoadSegment(new V3(25f, 0f, -380f), new V3(0f, 0f, -600f)),
        };
        public const float RiverWidth = 12f;

        public static float DistanceToRiver(float x, float z) { return DistanceTo(River, x, z); }

        /// Море вдоль западного края: полоса воды у стены мира.
        public const float SeaWidth = 34f;

        public static bool InSea(float x, float z, float margin)
        {
            return x < -WorldSize * 0.5f + SeaWidth + margin;
        }

        static float DistanceTo(RoadSegment[] segments, float x, float z)
        {
            float best = float.MaxValue;
            foreach (var road in segments) best = Math.Min(best, ToSegment(x, z, road.From, road.To));
            return best;
        }

        public static float ToSegment(float x, float z, V3 a, V3 b)
        {
            float vx = b.X - a.X, vz = b.Z - a.Z;
            float wx = x - a.X, wz = z - a.Z;
            float len = vx * vx + vz * vz;
            float t = len > 0f ? Math.Max(0f, Math.Min(1f, (wx * vx + wz * vz) / len)) : 0f;
            float dx = wx - vx * t, dz = wz - vz * t;
            return (float)Math.Sqrt(dx * dx + dz * dz);
        }

        // --- шахты -----------------------------------------------------------

        /// Пять шахт, все в лесу (концепт). Железо у стражи (Сосновая) и у
        /// злодея (Тихая) своё — от пандуса и от перевала поровну; камень
        /// (Лунная) и золото (Серебряная) — общие, ровно посередине между
        /// пандусом и перевалом; уголь (Глубокая) — ближе к середине.
        public static readonly MineSite[] Mines =
        {
            new MineSite(ResourceKind.Iron, new V3(-140f, 0f, 280f), "Сосновая", new V3(-0.6f, 0f, -0.8f)),
            new MineSite(ResourceKind.Stone, new V3(120f, 0f, 345f), "Лунная", new V3(0f, 0f, -1f)),
            new MineSite(ResourceKind.Coal, new V3(-60f, 0f, -150f), "Глубокая", new V3(0f, 0f, 1f)),
            new MineSite(ResourceKind.Gold, new V3(-200f, 0f, -208f), "Серебряная", new V3(0f, 0f, 1f)),
            new MineSite(ResourceKind.Iron, new V3(170f, 0f, 85f), "Тихая", new V3(0f, 0f, -1f)),
        };

        /// Дороги шахт: от входа каждой — две, к разным дорогам, чтобы маршрут
        /// обоза было из чего выбирать (решение автора от 07.10).
        public static readonly RoadSegment[] MineRoads = BuildMineRoads();

        static RoadSegment[] BuildMineRoads()
        {
            var pine = MineEntrance(Mines[0].At);
            var moon = MineEntrance(Mines[1].At);
            var deep = MineEntrance(Mines[2].At);
            var silver = MineEntrance(Mines[3].At);
            var quiet = MineEntrance(Mines[4].At);
            var tract = new V3(150f, 0f, -153f);
            var bend = new V3(160f, 0f, -44f);
            return new[]
            {
                // Сосновая: к пандусу замка и к караванному пути.
                new RoadSegment(pine, new V3(-175f, 0f, 170f)),
                new RoadSegment(new V3(-175f, 0f, 170f), new V3(RampFoot.X, 0f, 120f)),
                new RoadSegment(pine, new V3(-200f, 0f, 3f)),
                // Лунная: в поселение эльфов через реку и в обход на восток к тракту.
                new RoadSegment(moon, new V3(40f, 0f, 200f)),
                new RoadSegment(new V3(40f, 0f, 200f), ElvesCentre),
                new RoadSegment(moon, new V3(235f, 0f, 190f)),
                new RoadSegment(new V3(235f, 0f, 190f), new V3(230f, 0f, 20f)),
                new RoadSegment(new V3(230f, 0f, 20f), bend),
                // Тихая: к тракту на перевал и в поселение эльфов через реку.
                new RoadSegment(quiet, bend),
                new RoadSegment(bend, tract),
                new RoadSegment(quiet, new V3(20f, 0f, 20f)),
                // Глубокая: к караванному пути и к тракту.
                new RoadSegment(deep, new V3(-30f, 0f, -34f)),
                new RoadSegment(deep, new V3(60f, 0f, -85f)),
                // Серебряная: к караванному пути и к дороге в деревню людей.
                new RoadSegment(silver, new V3(-200f, 0f, 3f)),
                new RoadSegment(silver, new V3(RampFoot.X, 0f, -150f)),
            };
        }

        /// Все дороги — главные и шахтные.
        public static readonly RoadSegment[] Roads = Join(MainRoads, MineRoads);

        static RoadSegment[] Join(RoadSegment[] a, RoadSegment[] b)
        {
            var all = new RoadSegment[a.Length + b.Length];
            a.CopyTo(all, 0);
            b.CopyTo(all, a.Length);
            return all;
        }
        public const float MineRock = 34f;
        public const float MineHeight = 16f;
        public const float MineEntranceAhead = 20f;
        public const float MineClearing = 42f;

        /// Рудник злодея в кольце гор, к западу от форта: все руды понемногу и
        /// конечно (ответ автора от 07.10) — камень, золото, железо, уголь.
        public static readonly V3 MicroMine = FortCentre + new V3(-115f, 0f, -20f);
        public static readonly V3[] MicroMineStone = { new V3(-5f, 0f, 4f), new V3(5f, 0f, -3f) };
        public static readonly V3[] MicroMineGold = { new V3(0f, 0f, -8f), new V3(-6f, 0f, -9f) };
        public static readonly V3[] MicroMineIron = { new V3(9f, 0f, 5f), new V3(12f, 0f, -2f) };
        public static readonly V3[] MicroMineCoal = { new V3(5f, 0f, -13f), new V3(11f, 0f, -10f) };

        // --- места сторон ------------------------------------------------------

        /// Лавка у каждой стороны своя, рядом со спавном: злодей, эльфы, стража.
        public static readonly V3[] Traders =
        {
            FortCentre + new V3(0f, 0f, 8f),
            ElvesCentre + new V3(0f, 0f, -28f),
            PalaceCentre + new V3(0f, 6f, -88f),
        };

        /// Хутора — «древние земли» для заданий эльфов: ферма у моря,
        /// разрушенная деревня на юге, рыбацкая деревня, хутор у Сосновой.
        public static readonly V3[] Hamlets =
        {
            new V3(-500f, 0f, 60f), new V3(-150f, 0f, -430f), new V3(-490f, 0f, -430f), new V3(-120f, 0f, 170f),
        };

        // --- приметы концепта (только вид) ---------------------------------------

        /// Сторожевая башня — к востоку от плато замка.
        public static readonly V3 Watchtower = new V3(-160f, 0f, 470f);
        /// Древние руины на севере леса, древний портал на юге.
        public static readonly V3 AncientRuins = new V3(-80f, 0f, 420f);
        public static readonly V3 AncientPortal = new V3(-60f, 0f, -480f);
        /// Порт на западном берегу, военный лагерь людей южнее.
        public static readonly V3 Port = new V3(-560f, 0f, -60f);
        public static readonly V3 MilitaryCamp = new V3(-420f, 0f, -340f);
        /// Второй лагерь эльфов — в восточной чаще.
        public static readonly V3 ElfCampEast = new V3(300f, 0f, 140f);
        /// Лагерь злодея — в кольце гор, к востоку от форта.
        public static readonly V3 VillainCamp = FortCentre + new V3(120f, 0f, 90f);

        // --- лес -------------------------------------------------------------

        /// Лес — на всю карту, кроме плато замка, полей людей у моря, кольца
        /// гор злодея, дорог, реки и полян.
        public const float ForestRadius = 1000f;
        /// Западнее этой линии — поля и деревни людей, не лес.
        public const float FieldsEdgeX = -290f;

        /// Куда смотрит вход шахты: к её дороге, а у шахты без дороги — прочь
        /// от поселения эльфов.
        public static V3 MineFacing(V3 at)
        {
            if (Mines != null)
                foreach (var mine in Mines)
                    if (mine.At.FlatDistance(at) < 0.01f && (mine.Facing.X != 0f || mine.Facing.Z != 0f))
                    {
                        float l = (float)Math.Sqrt(mine.Facing.X * mine.Facing.X + mine.Facing.Z * mine.Facing.Z);
                        return new V3(mine.Facing.X / l, 0f, mine.Facing.Z / l);
                    }
            var centre = ElvesCentre;
            float dx = at.X - centre.X;
            float dz = at.Z - centre.Z;
            float length = (float)Math.Sqrt(dx * dx + dz * dz);
            if (length < 0.01f) return new V3(0f, 0f, -1f);
            return new V3(dx / length, 0f, dz / length);
        }

        /// Вход шахты: точка, куда реально можно подойти и подъехать.
        public static V3 MineEntrance(V3 at)
        {
            return at + MineFacing(at) * MineEntranceAhead;
        }

        /// Первая шахта руды (для проверок и подсказок без точки отсчёта).
        public static MineSite? MineOf(ResourceKind kind)
        {
            foreach (var mine in Mines)
                if (mine.Kind == kind) return mine;
            return null;
        }

        /// Ближайшая к точке шахта руды: железа две — у каждой стороны своя.
        public static MineSite? MineOf(ResourceKind kind, V3 near)
        {
            MineSite? best = null;
            float bestGap = float.MaxValue;
            foreach (var mine in Mines)
            {
                if (mine.Kind != kind) continue;
                float gap = mine.At.FlatDistance(near);
                if (gap < bestGap)
                {
                    bestGap = gap;
                    best = mine;
                }
            }
            return best;
        }
    }
}
