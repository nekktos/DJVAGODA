// Ресурсы, постройки и цены — одним местом (перенос resources.gd).
//
// ЯДРО НА ЧИСТОМ C#, без UnityEngine (noEngineReferences): правила игры
// проверяются EditMode-набором (Tests/EditMode/CoreTests.cs) без сцены, а
// Unity-слой ложится поверх. Язык — C# 9, как во всём проекте.
//
// Числа — те же, что в Godot-версии: они выверены живыми playtest'ами и
// «долгими партиями», и перенос не повод их трогать. Почему каждое именно
// такое — в комментариях Godot-версии (godot_project/scripts/economy/resources.gd).
using System;
using System.Collections.Generic;
using System.Text;

namespace DjvaGoda.CoreOld
{
    /// Виды ресурсов. Новые — ТОЛЬКО В КОНЕЦ: номер уходит в сеть и в сохранение.
    public enum ResourceKind { Wood, Stone, Gold, Iron, Food, Coal }

    /// Виды построек. Новые — только в конец (номер уходит в сеть и сейв).
    public enum BuildingKind
    {
        Storage, SwordBarracks, ArcherBarracks, Stable, House, Farm,
        ElfHouse, ElfStoneHouse, Forge
    }

    /// Ступени материала построек (ответ автора от 29.09).
    public enum Grade { Wood, WoodStone, Stone, StoneIron }

    /// Товары лавок. Новые — в конец.
    public enum TradeItem { Bandages, Gear, Arrows, Armor, PotionHeal, PotionMana }

    public static class Res
    {
        public const int Count = 6;

        public static readonly string[] Names = { "дерево", "камень", "золото", "железо", "еда", "уголь" };
        public static readonly string[] Short = { "дер", "кам", "зол", "жел", "еда", "уг" };

        /// Базовый запас склада на каждый ресурс; склад поднимает потолок.
        public const int BaseCapacity = 120;
        public const int StorageBonus = 400;

        public const int YieldPerHit = 5;
        /// Микро-шахта злодея: хватает только на путь до первого обоза.
        public const int MicroStoneHitsEach = 3;
        public const int MicroGoldHitsEach = 4;
        public const int SourceHits = 6;
        public const float HarvestRange = 3.2f;

        // --- постройки --------------------------------------------------------

        public static readonly string[] BuildingNames =
        {
            "склад", "казарма мечников", "казарма лучников", "конюшня",
            "дом дружины", "поле", "дом эльфов", "каменный дом эльфов", "кузня"
        };

        public const int ElfHousesPerPlayer = 5;

        /// Прочее без ступеней (поле) держит столько же, сколько деревянная постройка.
        public const float DefaultBuildingHealth = 1200f;

        public static readonly string[] GradeNames = { "дерево", "дерево и камень", "камень", "камень и железо" };
        public static readonly float[] GradeHealth = { 1200f, 2000f, 3200f, 5000f };

        /// Цена перехода НА ступень. Железо — только на последнюю.
        static readonly Dictionary<Grade, int[]> GradeCostTable = new Dictionary<Grade, int[]>
        {
            { Grade.WoodStone, new[] { 30, 40, 0, 0 } },
            { Grade.Stone, new[] { 0, 90, 0, 0 } },
            { Grade.StoneIron, new[] { 0, 60, 0, 40 } },
        };

        public static bool IsElfHouse(BuildingKind kind)
        {
            return kind == BuildingKind.ElfHouse || kind == BuildingKind.ElfStoneHouse;
        }

        /// Поле — пашня, а не стена: по нему ходят, и обходить его не должен никто.
        public static bool Walkable(BuildingKind kind)
        {
            return kind == BuildingKind.Farm;
        }

        public static bool Gradeable(BuildingKind kind)
        {
            return !IsElfHouse(kind) && kind != BuildingKind.Farm;
        }

        public static float BuildingHealth(BuildingKind kind, int grade)
        {
            if (kind == BuildingKind.ElfHouse) return 350f;
            if (kind == BuildingKind.ElfStoneHouse) return 900f;
            if (!Gradeable(kind)) return DefaultBuildingHealth;
            return GradeHealth[Clamp(grade, 0, GradeHealth.Length - 1)];
        }

        /// Цена следующей ступени; пусто — крепче некуда.
        public static int[] GradeCost(BuildingKind kind, int grade)
        {
            int[] cost;
            if (!Gradeable(kind) || !GradeCostTable.TryGetValue((Grade)(grade + 1), out cost))
                return new int[0];
            return cost;
        }

