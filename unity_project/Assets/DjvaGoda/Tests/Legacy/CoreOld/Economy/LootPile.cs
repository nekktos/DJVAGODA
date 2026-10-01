// Куча на земле: груз разбитого обоза, всё с тела павшего (перенос loot.gd).
//
// Подобрать может любой (ответ автора: «при смерти падает всё из
// инвентаря»). Снаряжение берётся, только если лучше своего; расходники — до
// своих потолков. Подобранная куча исчезает целиком — как в Godot-версии.
using System;
using System.Collections.Generic;

namespace DjvaGoda.CoreOld
{
    public class LootPile
    {
        public const float PickupRange = 3.5f;
        public const float Lifetime = 240f;

        public int[] Contents = Res.Empty();
        public int Gear;
        public int Armor;
        public int Bandages;
        public int PotionsHeal;
        public int PotionsMana;
        public int Arrows;
        public bool Taken;

        /// Всё с тела павшего: несённое, снаряжение, расходники.
        public static LootPile FromBody(int[] carried, Kit kit, BodyState body)
        {
            return new LootPile
            {
                Contents = Res.Fit(carried),
                Gear = kit.GearTier,
                Armor = kit.ArmorTier,
                Bandages = body.Bandages,
                PotionsHeal = kit.PotionsHeal,
                PotionsMana = kit.PotionsMana,
                Arrows = kit.Arrows,
            };
        }

        /// Подобрать. Возвращает сколько единиц взято; 0 и без снаряжения — не взято.
        public int Collect(Wallet wallet, Kit kit, BodyState body)
        {
            if (Taken) return 0;
            int total = 0;
            for (int i = 0; i < Res.Count; i++) total += wallet.Add(i, Contents[i]);
            bool tookGear = false;
            if (Gear > kit.GearTier)
            {
                kit.GearTier = Gear;
                tookGear = true;
            }
            if (Armor > kit.ArmorTier)
            {
                kit.ArmorTier = Armor;
                tookGear = true;
            }
            total += Move(ref Bandages, ref body.Bandages, Res.BandageLimit);
            total += Move(ref PotionsHeal, ref kit.PotionsHeal, Res.PotionLimit);
            total += Move(ref PotionsMana, ref kit.PotionsMana, Res.PotionLimit);
            total += Move(ref Arrows, ref kit.Arrows, Res.QuiverLimit);
            if (total <= 0 && !tookGear) return 0;
            Taken = true;
            return total;
        }

        static int Move(ref int from, ref int to, int limit)
        {
            int took = Math.Max(0, Math.Min(from, limit - to));
            to += took;
            from -= took;
            return took;
        }

        public string Summary()
        {
            var parts = new List<string>();
            for (int i = 0; i < Res.Count; i++)
                if (Contents[i] > 0) parts.Add(Res.Short[i] + " " + Contents[i]);
            if (Gear > 0) parts.Add("оружие " + Gear);
            if (Armor > 0) parts.Add("доспех " + Armor);
            if (Bandages > 0) parts.Add("бинтов " + Bandages);
            if (PotionsHeal + PotionsMana > 0) parts.Add("зелий " + (PotionsHeal + PotionsMana));
            if (Arrows > 0) parts.Add("стрел " + Arrows);
            return string.Join(", ", parts.ToArray());
        }
    }
}
