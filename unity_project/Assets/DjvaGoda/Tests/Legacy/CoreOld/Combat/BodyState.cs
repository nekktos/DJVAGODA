// Тело: ранения, протезы, кровотечение (перенос body.gd, GDD раздел 4).
//
// Считает ТОЛЬКО хост; Unity-слой реплицирует поля и рисует последствия.
// Исход ранения решает ОРУЖИЕ: рубящее отрывает, прочее калечит (GDD 4.0).
using System;
using System.Collections.Generic;

namespace DjvaGoda.CoreOld
{
    public enum Limb { ArmL, ArmR, LegL, LegR }

    public class BodyState
    {
        public static readonly string[] LimbKeys = { "arm_l", "arm_r", "leg_l", "leg_r" };
        public static readonly string[] LimbNames = { "левая рука", "правая рука", "левая нога", "правая нога" };

        public const float LimbDurability = 45f;
        public const float EyeThreshold = 40f;
        public const float BleedPerSecond = 3f;
        public const float BandageTime = 3f;
        public const int StartBandages = 3;
        public const float CrawlSpeedOne = 1.4f;
        public const float CrawlSpeedBoth = 0.8f;
        public const float WheelchairSpeed = 4.5f;

        /// Качество протезов: 0 — нет; 1 деревянный … 3 мастерский (лучше
        /// живого); 4 некротический — лучший, из десяти чужих конечностей.
        public static readonly string[] TierNames = { "нет", "деревянный", "кованый", "мастерский", "некротический" };
        static readonly float[] TierSpeed = { 0f, 0.30f, 1f, 1.25f, 1.45f };
        static readonly float[] TierJump = { 0f, 0.55f, 1f, 1.35f, 1.50f };
        static readonly float[] TierChafeDamage = { 0f, 1.5f, 0f, 0f, 1f };
        static readonly float[] TierAttackSpeed = { 1f, 1f, 1f, 0.75f, 0.62f };
        public const float ChafeInterval = 4f;
        public const int NecroticTier = 4;
        public const int NecroticPrice = 10;

        public int SeveredMask;
        public int CrippledMask;
        public readonly int[] Prosthetics = new int[4];
        public int EyesLost;
        public int EyeImplants;
        public bool Bleeding;
        public int Bandages = StartBandages;
        public bool InWheelchair;

        readonly float[] _limbDamage = new float[4];
        float _headDamage;
        float _chafeTimer;

        public bool IsSevered(Limb limb) { return (SeveredMask & (1 << (int)limb)) != 0; }
        public bool IsCrippled(Limb limb) { return (CrippledMask & (1 << (int)limb)) != 0; }
        public bool IsDisabled(Limb limb) { return IsSevered(limb) || IsCrippled(limb); }
        public int Tier(Limb limb) { return Prosthetics[(int)limb]; }

        float LimbFactor(Limb limb, float[] table)
        {
            if (IsSevered(limb)) return table[Res.Clamp(Tier(limb), 0, table.Length - 1)];
            if (IsCrippled(limb)) return 0f;
            return 1f;
        }

        public bool IsCrawling()
        {
            if (InWheelchair) return false;
            return LimbFactor(Limb.LegL, TierSpeed) <= 0f || LimbFactor(Limb.LegR, TierSpeed) <= 0f;
        }

        public float MoveSpeed(float baseSpeed)
        {
            if (InWheelchair) return WheelchairSpeed;
            float left = LimbFactor(Limb.LegL, TierSpeed);
            float right = LimbFactor(Limb.LegR, TierSpeed);
            int lost = (left <= 0f ? 1 : 0) + (right <= 0f ? 1 : 0);
            if (lost == 2) return CrawlSpeedBoth;
            if (lost == 1) return CrawlSpeedOne;
            return baseSpeed * (left + right) * 0.5f;
        }

        public float JumpVelocity(float baseVelocity)
        {
            if (InWheelchair || IsCrawling()) return 0f;
            return baseVelocity * Math.Min(LimbFactor(Limb.LegL, TierJump), LimbFactor(Limb.LegR, TierJump));
        }

        public bool CanAttackMelee() { return ArmUsable(Limb.ArmL, 1) || ArmUsable(Limb.ArmR, 1); }

        /// Лук и заклинания требуют полноценной руки: деревянный протез не годится.
        public bool CanAttackRanged() { return ArmUsable(Limb.ArmL, 2) || ArmUsable(Limb.ArmR, 2); }

        bool ArmUsable(Limb limb, int minTier)
        {
            if (IsCrippled(limb) && !IsSevered(limb)) return false;
            if (!IsSevered(limb)) return true;
            return Tier(limb) >= minTier;
        }

        public float AttackSpeedScale()
        {
            float best = 1f;
            foreach (var limb in new[] { Limb.ArmL, Limb.ArmR })
                if (IsSevered(limb)) best = Math.Min(best, TierAttackSpeed[Res.Clamp(Tier(limb), 0, TierNames.Length - 1)]);
            return best;
        }