        static readonly Dictionary<BuildingKind, int[]> BuildingCostTable = new Dictionary<BuildingKind, int[]>
        {
            { BuildingKind.Storage, new[] { 40, 20, 0, 0 } },
            { BuildingKind.SwordBarracks, new[] { 60, 40, 0, 10 } },
            { BuildingKind.ArcherBarracks, new[] { 70, 25, 0, 20 } },
            { BuildingKind.Stable, new[] { 50, 15, 0, 0 } },
            { BuildingKind.House, new[] { 90, 60, 0, 0 } },
            { BuildingKind.Farm, new[] { 60, 20, 0, 0 } },
            { BuildingKind.ElfHouse, new[] { 60, 0, 0, 0 } },
            { BuildingKind.ElfStoneHouse, new[] { 30, 60, 0, 0 } },
            { BuildingKind.Forge, new[] { 80, 60, 0, 20 } },
        };

        public static int[] BuildingCost(BuildingKind kind)
        {
            return BuildingCostTable[kind];
        }

        static readonly Dictionary<BuildingKind, float> BuildTimeTable = new Dictionary<BuildingKind, float>
        {
            { BuildingKind.Storage, 6f }, { BuildingKind.SwordBarracks, 8f },
            { BuildingKind.ArcherBarracks, 9f }, { BuildingKind.Stable, 7f },
            { BuildingKind.House, 10f }, { BuildingKind.Farm, 8f },
            { BuildingKind.ElfHouse, 25f }, { BuildingKind.ElfStoneHouse, 40f },
            { BuildingKind.Forge, 20f },
        };

        public static float BuildTime(BuildingKind kind)
        {
            return BuildTimeTable[kind];
        }

        static readonly Dictionary<BuildingKind, V3> BuildingSizeTable = new Dictionary<BuildingKind, V3>
        {
            { BuildingKind.Storage, new V3(12f, 7f, 10f) },
            { BuildingKind.SwordBarracks, new V3(14f, 6f, 9f) },
            { BuildingKind.ArcherBarracks, new V3(12f, 6f, 9f) },
            { BuildingKind.Stable, new V3(14f, 5f, 11f) },
            { BuildingKind.House, new V3(16f, 5f, 9f) },
            { BuildingKind.Farm, new V3(20f, 2f, 16f) },
            { BuildingKind.ElfHouse, new V3(10f, 7f, 10f) },
            { BuildingKind.ElfStoneHouse, new V3(10f, 7f, 10f) },
            { BuildingKind.Forge, new V3(12f, 6f, 10f) },
        };

        public static V3 BuildingSize(BuildingKind kind)
        {
            return BuildingSizeTable[kind];
        }

        // --- люди и лошади ----------------------------------------------------

        public static readonly int[] UnitCost = { 0, 0, 25, 10 };
        public static readonly int[] ArcherCost = { 0, 0, 20, 18 };
        public static readonly int[] LabourerCost = { 0, 0, 12, 0 };
        public const int LabourerLimit = 8;
        public const int SquadBase = 3;
        public const int HouseSlots = 3;
        public const int SquadLimit = 12;
        public static readonly int[] HorseCost = { 25, 0, 12, 0 };
        public const int HorseLimit = 12;

        public static int[] ProstheticCost(int quality)
        {
            switch (quality)
            {
                case 1: return new[] { 20, 0, 0, 0 };
                case 2: return new[] { 10, 0, 30, 40 };
                case 3: return new[] { 10, 0, 150, 80 };
                default: return new int[0];
            }
        }

        // --- хранилища ----------------------------------------------------------

        /// Пустое хранилище длины Count. Через него заводятся ВСЕ склады и грузы.
        public static int[] Empty()
        {
            return new int[Count];
        }

        /// Подогнать хранилище под Count: короткое дополняем нулями, длинное режем.
        public static int[] Fit(int[] values)
        {
            var output = Empty();
            for (int i = 0; i < Count; i++) output[i] = At(values, i);
            return output;
        }

        /// Сколько этого ресурса в цене. Короткий массив читается нулём:
        /// цены построек остались четвёрками намеренно.
        public static int At(int[] cost, int kind)
        {
            if (cost == null || kind < 0 || kind >= cost.Length) return 0;
            return cost[kind];
        }

        public static int At(int[] cost, ResourceKind kind)
        {
            return At(cost, (int)kind);
        }

        /// Хватает ли запаса на цену.
        public static bool CanAfford(int[] stock, int[] cost)
        {
            for (int i = 0; i < Count; i++)
                if (At(stock, i) < At(cost, i)) return false;
            return true;
        }

        public static string FormatCost(int[] cost)
        {
            var parts = new List<string>();
            for (int i = 0; i < Count; i++)
                if (At(cost, i) > 0) parts.Add(Short[i] + " " + At(cost, i));
            return parts.Count > 0 ? string.Join(", ", parts.ToArray()) : "бесплатно";
        }

