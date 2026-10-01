// Формулы урона (перенос из player.gd, projectile.gd, unit.gd).
//
// Урон удара = база оружия × множитель зоны × закалка × (проклятие увядания).
// Затем у цели: строй бойца, доспех персонажа, правило стражи для злодея.
using System;

namespace DjvaGoda.CoreOld
{
    public static class DamageRules
    {
        /// Урон, с которым удар выходит из руки: ближний бой или прямое попадание снаряда.
        public static float Outgoing(WeaponKind weapon, string zone, int gearTier, bool attackerWithered)
        {
            float curse = attackerWithered ? Abilities.WitherDamageScale : 1f;
            return Weapons.Damage[(int)weapon] * UnitStats.ZoneMultiplier(zone) * Weapons.GearDamage(gearTier) * curse;
        }

        /// Взрыв огненного шара: затухает к краю радиуса; по краю — ноль.
        public static float Blast(float distance, string zone, int gearTier)
        {
            float falloff = Math.Max(0f, Math.Min(1f, 1f - distance / Weapons.SpellBlastRadius));
            return Weapons.Damage[(int)WeaponKind.Spell] * UnitStats.ZoneMultiplier(zone) * falloff * Weapons.GearDamage(gearTier);
        }

        /// Арбалет пробивает защиту СТРОЯ (не снаряжения): возвращает часть
        /// отнятой строем защиты. Сплошной строй без защиты — как есть.
        public static float PierceScale(WeaponKind weapon, float defensiveScale)
        {
            if (weapon != WeaponKind.Crossbow || defensiveScale <= 0.01f || defensiveScale >= 1f) return 1f;
            float pierced = defensiveScale + (1f - defensiveScale) * Weapons.CrossbowPierce;
            return pierced / defensiveScale;
        }

        /// Сколько снимет удар по бойцу в строю.
        public static float ToUnit(float amount, FormationKind formation, bool aoe, WeaponKind? weapon)
        {
            float scale = Formations.DamageScale(formation, aoe);
            float pierce = weapon.HasValue ? PierceScale(weapon.Value, scale) : 1f;
            return amount * scale * pierce;
        }

        /// Сколько снимет удар по персонажу: доспех, затем правило стражи для злодея.
        public static float ToCharacter(float amount, Kit target, int sourceFaction, int sourceGear, int sourceArmor)
        {
            float armor = Res.ArmorTaken(target.Side, target.ArmorTier);
            float guardRule = Factions.VillainHitScale(target.Side, sourceFaction, sourceGear, sourceArmor);
            return amount * armor * guardRule;
        }
    }
}
