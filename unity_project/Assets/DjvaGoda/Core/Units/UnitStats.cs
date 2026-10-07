// Числа бойцов, батраков, лошадей и ИИ (перенос констант unit.gd, labourer.gd,
// horse.gd, garrison.gd, warband.gd, hero.gd). Поведение — Unity-слой; числа
// выверены долгими прогонами Godot-версии, почему каждое такое — там.
namespace DjvaGoda.Core
{
    public enum UnitKind { Swordsman, Archer, Champion, Beast }

    public static class UnitStats
    {
        /// Множитель урона по зоне попадания: голова вдвое, конечности слабее.
        public static float ZoneMultiplier(string zone)
        {
            switch (zone)
            {
                case "head": return 2f;
                case "torso": return 1f;
                case "arm_l":
                case "arm_r":
                case "leg_l":
                case "leg_r": return 0.7f;
                default: return 1f;
            }
        }

        public static float Health(UnitKind kind)
        {
            switch (kind)
            {
                case UnitKind.Archer: return 65f;
                case UnitKind.Champion: return 700f;
                // Зверь призыва — белка: одна слаба, сила в стае.
                case UnitKind.Beast: return 12f;
                default: return 90f;
            }
        }

        /// Шаг рядового бойца; по нему ИИ считает, успеет ли к точке перехвата.
        public const float BaseSpeed = 5.2f;

        public static float Speed(UnitKind kind)
        {
            switch (kind)
            {
                case UnitKind.Champion: return 6.6f;
                case UnitKind.Beast: return 8f;
                default: return BaseSpeed;
            }
        }

        public static float StrikeDamage(UnitKind kind)
        {
            switch (kind)
            {
                case UnitKind.Champion: return 32f;
                case UnitKind.Beast: return 3f;
                // Лучник стреляет стрелой лука, а не бьёт как мечник.
                case UnitKind.Archer: return Weapons.Damage[(int)WeaponKind.Bow];
                default: return 22f;
            }
        }

        public static float StrikeCooldown(UnitKind kind)
        {
            switch (kind)
            {
                case UnitKind.Champion: return 1f;
                case UnitKind.Beast: return 0.6f;
                case UnitKind.Archer: return Weapons.Cooldown[(int)WeaponKind.Bow];
                default: return 1.1f;
            }
        }

        public static float EngageRange(UnitKind kind)
        {
            switch (kind)
            {
                case UnitKind.Archer: return 32f;
                case UnitKind.Champion: return 20f;
                default: return 14f;
            }
        }

        public const float StrikeRange = 2.4f;
        public const float ArcherRange = 24f;
        public const float ArcherRear = 7f;
        /// Отряд игрока и звери призыва: в бой не дальше этого от своего якоря
        /// (командир, точка приказа, повозка) — иначе строй растаскивает по карте.
        public const float SquadLeash = 30f;
        public const float SlotTolerance = 1.2f;
        public const float SeparationRadius = 1.7f;
        public const float SeparationForce = 5f;
        public const float MaxFlatSpeed = 9f;
        public const float DirectRange = 25f;
        public const float BlockedSeconds = 0.5f;
        public const float ProgressStep = 0.6f;
        public const float RepathDistance = 6f;
        public const float WaypointRadius = 2.5f;
    }

    public static class LabourerStats
    {
        public static readonly string[] RoleNames = { "лесоруб", "шахтёр", "ополченец", "строитель", "фермер" };
        public const int LoadLimit = 30;
        public const float WorkInterval = 1.2f;
        public const float MineDigReach = 9f;
        public const float WorkRange = 4.5f;
        public const float RetargetInterval = 2f;
        public const float FleeRadius = 18f;

        /// Что добывает роль. Шахтёр — и золото микро-шахты: иначе злодею не на что
        /// нанять второго батрака и купить лошадь.
        public static ResourceKind[] Resources(LabourerRole role)
        {
            if (role == LabourerRole.Lumberjack) return new[] { ResourceKind.Wood };
            if (role == LabourerRole.Miner) return new[] { ResourceKind.Stone, ResourceKind.Iron, ResourceKind.Gold };
            return new ResourceKind[0];
        }
    }

    public static class HorseStats
    {
        public const float Health = 90f;
        public const float RideSpeedScale = 1.55f;
        public const float MountRange = 4f;
    }

    public static class AiStats
    {
        // Гарнизон.
        public const int GarrisonSize = 4;
        public const float GarrisonLeash = 90f;
        public const float GarrisonCheck = 3f;

        // Отряд.
        public static readonly string[] WarbandStateNames = { "обороняет базу", "идёт в набег", "дерётся", "отходит" };
        public const float WarbandThink = 2f;
        public const float WaypointReached = 5f;
        public const float BandReached = 8f;
        public const float LeadDistance = 14f;
        public const float ArriveRadius = 14f;
        public const float FightRadius = 22f;
        public const float MarchLeash = 26f;
        public const float RetreatFraction = 0.5f;
        public const float SallyFraction = 1f;
        public const float RaidRange = 800f;
        /// С какого числа бойцов войско злодея-ИИ идёт брать дворец: гарнизон —
        /// четверо, значит, нужно ещё хотя бы четверо нанятых.
        public const int AssaultBand = 8;
        public const float StuckSeconds = 24f;
        public const float StuckStep = 2f;
        /// Враг у своей постройки или батрака — идём отбивать (не дальше DefendRange от базы).
        public const float DefendRadius = 30f;
        public const float DefendRange = 220f;

        // Вожак ИИ.
        public const float HeroThink = 0.5f;
        public const float HeroLeash = 18f;
        /// Врага ближе этого вожак бьёт, куда бы ни тянул поводок.
        public const float CloseFight = 12f;
        public const float AtAnchor = 6f;
        public const float Sight = 34f;
        public const float MeleeReach = 4f;
        /// Ближе огненным шаром не бьём: взрыв достанет и самого.
        public const float SafeSpellGap = Weapons.SpellBlastRadius + 3f;
        public const float PanicFraction = 0.5f;
        public const int ClusterSize = 3;
        public const float ClusterRadius = 9f;
        /// Покупать и закалять — только при вдвое большем запасе.
        public const float Surplus = 2f;
        public const float PotionAt = 0.4f;
        public const float MicroRadius = 20f;
        public const float MineReach = 2.4f;
        public static readonly float[] ElfRing = { 32f, 48f, 62f };
        public const int ElfAngles = 12;
        public const float ElfWoods = 110f;
    }
}
