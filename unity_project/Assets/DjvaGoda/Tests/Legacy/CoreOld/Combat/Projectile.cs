// Стрела, болт, огненный шар в полёте (перенос projectile.gd) и прицел игрока
// (player.gd::aim_direction).
//
// Полёт считает хост: прямой отрезок за кадр, лёгкая дуга (4 м/с² вниз —
// чтобы стрельба читалась), шесть секунд жизни. Луч по отрезку и зоны
// попадания — Unity-слой. Взрыв шара бьёт каждую цель один раз — по её
// ближайшей к центру зоне, с затуханием к краю.
using System;
using System.Collections.Generic;

namespace DjvaGoda.CoreOld
{
    public class ProjectileFlight
    {
        public const float Drop = 4f;

        public readonly WeaponKind Kind;
        public V3 Position;
        public V3 Velocity;
        public float Life;

        public ProjectileFlight(WeaponKind kind, V3 origin, V3 direction)
        {
            Kind = kind;
            Position = origin;
            Velocity = direction.Normalized() * Weapons.ProjectileSpeed(kind);
        }

        public bool Expired { get { return Life > Weapons.ProjectileLifetime; } }

        /// Отрезок этого кадра: откуда и куда. Луч по нему пускает Unity-слой;
        /// промах — Advance(to).
        public V3 Segment(float delta, out V3 to)
        {
            Life += delta;
            to = Position + Velocity * delta;
            Velocity = new V3(Velocity.X, Velocity.Y - Drop * delta, Velocity.Z);
            return Position;
        }

        public void Advance(V3 to) { Position = to; }

        /// Урон прямого попадания: оружие × зона × закалка × пробой строя (арбалет).
        public static float HitDamage(WeaponKind kind, string zone, int gearTier, float targetDefensiveScale)
        {
            return Weapons.Damage[(int)kind] * UnitStats.ZoneMultiplier(zone) * Weapons.GearDamage(gearTier)
                * DamageRules.PierceScale(kind, targetDefensiveScale);
        }

        /// Взрыв: по каждой цели — её ближайшая зона и урон с затуханием.
        /// Меньше полуединицы — не в счёт (задело краем).
        public static Dictionary<int, KeyValuePair<ZoneHit, float>> Blast(V3 point, IEnumerable<ZoneHit> zones, int gearTier)
        {
            var nearest = new Dictionary<int, ZoneHit>();
            foreach (var zone in zones)
            {
                ZoneHit prev;
                if (!nearest.TryGetValue(zone.Target, out prev) || zone.Centre.Distance(point) < prev.Centre.Distance(point))
                    nearest[zone.Target] = zone;
            }
            var result = new Dictionary<int, KeyValuePair<ZoneHit, float>>();
            foreach (var pair in nearest)
            {
                float damage = DamageRules.Blast(pair.Value.Centre.Distance(point), pair.Value.Zone, gearTier);
                if (damage > 0.5f) result[pair.Key] = new KeyValuePair<ZoneHit, float>(pair.Value, damage);
            }
            return result;
        }
    }

    public static class Aim
    {
        public const float EyeHeight = 1.5f;
        public const float Range = Movement.AimRange;

        public static V3 Origin(V3 feet) { return feet + new V3(0f, EyeHeight, 0f); }

        /// Прямо по взгляду: поворот и наклон головы («вперёд» — −Z).
        public static V3 Straight(float yaw, float pitch)
        {
            var look = new V3(0f, (float)Math.Sin(pitch), -(float)Math.Cos(pitch));
            return UnitBrain.Rotate(look, yaw);
        }

        /// Куда летит выстрел: из глаз персонажа в точку, куда смотрит камера
        /// (точка попадания луча камеры или конец дальности). Камера из-за плеча
        /// видит не то, что глаза, — поэтому точка, а не направление камеры.
        /// Точка вплотную (меньше полуметра) — прямо по взгляду.
        public static V3 Direction(V3 feet, float yaw, float pitch, V3 cameraTarget)
        {
            var dir = cameraTarget - Origin(feet);
            if (dir.Length() < 0.5f) return Straight(yaw, pitch);
            return dir.Normalized();
        }
    }
}
