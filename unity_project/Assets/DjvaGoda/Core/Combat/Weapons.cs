// Оружие и заклинания (перенос weapons.gd и abilities.gd).
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    /// Виды оружия. Новые — только в конец: номер уходит в сеть.
    public enum WeaponKind { Sword, Bow, Spell, Axe, Hammer, Crossbow }

    public enum AbilityKind { Heal, Rally, Summon, Paralysis, Wither, Blind }

    public static class Weapons
    {
        public static readonly string[] Names = { "меч", "лук", "огненный шар", "топор", "молот", "арбалет" };
        public static readonly float[] Cooldown = { 0.7f, 1.0f, 1.5f, 0.55f, 1.25f, 1.6f };
        public static readonly float[] Damage = { 35f, 30f, 45f, 28f, 52f, 44f };

        public const float AxeBleedChance = 0.35f;
        public const float HammerStagger = 1.1f;
        public const float CrossbowPierce = 0.6f;
        public const float SwordRange = 2.6f;
        public const float SwordHalfAngle = 0.9f;
        public const float SpellBlastRadius = 6f;
        public const float ProjectileLifetime = 6f;

        /// Отрубает ли оружие конечность (режущее), а не калечит.
        public static bool Severs(WeaponKind kind)
        {
            return kind == WeaponKind.Sword || kind == WeaponKind.Axe;
        }

        public static bool IsProjectile(WeaponKind kind)
        {
            return kind == WeaponKind.Bow || kind == WeaponKind.Spell || kind == WeaponKind.Crossbow;
        }

        public static bool IsMelee(WeaponKind kind)
        {
            return !IsProjectile(kind);
        }

        public static float MeleeRange(WeaponKind kind)
        {
            switch (kind)
            {
                case WeaponKind.Axe: return 2.5f;
                case WeaponKind.Hammer: return 3f;
                default: return SwordRange;
            }
        }

        public static float ProjectileSpeed(WeaponKind kind)
        {
            switch (kind)
            {
                case WeaponKind.Bow: return 55f;
                case WeaponKind.Spell: return 32f;
                case WeaponKind.Crossbow: return 70f;
                default: return 0f;
            }
        }

        /// Топор вдвое добычливее по дереву, молот — по камню.
        public static float HarvestBonus(WeaponKind kind, ResourceKind resource)
        {
            if (kind == WeaponKind.Axe && resource == ResourceKind.Wood) return 2f;
            if (kind == WeaponKind.Hammer && resource == ResourceKind.Stone) return 2f;
            return 1f;
        }

        public static bool UsesArrows(WeaponKind kind)
        {
            return kind == WeaponKind.Bow || kind == WeaponKind.Crossbow;
        }

        public const int GearTiers = 3;
        static readonly string[] GearNames = { "простое", "калёное", "эльфийское" };
        static readonly string[] ForgedNames = { "простое", "калёное", "булатное" };
        static readonly float[] GearDamageTable = { 1f, 1.25f, 1.55f };
        static readonly float[] GearCooldownTable = { 1f, 0.92f, 0.85f };

        public static float GearDamage(int tier) { return GearDamageTable[Res.Clamp(tier, 0, GearTiers - 1)]; }
        public static float GearCooldown(int tier) { return GearCooldownTable[Res.Clamp(tier, 0, GearTiers - 1)]; }

        /// Название ступени оружия: у кузни людей не «эльфийское», а «булатное».
        public static string GearName(int tier, bool forged)
        {
            var names = forged ? ForgedNames : GearNames;
            return names[Res.Clamp(tier, 0, GearTiers - 1)];
        }
    }

    public static class Abilities
    {
        public static readonly string[] Names =
        {
            "лечение", "клич леса", "призыв стаи белок",
            "паралич воли", "проклятие увядания", "слепящее проклятие"
        };
        public static readonly float[] Cooldown = { 8f, 22f, 30f, 28f, 14f, 18f };
        public static readonly float[] ManaCost = { 25f, 35f, 50f, 45f, 30f, 30f };
        public static readonly float[] Range = { 12f, 18f, 5f, 20f, 18f, 22f };

        public const float HealAmount = 45f;
        public const float RallyDuration = 12f;
        public const float RallySpeedScale = 1.35f;
        public const float RallyAttackScale = 0.72f;
        public const float SummonLifetime = 60f;
        /// Стая белок (решение автора от 02.10, вместо двух волков): от трёх без
        /// прокачки самого заклинания до пятнадцати на её пределе.
        public const int SwarmMin = 3;
        public const int SwarmMax = 15;

        /// Прокачка заклинания (за опыт, как уровни здоровья и маны): 0..MaxSpellLevel.
        public const int MaxSpellLevel = 5;

        /// У каких заклинаний прокачка что-то меняет. Пока — только у призыва:
        /// уровень без действия обманывал бы игрока.
        public static bool Upgradable(AbilityKind kind) { return kind == AbilityKind.Summon; }

        /// Что даёт следующий уровень — для окна прокачки.
        public static string UpgradeText(AbilityKind kind, int level)
        {
            if (kind == AbilityKind.Summon) return "белок в стае: " + SwarmSize(level);
            return "";
        }

        /// Сколько белок в стае при уровне заклинания «призыв стаи белок».
        public static int SwarmSize(int spellLevel)
        {
            int level = spellLevel < 0 ? 0 : (spellLevel > MaxSpellLevel ? MaxSpellLevel : spellLevel);
            return SwarmMin + (int)System.Math.Round((SwarmMax - SwarmMin) * (double)level / MaxSpellLevel);
        }
        public const float ParalysisCast = 1.75f;
        public const float ParalysisHold = 3f;
        public const float ParalysisCharm = 8f;
        public const float ParalysisImmunity = 25f;
        public const float WitherDuration = 8f;
        public const float WitherDamageScale = 0.65f;
        public const float BlindDuration = 7f;

        public static float CastTime(AbilityKind kind)
        {
            return kind == AbilityKind.Paralysis ? ParalysisCast : 0f;
        }

        public static string NameOf(AbilityKind kind) { return Names[(int)kind]; }
        public static float RangeOf(AbilityKind kind) { return Range[(int)kind]; }
    }
}