        /// Подсказка, ГДЕ взять недостающее — только про то, что руками не добыть.
        public static string ShortfallHint(int[] cost, IStock have)
        {
            if (have == null) return "";
            var missing = new List<ResourceKind>();
            foreach (var kind in new[] { ResourceKind.Gold, ResourceKind.Iron })
                if (At(cost, kind) > have.GetAmount(kind)) missing.Add(kind);
            if (missing.Count == 0) return "";
            string what = Names[(int)missing[0]];
            if (missing.Count > 1) what = Names[(int)missing[0]] + " и " + Names[(int)missing[1]];
            return " (" + what + " есть только в шахтах на земле эльфов: вези караваном)";
        }

        // --- лавки, доспех, снаряжение ---------------------------------------------

        public static TradeItem[] Shop(Faction faction)
        {
            if (faction == Faction.Elves)
                return new[] { TradeItem.Bandages, TradeItem.Arrows, TradeItem.Gear, TradeItem.Armor,
                    TradeItem.PotionHeal, TradeItem.PotionMana };
            return new[] { TradeItem.Bandages, TradeItem.Arrows, TradeItem.Armor };
        }

        public const int ArmorTiers = 2;
        static readonly float[] PlateTaken = { 1f, 0.82f, 0.66f };
        static readonly float[] LeatherTaken = { 1f, 0.88f, 0.78f };

        public static int[] ArmorCost(Faction faction, int tier)
        {
            if (faction == Faction.Elves)
            {
                if (tier == 1) return new[] { 0, 0, 40, 0 };
                if (tier == 2) return new[] { 0, 0, 120, 0 };
            }
            else
            {
                if (tier == 1) return new[] { 0, 0, 50, 25 };
                if (tier == 2) return new[] { 0, 0, 140, 60 };
            }
            return new int[0];
        }

        public static float ArmorTaken(Faction faction, int tier)
        {
            var table = faction == Faction.Elves ? LeatherTaken : PlateTaken;
            return table[Clamp(tier, 0, table.Length - 1)];
        }

        public static string ArmorName(Faction faction, int tier)
        {
            string[] names;
            if (faction == Faction.Elves) names = new[] { "без доспеха", "кожаная куртка", "эльфийская броня" };
            else if (faction == Faction.Guard) names = new[] { "без доспеха", "серебряная кираса", "серебряные латы" };
            else names = new[] { "без доспеха", "чёрная кираса", "чёрные латы" };
            return names[Clamp(tier, 0, names.Length - 1)];
        }

        /// Доля урона злодею от стражника по его снаряжённости (оружие + доспех,
        /// 0…4) — ответ автора от 29.09: непрокачанная стража злодею не ровня.
        public static readonly float[] VillainTakenFromGuardTable = { 0.1f, 0.2f, 0.35f, 0.6f, 1f };

        public static float VillainTakenFromGuard(int kit)
        {
            return VillainTakenFromGuardTable[Clamp(kit, 0, VillainTakenFromGuardTable.Length - 1)];
        }

        public static int[] ElfGearCost(int tier)
        {
            if (tier == 1) return new[] { 0, 0, 80, 0 };
            if (tier == 2) return new[] { 0, 0, 220, 0 };
            return new int[0];
        }

        /// Закалка в кузне: железо и уголь, немного золота.
        public static int[] ForgeGearCost(int tier)
        {
            if (tier == 1) return new[] { 0, 0, 20, 20, 0, 10 };
            if (tier == 2) return new[] { 0, 0, 60, 60, 0, 30 };
            return new int[0];
        }

        public static readonly int[] ElfArrowCost = { 0, 0, 6, 0 };
        public const int PotionLimit = 3;
        public static readonly int[] PotionHealCost = { 0, 0, 25, 0 };
        public static readonly int[] PotionManaCost = { 0, 0, 20, 0 };
        public const float PotionHeal = 50f;
        public const float PotionMana = 60f;
        public static readonly int[] SplintCost = { 10, 0, 12, 0 };

        // --- поле и голод -------------------------------------------------------------

        public const float FarmRate = 0.25f;
        public const int FarmCap = 120;
        public const float FeedInterval = 300f;
        public const int FeedPerWorker = 12;
        public const int HungerFatal = 3;
        public const float HungerSlowdown = 2f;

        public const int BandagePack = 3;
        public const int BandageLimit = 9;
        public static readonly int[] BandageCost = { 0, 0, 15, 0 };

        public const int ArrowPack = 20;
        public const int QuiverLimit = 60;
        public const int QuiverStart = 30;
        public static readonly int[] ArrowCost = { 0, 0, 5, 2 };

        public static int Clamp(int value, int min, int max)
        {
            return value < min ? min : (value > max ? max : value);
        }
    }

    /// Любой запас, у которого можно спросить количество: кошелёк, склад, куча.
    public interface IStock
    {
        int GetAmount(ResourceKind kind);
    }
}
