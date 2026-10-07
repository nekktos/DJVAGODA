// Раскладка карты «Изумрудный Разлом» (решение автора от 07.10, по концепту):
// запад — Королевский Предел (замок людей на плато, деревни, поля);
// центр — Изумрудное Сердце (лес эльфов, все шахты — только в лесу);
// восток — Кровавый Предел (цитадель злодея, рудник, тёмные горы).
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

        public MineSite(ResourceKind kind, V3 at, string name = "")
        {
            Kind = kind;
            At = at;
            Name = name;
        }
    }

    /// Отрезок дороги на плоскости.
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

        /// Изумрудное Сердце — поселение эльфов посреди леса.
        public static readonly V3 ElvesCentre = new V3(0f, 0f, 60f);
        /// Замок людей (дворец стражи) на плато — северо-запад.
        public static readonly V3 PalaceCentre = new V3(-380f, 0f, 250f);
        /// Кровавый Предел — цитадель злодея на востоке.
        public static readonly V3 VillainCentre = new V3(410f, 0f, -20f);
        /// Деревни и поля людей — юго-запад.
        public static readonly V3 HumansCentre = new V3(-380f, 0f, -270f);

        public static readonly V3[] ZoneCenters = { ElvesCentre, PalaceCentre, VillainCentre, HumansCentre };

        public static readonly string[] ZoneNames = { "Изумрудное Сердце", "Замок людей", "Кровавый Предел", "Королевский Предел" };

        // --- дороги --------------------------------------------------------------

        /// Плато замка и пандус на него (с юга, с парапетами).
        public static readonly V3 RampFoot = PalaceCentre + new V3(0f, 0f, -225f);
        public const float PlateauHeight = 6f;
        public const float RampWidth = 40f;
        public const float RampRun = 45f;

        /// Королевский тракт: от пандуса замка через лес, в обход стены цитадели
        /// с юга, к её воротам; от тракта — на юг к деревням людей и тропа
        /// на север, в поселение эльфов.
        public const float RoadZ = -40f;
        public static readonly V3 VillainGate = VillainCentre + new V3(0f, 0f, -40f);
        public static readonly RoadSegment[] Roads =
        {
            new RoadSegment(RampFoot, new V3(RampFoot.X, 0f, RoadZ)),
            new RoadSegment(new V3(RampFoot.X, 0f, RoadZ), new V3(250f, 0f, RoadZ)),
            new RoadSegment(new V3(250f, 0f, RoadZ), new V3(VillainGate.X, 0f, -130f)),
            new RoadSegment(new V3(VillainGate.X, 0f, -130f), VillainGate),
            new RoadSegment(new V3(RampFoot.X, 0f, RoadZ), HumansCentre),
            new RoadSegment(new V3(0f, 0f, RoadZ), ElvesCentre + new V3(0f, 0f, -45f)),
        };
        public const float RoadWidth = 14f;

        /// Расстояние по плоскости до ближайшей дороги.
        public static float DistanceToRoad(float x, float z)
        {
            float best = float.MaxValue;
            foreach (var road in Roads) best = Math.Min(best, ToSegment(x, z, road.From, road.To));
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

        /// Перекрёсток: тропа эльфов выходит на тракт. От ворот замка и от ворот
        /// цитадели — поровну; рядом — верстак и стартовое сырьё.
        public static readonly V3 Crossroads = new V3(0f, 0f, RoadZ);
        public static readonly V3 Workbench = Crossroads + new V3(-24f, 0f, -22f);

        // --- шахты -----------------------------------------------------------

        /// Пять шахт, все в лесу эльфов (концепт): по железу — у каждой стороны
        /// своя ближняя; камень (север) и золото (юг) — на оси между замком и
        /// цитаделью, общие; уголь — на северо-востоке. Камень у замка обоз
        /// злодея брал через полкарты мимо стражи и погибал (долгая партия).
        public static readonly MineSite[] Mines =
        {
            new MineSite(ResourceKind.Iron, new V3(-200f, 0f, -170f), "Глубокая"),
            new MineSite(ResourceKind.Stone, new V3(20f, 0f, 360f), "Сосновая"),
            new MineSite(ResourceKind.Coal, new V3(200f, 0f, 300f), "Лунная"),
            new MineSite(ResourceKind.Gold, new V3(-40f, 0f, -250f), "Серебряная"),
            new MineSite(ResourceKind.Iron, new V3(190f, 0f, -200f), "Тихая"),
        };
        public const float MineRock = 34f;
        public const float MineHeight = 16f;
        public const float MineEntranceAhead = 20f;
        public const float MineClearing = 42f;

        /// Рудник злодея у цитадели (концепт): все руды понемногу и конечно
        /// (ответ автора от 07.10) — камень, золото, железо, уголь.
        public static readonly V3 MicroMine = VillainCentre + new V3(60f, 0f, -110f);
        public static readonly V3[] MicroMineStone = { new V3(-5f, 0f, 4f), new V3(5f, 0f, -3f) };
        public static readonly V3[] MicroMineGold = { new V3(0f, 0f, -8f), new V3(-6f, 0f, -9f) };
        public static readonly V3[] MicroMineIron = { new V3(9f, 0f, 5f), new V3(12f, 0f, -2f) };
        public static readonly V3[] MicroMineCoal = { new V3(5f, 0f, -13f), new V3(11f, 0f, -10f) };

        // --- места сторон ------------------------------------------------------

        /// Лавка у каждой стороны своя, рядом со спавном: злодей, эльфы, стража.
        public static readonly V3[] Traders =
        {
            VillainCentre + new V3(0f, 0f, 32f),
            ElvesCentre + new V3(0f, 0f, -28f),
            PalaceCentre + new V3(0f, 6f, -88f),
        };

        /// Хутора — «древние земли» для заданий эльфов: ферма у тракта,
        /// разрушенная деревня на юге, деревня людей, хутор у портала.
        public static readonly V3[] Hamlets =
        {
            new V3(-300f, 0f, -105f), new V3(-130f, 0f, -420f), new V3(-470f, 0f, -400f), new V3(150f, 0f, -420f),
        };

        // --- приметы концепта (только вид) ---------------------------------------

        /// Сторожевая башня на севере, за плато замка.
        public static readonly V3 Watchtower = new V3(-140f, 0f, 480f);
        /// Древние руины и древний портал — на краях леса, север и юг.
        public static readonly V3 AncientRuins = new V3(-100f, 0f, 400f);
        public static readonly V3 AncientPortal = new V3(100f, 0f, -262f);
        /// Военный лагерь людей — юго-запад, за деревнями.
        public static readonly V3 MilitaryCamp = new V3(-260f, 0f, -470f);
        /// Второй лагерь эльфов — в восточной чаще.
        public static readonly V3 ElfCampEast = new V3(190f, 0f, 110f);
        /// Лагерь злодея — к югу от цитадели.
        public static readonly V3 VillainCamp = new V3(400f, 0f, -250f);
        /// Тёмные горы вдоль восточного края и на северо-востоке.
        public const float MountainX = 560f;

        // --- лес -------------------------------------------------------------

        /// Лес эльфов — от центра зоны во все стороны, кроме плато замка,
        /// цитадели, деревень, дорог и полян.
        public const float ForestRadius = 400f;

        /// Квадрат плато замка (половина стороны).
        public const float PlateauHalf = 180f;

        public static bool OnPlateau(float x, float z, float margin)
        {
            return Math.Abs(x - PalaceCentre.X) <= PlateauHalf + margin && Math.Abs(z - PalaceCentre.Z) <= PlateauHalf + margin;
        }

        /// Куда смотрит вход шахты: прочь от поселения эльфов.
        public static V3 MineFacing(V3 at)
        {
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
