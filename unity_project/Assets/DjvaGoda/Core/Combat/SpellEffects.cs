// Что делают удар, добыча и заклинания, когда хост их исполняет
// (перенос player.gd: _server_swing_melee, _server_try_harvest, _server_cast_*).
//
// Физику (сфера удара, луч добычи, зоны попадания) держит Unity-слой; здесь —
// кого из найденного бить, сколько добыть, на кого ляжет заклинание.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    /// Зона попадания, которую нашла сфера удара: чья и с каким множителем.
    public struct ZoneHit
    {
        public readonly int Target;
        public readonly string Zone;
        public readonly V3 Centre;

        public ZoneHit(int target, string zone, V3 centre)
        {
            Target = target;
            Zone = zone;
            Centre = centre;
        }
    }

    public static class MeleeRules
    {
        /// Грудь цели — на метр выше её ног: туда и меряется угол замаха.
        public const float ChestHeight = 1f;

        /// В дуге ли замаха: угол между прицелом и направлением на грудь цели не больше 0.9 рад.
        public static bool InArc(V3 aim, V3 origin, V3 targetFeet)
        {
            var to = targetFeet + new V3(0f, ChestHeight, 0f) - origin;
            if (to.Length() <= 0.01f) return true;
            var a = aim.Normalized();
            var b = to.Normalized();
            float dot = Math.Max(-1f, Math.Min(1f, a.X * b.X + a.Y * b.Y + a.Z * b.Z));
            return Math.Acos(dot) <= Weapons.SwordHalfAngle;
        }

        /// По каждой цели в дуге — одна зона, самая ценная (голова лучше тела):
        /// один взмах не бьёт одного и того же дважды.
        public static Dictionary<int, ZoneHit> BestZones(IEnumerable<ZoneHit> hits, V3 aim, V3 origin,
            Func<int, V3> feetOf, int self)
        {
            var best = new Dictionary<int, ZoneHit>();
            foreach (var hit in hits)
            {
                if (hit.Target == self) continue;
                if (!InArc(aim, origin, feetOf(hit.Target))) continue;
                ZoneHit prev;
                if (!best.TryGetValue(hit.Target, out prev)
                    || UnitStats.ZoneMultiplier(hit.Zone) > UnitStats.ZoneMultiplier(prev.Zone))
                    best[hit.Target] = hit;
            }
            return best;
        }

        /// Добыча за удар: пять единиц, умноженные на бонус оружия (топор по лесу, молот по камню).
        public static int HarvestYield(WeaponKind weapon, ResourceKind resource)
        {
            return (int)Math.Round(Res.YieldPerHit * Weapons.HarvestBonus(weapon, resource), MidpointRounding.AwayFromZero);
        }
    }

    public static class SpellEffects
    {
        /// Ближайший живой враг в радиусе заклинания (игроки и бойцы).
        public static Sighting? NearestEnemy(int side, V3 here, float radius, IEnumerable<Sighting> around)
        {
            Sighting? best = null;
            float bestDistance = radius;
            foreach (var other in around)
            {
                if (!Factions.Hostile(side, other.Side)) continue;
                float d = here.Distance(other.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = other;
                }
            }
            return best;
        }

        /// Лечение эльфа: здоровье +45, кровотечение останавливается, одна
        /// перебитая (не оторванная) конечность срастается. true — было что лечить.
        public static bool Heal(Vitals vitals, BodyState body)
        {
            bool restored = false;
            if (vitals.Health < vitals.MaxHealth)
            {
                vitals.Health = Math.Min(vitals.MaxHealth, vitals.Health + Abilities.HealAmount);
                restored = true;
            }
            if (body.Bleeding)
            {
                body.Bleeding = false;
                restored = true;
            }
            for (int limb = 0; limb < 4; limb++)
                if (body.HealLimb((Limb)limb))
                {
                    restored = true;
                    break;
                }
            return restored;
        }

        /// Увядание по бойцу (не игроку): урон вместо проклятия — у бойца нет маны и замедления.
        public const float WitherUnitDamage = Abilities.WitherDuration * 3f;

        public static float RallySpeedScale(bool rallied) { return rallied ? Abilities.RallySpeedScale : 1f; }
        public static float RallyAttackScale(bool rallied) { return rallied ? Abilities.RallyAttackScale : 1f; }

        /// Стая не больше своего размера: повторный призыв только доводит её до полной.
        public static bool CanSummon(int beastsAlive, int spellLevel) { return beastsAlive < Abilities.SwarmSize(spellLevel); }

        /// Стая появляется перед призывающим на дальности заклинания.
        public static V3 SummonPoint(V3 here, float yaw)
        {
            return here + UnitBrain.Rotate(new V3(0f, 0f, Abilities.RangeOf(AbilityKind.Summon)), yaw);
        }
    }
}
