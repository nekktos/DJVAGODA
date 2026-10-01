// Раскладка карты: зоны, шахты, лавки, микро-шахта, хутора, дворец
// (перенос постоянных world_builder.gd и соседей). Геометрию строит Unity-слой;
// здесь — где что стоит. Почему именно там — в комментариях Godot-версии.
using System;

namespace DjvaGoda.Core
{
    public enum Zone { Elves, Emperor, Villain, Humans }

    public struct MineSite
    {
        public readonly ResourceKind Kind;
        public readonly V3 At;

        public MineSite(ResourceKind kind, V3 at)
        {
            Kind = kind;
            At = at;
        }
    }

    public static class MapLayout
    {
        public const float WorldSize = 1200f;
        public const float ZoneSize = 600f;
        public const float ZoneHalf = ZoneSize * 0.5f;

        public static readonly V3 Workbench = new V3(-24f, 0f, -22f);

        /// Четыре шахты, все в лесу эльфов: железо и золото — поровну злодею и
        /// страже, камень ближе к злодею, уголь — к страже (GDD 9a).
        public static readonly MineSite[] Mines =
        {
            new MineSite(ResourceKind.Iron, new V3(-167f, 0f, 158f)),
            new MineSite(ResourceKind.Stone, new V3(-250f, 0f, 110f)),
            new MineSite(ResourceKind.Coal, new V3(-120f, 0f, 230f)),
            new MineSite(ResourceKind.Gold, new V3(-226f, 0f, 225f)),
        };
        public const float MineRock = 34f;
        public const float MineHeight = 16f;
        public const float MineEntranceAhead = 20f;
        public const float MineClearing = 42f;

        /// Микро-шахта злодея — сразу за восточной стеной форта: камень и золото.
        public static readonly V3 MicroMine = new V3(-192f, 0f, -296f);
        public static readonly V3[] MicroMineStone = { new V3(-5f, 0f, 4f), new V3(5f, 0f, -3f) };
        public static readonly V3[] MicroMineGold = { new V3(0f, 0f, -8f), new V3(-6f, 0f, -9f) };

        /// Лавка у каждой стороны своя, рядом со спавном.
        public static readonly V3[] Traders =
        {
            new V3(-300f, 0f, -268f),
            new V3(-300f, 0f, 272f),
            new V3(300f, 6f, 212f),
        };

        public static readonly V3[] ZoneCenters =
        {
            new V3(-300f, 0f, 300f),
            new V3(300f, 0f, 300f),
            new V3(-300f, 0f, -300f),
            new V3(300f, 0f, -300f),
        };

        public static readonly string[] ZoneNames = { "Зона эльфов", "Зона императора", "Зона злодея", "Зона людей" };

        /// Хутора — «древние земли» для заданий эльфов.
        public static readonly V3[] Hamlets =
        {
            new V3(-150f, 0f, -150f), new V3(155f, 0f, -140f), new V3(150f, 0f, 160f), new V3(-160f, 0f, 140f),
        };

        /// Плато императора и пандус на него (с фасада, с парапетами).
        public static readonly V3 RampFoot = new V3(300f, 0f, 75f);
        public const float PlateauHeight = 6f;
        public const float RampWidth = 40f;
        public const float RampRun = 45f;

        /// Куда смотрит вход шахты: прочь от поселения эльфов.
        public static V3 MineFacing(V3 at)
        {
            var centre = ZoneCenters[(int)Zone.Elves];
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

        public static MineSite? MineOf(ResourceKind kind)
        {
            foreach (var mine in Mines)
                if (mine.Kind == kind) return mine;
            return null;
        }
    }
}
