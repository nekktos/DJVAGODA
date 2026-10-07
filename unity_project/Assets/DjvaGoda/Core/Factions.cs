// Стороны: цели, подвижность, оружие, заклинания, вражда (перенос factions.gd).
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum Faction { Villain, Elves, Guard }

    public struct Mobility
    {
        public readonly float Speed;
        public readonly int AirJumps;
        public readonly bool Dash;

        public Mobility(float speed, int airJumps, bool dash)
        {
            Speed = speed;
            AirJumps = airJumps;
            Dash = dash;
        }
    }

    public struct Rgb
    {
        public readonly float R;
        public readonly float G;
        public readonly float B;

        public Rgb(float r, float g, float b)
        {
            R = r;
            G = g;
            B = b;
        }
    }

    public static class Factions
    {
        public const int Count = 3;
        public static readonly string[] Names = { "Злодей", "Лесные эльфы", "Охрана дворца" };

        /// Палитра подобрана под карту: эльфам не зелёный (карта зелёная), а золото.
        public static readonly Rgb[] Colors =
        {
            new Rgb(0.78f, 0.09f, 0.12f),
            new Rgb(0.95f, 0.80f, 0.10f),
            new Rgb(0.13f, 0.30f, 0.92f),
        };

        public static Mobility MobilityOf(Faction faction)
        {
            if (faction == Faction.Elves) return new Mobility(1.15f, 1, true);
            return new Mobility(1f, 0, false);
        }

        public static readonly V3[] Spawn =
        {
            MapLayout.VillainCentre + new V3(0f, 2f, 4f),
            MapLayout.ElvesCentre + new V3(0f, 2f, 0f),
            MapLayout.PalaceCentre + new V3(0f, 8f, -60f),
        };

        public static readonly int[] Slots = { 1, 5, 5 };
        static readonly bool[] HasStrategyTable = { true, false, false };
        static readonly bool[] CanBuildTable = { true, false, false };

        static readonly WeaponKind[][] WeaponSets =
        {
            new[] { WeaponKind.Sword, WeaponKind.Bow, WeaponKind.Spell, WeaponKind.Hammer },
            new[] { WeaponKind.Sword, WeaponKind.Bow, WeaponKind.Axe },
            new[] { WeaponKind.Sword, WeaponKind.Bow, WeaponKind.Crossbow },
        };

        static readonly AbilityKind[][] AbilitySets =
        {
            new[] { AbilityKind.Paralysis, AbilityKind.Wither, AbilityKind.Blind },
            new[] { AbilityKind.Heal, AbilityKind.Rally, AbilityKind.Summon },
            new AbilityKind[0],
        };

        public static readonly int[][] StartingResources =
        {
            new[] { 0, 0, 0, 0 },
            new[] { 0, 0, 0, 0 },
            new[] { 120, 120, 200, 120 },
        };

        public static readonly int[] StartingCapacity = { Res.BaseCapacity, 400, 600 };

        public static readonly string[] Goals =
        {
            "взять дворец — стража станет твоей, — потом вырезать эльфов",
            "вернуть древние земли: уничтожить злодея и стражу",
            "уничтожить злодея и эльфов и не отдать дворец",
        };

        /// Кто над кем: стража, поглощённая злодеем при захвате дворца, воюет за
        /// него. -1 — сторона сама себе хозяин.
        public static readonly int[] Overlord = { -1, -1, -1 };

        public static int Clamp(int faction)
        {
            return Res.Clamp(faction, 0, Count - 1);
        }

        /// Враги ли стороны. Неизвестная сторона (-1) — враг всем.
        public static bool Hostile(int a, int b)
        {
            if (a == b) return false;
            if (a < 0 || b < 0) return true;
            return Root(a) != Root(b);
        }

        public static int Root(int side)
        {
            if (side < 0 || side >= Overlord.Length) return side;
            int top = Overlord[side];
            return top >= 0 ? top : side;
        }

        /// Кому что строить: эльфам — только свои дома; прочим — всё, кроме
        /// эльфийских домов, если сторона строит или игрок стал командиром.
        public static bool MayBuild(Faction faction, BuildingKind kind, bool leader)
        {
            bool elfHouse = Res.IsElfHouse(kind);
            if (faction == Faction.Elves) return elfHouse;
            if (elfHouse) return false;
            return CanBuild(faction) || leader;
        }

        /// Доля удара по злодею (телу или постройке) от источника: стража бьёт
        /// по своей снаряжённости (ответ автора от 29.09). Прочие — в полную.
        public static float VillainHitScale(Faction target, int sourceFaction, int gearTier, int armorTier)
        {
            if (target != Faction.Villain || sourceFaction != (int)Faction.Guard) return 1f;
            return Res.VillainTakenFromGuard(gearTier + armorTier);
        }

        public static bool HasStrategy(Faction faction) { return HasStrategyTable[(int)faction]; }
        public static bool CanBuild(Faction faction) { return CanBuildTable[(int)faction]; }

        public static WeaponKind[] WeaponsOf(Faction faction) { return WeaponSets[(int)faction]; }
        public static AbilityKind[] AbilitiesOf(Faction faction) { return AbilitySets[(int)faction]; }

        public static bool AllowsWeapon(Faction faction, WeaponKind weapon)
        {
            return System.Array.IndexOf(WeaponSets[(int)faction], weapon) >= 0;
        }

        public static bool AllowsAbility(Faction faction, AbilityKind ability)
        {
            return System.Array.IndexOf(AbilitySets[(int)faction], ability) >= 0;
        }

        public static WeaponKind DefaultWeapon(Faction faction)
        {
            var set = WeaponSets[(int)faction];
            return set.Length > 0 ? set[0] : WeaponKind.Sword;
        }

        public static string NameOf(Faction faction) { return Names[(int)faction]; }
        public static string GoalOf(Faction faction) { return Goals[(int)faction]; }
    }
}