        public float Blindness() { return Math.Min(1f, Math.Max(0, EyesLost - EyeImplants) * 0.5f); }
        public int EyesMissing() { return Math.Max(0, EyesLost - EyeImplants); }

        public bool GrantEye()
        {
            if (EyesMissing() <= 0) return false;
            EyeImplants += 1;
            return true;
        }

        /// Попадание в зону. Здоровье снимается отдельно — здесь судьба конечности.
        /// weapon == null — «неизвестно чем»: калечит (отрыв требует рубящего).
        public void RegisterHit(string zone, float amount, WeaponKind? weapon)
        {
            if (amount <= 0f) return;
            if (zone == "head")
            {
                _headDamage += amount;
                while (_headDamage >= EyeThreshold && EyesLost < 2)
                {
                    _headDamage -= EyeThreshold;
                    EyesLost += 1;
                }
                return;
            }
            int index = Array.IndexOf(LimbKeys, zone);
            if (index < 0) return;
            var limb = (Limb)index;
            if (IsSevered(limb)) return;
            _limbDamage[index] += amount;
            if (_limbDamage[index] < LimbDurability) return;

            bool severs = weapon.HasValue && Weapons.Severs(weapon.Value);
            if (!severs)
            {
                // Покалеченная — на один рубящий удар от того, чтобы её лишиться.
                _limbDamage[index] = LimbDurability;
                CrippledMask |= 1 << index;
                return;
            }
            SeveredMask |= 1 << index;
            Prosthetics[index] = 0;
            Bleeding = true;
        }

        /// Вылечить перебитую. Оторванное не лечит ничто — на то и протезы.
        public bool HealLimb(Limb limb)
        {
            if (!IsCrippled(limb) || IsSevered(limb)) return false;
            CrippledMask &= ~(1 << (int)limb);
            _limbDamage[(int)limb] = 0f;
            return true;
        }

        public void StartBleeding() { Bleeding = true; }

        /// Такт хоста: сколько здоровья снять кровотечением и натиранием протеза.
        public float Tick(float delta)
        {
            float damage = 0f;
            if (Bleeding) damage += BleedPerSecond * delta;
            float chafe = 0f;
            for (int i = 0; i < 4; i++)
                if (IsSevered((Limb)i)) chafe += TierChafeDamage[Res.Clamp(Prosthetics[i], 0, TierNames.Length - 1)];
            if (chafe <= 0f)
            {
                _chafeTimer = 0f;
                return damage;
            }
            _chafeTimer += delta;
            if (_chafeTimer >= ChafeInterval)
            {
                _chafeTimer = 0f;
                damage += chafe;
            }
            return damage;
        }

        public bool ApplyBandage()
        {
            if (!Bleeding || Bandages <= 0) return false;
            Bandages -= 1;
            Bleeding = false;
            return true;
        }

        public bool GrantProsthetic(Limb limb, int tier)
        {
            if (!IsSevered(limb)) return false;
            tier = Res.Clamp(tier, 1, TierNames.Length - 1);
            if (Tier(limb) == tier) return false;
            Prosthetics[(int)limb] = tier;
            return true;
        }

        public bool SetWheelchair(bool on)
        {
            if (on && !IsCrawling()) return false;
            if (InWheelchair == on) return false;
            InWheelchair = on;
            return true;
        }

        public void Reset()
        {
            SeveredMask = 0;
            CrippledMask = 0;
            for (int i = 0; i < 4; i++)
            {
                Prosthetics[i] = 0;
                _limbDamage[i] = 0f;
            }
            EyesLost = 0;
            EyeImplants = 0;
            Bleeding = false;
            InWheelchair = false;
            Bandages = StartBandages;
            _headDamage = 0f;
            _chafeTimer = 0f;
        }

        public string Summary()
        {
            if (SeveredMask == 0 && CrippledMask == 0 && EyesLost == 0 && !InWheelchair) return "цел";
            var parts = new List<string>();
            for (int i = 0; i < 4; i++)
            {
                var limb = (Limb)i;
                if (IsSevered(limb))
                    parts.Add(LimbNames[i] + ": " + (Prosthetics[i] > 0 ? TierNames[Prosthetics[i]] : "оторвана"));
                else if (IsCrippled(limb))
                    parts.Add(LimbNames[i] + ": перебита");
            }
            if (EyesMissing() > 0) parts.Add("глаз потеряно: " + EyesMissing());
            if (EyeImplants > 0) parts.Add("некротических глаз: " + EyeImplants);
            if (InWheelchair) parts.Add("в коляске");
            if (Bleeding) parts.Add("КРОВОТЕЧЕНИЕ");
            return string.Join(", ", parts.ToArray());
        }
    }
}
