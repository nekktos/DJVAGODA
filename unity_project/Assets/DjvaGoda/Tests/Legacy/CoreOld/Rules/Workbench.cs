// Верстак-медпункт на перекрёстке, трофеи, перевязка, опыт за добычу
// (перенос player.gd: request_prosthetic, request_eye, request_splint,
// request_wheelchair, _update_bandage, award_xp_for_resources).
//
// Ранения в игре не лечатся смертью (GDD 4.1): встать можно, а руку вернёт
// только протез. Деревянный ставят где угодно, кованый и мастерский — у
// верстака; некротический — у верстака за десять чужих рук или ног того же
// вида: трофеи с врагов, которым их оторвал сам игрок.
using System;

namespace DjvaGoda.CoreOld
{
    public enum TrophyKind { Arms, Legs, Eyes }

    public static class Workbench
    {
        public static readonly string[] TrophyNames = { "рук", "ног", "глаз" };

        public static TrophyKind TrophyOf(Limb limb)
        {
            return limb == Limb.ArmL || limb == Limb.ArmR ? TrophyKind.Arms : TrophyKind.Legs;
        }

        /// Протез на все оторванные конечности, где он другой ступени.
        public static Deal Prosthetic(int tier, BodyState body, int[] trophies, Wallet wallet, bool atBench)
        {
            bool necrotic = tier == BodyState.NecroticTier;
            if (!necrotic && Res.ProstheticCost(tier).Length == 0) return Deal.Quiet();
            if (tier > 1 && !atBench) return Deal.Quiet();
            var targets = new System.Collections.Generic.List<Limb>();
            for (int limb = 0; limb < 4; limb++)
                if (body.IsSevered((Limb)limb) && body.Tier((Limb)limb) != tier) targets.Add((Limb)limb);
            if (targets.Count == 0) return Deal.Quiet();

            if (necrotic)
            {
                // Цена — за КАЖДУЮ конечность из запаса своего вида: две ноги — двадцать ног.
                var need = new int[3];
                foreach (var limb in targets) need[(int)TrophyOf(limb)] += BodyState.NecroticPrice;
                foreach (var limb in targets)
                {
                    int kind = (int)TrophyOf(limb);
                    if (trophies[kind] < need[kind])
                        return Deal.No("на некротический протез нужно " + need[kind] + " чужих " + TrophyNames[kind]
                            + ", есть " + trophies[kind]);
                }
                foreach (var limb in targets)
                {
                    trophies[(int)TrophyOf(limb)] -= BodyState.NecroticPrice;
                    body.GrantProsthetic(limb, tier);
                }
                return Deal.Done();
            }
            if (!wallet.Spend(Res.ProstheticCost(tier))) return Deal.No("не хватает ресурсов на протез");
            foreach (var limb in targets) body.GrantProsthetic(limb, tier);
            return Deal.Done();
        }

        /// Некротический глаз — только у верстака, за десять чужих глаз.
        public static Deal Eye(BodyState body, int[] trophies, bool atBench)
        {
            if (!atBench) return Deal.No("глаз вставляют только у верстака");
            if (body.EyesMissing() <= 0) return Deal.Quiet();
            int eyes = trophies[(int)TrophyKind.Eyes];
            if (eyes < BodyState.NecroticPrice)
                return Deal.No("на некротический глаз нужно " + BodyState.NecroticPrice + " чужих глаз, есть " + eyes);
            if (!body.GrantEye()) return Deal.Quiet();
            trophies[(int)TrophyKind.Eyes] -= BodyState.NecroticPrice;
            return Deal.Done();
        }

        /// Лубок: вправить одну перебитую (не оторванную) кость — в медпункте.
        public static Deal Splint(BodyState body, Wallet wallet, bool atBench)
        {
            if (!atBench) return Deal.No("вправить кость можно только в медпункте на перекрёстке");
            int hurt = -1;
            for (int limb = 0; limb < 4 && hurt < 0; limb++)
                if (body.IsCrippled((Limb)limb) && !body.IsSevered((Limb)limb)) hurt = limb;
            if (hurt < 0) return Deal.No("нечего вправлять: перебитых костей нет");
            if (!wallet.Spend(Res.SplintCost))
                return Deal.No("не хватает на лубок — нужно " + Res.FormatCost(Res.SplintCost) + Res.ShortfallHint(Res.SplintCost, wallet));
            body.HealLimb((Limb)hurt);
            return Deal.Done();
        }

        /// Коляска — у верстака, и только тому, кто иначе ползёт.
        public static Deal Wheelchair(BodyState body, bool on, bool atBench)
        {
            if (!atBench) return Deal.Quiet();
            return body.SetWheelchair(on) ? Deal.Done() : Deal.Quiet();
        }
    }

    /// Перевязка: держать клавишу три секунды, стоя на месте, пока течёт кровь.
    public class Bandaging
    {
        public const float StillSpeed = 0.3f;
        public float Progress { get; private set; }

        /// true — перевязка готова: хост тратит бинт (BodyState.ApplyBandage).
        public bool Tick(float delta, bool bleeding, bool holding, float flatSpeed)
        {
            if (!bleeding || !holding || flatSpeed >= StillSpeed)
            {
                Progress = 0f;
                return false;
            }
            Progress += delta;
            if (Progress < BodyState.BandageTime) return false;
            Progress = 0f;
            return true;
        }
    }

    /// Опыт за донесённую добычу: очко за каждые четыре единицы, остаток копится.
    public class ResourceXp
    {
        int _tail;

        public int Award(int units)
        {
            if (units <= 0) return 0;
            _tail += units;
            int points = _tail / Progression.ResourcePerPoint;
            _tail -= points * Progression.ResourcePerPoint;
            return points;
        }
    }
}
