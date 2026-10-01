// Сделки персонажа: лавка, кузня, стройка, наём, конюшня, обоз
// (перенос правил request_* из player.gd).
//
// Хост спрашивает здесь — и проводит сделку или получает отказ тем же
// русским текстом, что видел игрок в Godot-версии. Проверку «кто прислал и
// хост ли мы» делает Unity-слой; обстановку (у лавки ли, у кузни ли) — мир.
using System;

namespace DjvaGoda.CoreOld
{
    /// Снаряжение и расходники персонажа.
    public class Kit
    {
        public Faction Side;
        public bool IsLeader;
        public int GearTier;
        public int ArmorTier;
        public int PotionsHeal;
        public int PotionsMana;
        public int Arrows = Res.QuiverStart;

        /// Цена следующей ступени оружия: эльфам — в лавке за золото, прочим —
        /// в кузне за железо и уголь. Пусто — выше некуда.
        public int[] NextGearCost()
        {
            return Side == Faction.Elves ? Res.ElfGearCost(GearTier + 1) : Res.ForgeGearCost(GearTier + 1);
        }

        public int[] NextArmorCost() { return Res.ArmorCost(Side, ArmorTier + 1); }

        public int[] ArrowPrice() { return Side == Faction.Elves ? Res.ElfArrowCost : Res.ArrowCost; }

        /// Название ступени оружия у своей стороны.
        public string GearTitle(int tier) { return Weapons.GearName(tier, Side != Faction.Elves); }
    }

    /// Итог сделки: прошла или отказ со словами для игрока.
    public struct Deal
    {
        public readonly bool Ok;
        public readonly string Refusal;

        Deal(bool ok, string refusal)
        {
            Ok = ok;
            Refusal = refusal;
        }

        public static Deal Done() { return new Deal(true, null); }
        public static Deal No(string why) { return new Deal(false, why); }
        /// Молча нельзя (например, сумка полна) — без слов, как в Godot-версии.
        public static Deal Quiet() { return new Deal(false, null); }
    }

    public static class Deals
    {
        public const float ElfBuildReach = 40f;
        public const int MaxCaravans = 2;
        public const float RouteBound = 640f;

        /// Покупка в своей лавке. Лавка продаёт только товар своей стороны.
        public static Deal Trade(Kit kit, BodyState body, Wallet wallet, TradeItem item, bool atTrader)
        {
            if (!atTrader) return Deal.Quiet();
            if (Array.IndexOf(Res.Shop(kit.Side), item) < 0) return Deal.No("этого в вашей лавке не продают");
            switch (item)
            {
                case TradeItem.Bandages:
                    if (body.Bandages >= Res.BandageLimit || !wallet.Spend(Res.BandageCost)) return Deal.Quiet();
                    body.Bandages = Math.Min(Res.BandageLimit, body.Bandages + Res.BandagePack);
                    return Deal.Done();
                case TradeItem.Arrows:
                    if (kit.Arrows >= Res.QuiverLimit || !wallet.Spend(kit.ArrowPrice())) return Deal.Quiet();
                    kit.Arrows = Math.Min(Res.QuiverLimit, kit.Arrows + Res.ArrowPack);
                    return Deal.Done();
                case TradeItem.Gear:
                {
                    var cost = kit.NextGearCost();
                    if (cost.Length == 0 || !wallet.Spend(cost)) return Deal.Quiet();
                    kit.GearTier += 1;
                    return Deal.Done();
                }
                case TradeItem.Armor:
                {
                    var cost = kit.NextArmorCost();
                    if (cost.Length == 0) return Deal.Quiet();
                    if (!wallet.Spend(cost))
                        return Deal.No("не хватает на " + Res.ArmorName(kit.Side, kit.ArmorTier + 1)
                            + ": нужно " + Res.FormatCost(cost));
                    kit.ArmorTier += 1;
                    return Deal.Done();
                }
                case TradeItem.PotionHeal:
                    if (kit.PotionsHeal >= Res.PotionLimit || !wallet.Spend(Res.PotionHealCost)) return Deal.Quiet();
                    kit.PotionsHeal += 1;
                    return Deal.Done();
                case TradeItem.PotionMana:
                    if (kit.PotionsMana >= Res.PotionLimit || !wallet.Spend(Res.PotionManaCost)) return Deal.Quiet();
                    kit.PotionsMana += 1;
                    return Deal.Done();
            }
            return Deal.Quiet();
        }

        /// Закалка в кузне (GDD 9a): злодей и стража, у своей достроенной кузни.
        public static Deal ForgeGear(Kit kit, Wallet wallet, bool atForge)
        {
            if (kit.Side == Faction.Elves) return Deal.Quiet();
            if (!atForge) return Deal.No("закаляют в кузне: подойди к своей достроенной кузне");
            var cost = kit.NextGearCost();
            if (cost.Length == 0) return Deal.Quiet();
            if (!wallet.Spend(cost))
            {
                bool coal = Res.At(cost, ResourceKind.Coal) > wallet.GetAmount(ResourceKind.Coal);
                return Deal.No("не хватает на закалку: нужно " + Res.FormatCost(cost)
                    + (coal ? " — уголь возят обозом с угольной шахты" : ""));
            }
            kit.GearTier += 1;
            return Deal.Done();
        }

        /// Выпить зелье: лечения или маны.
        public static bool UsePotion(Kit kit, Vitals vitals, bool heal)
        {
            if (heal)
            {
                if (kit.PotionsHeal <= 0 || vitals.Health >= vitals.MaxHealth) return false;
                kit.PotionsHeal -= 1;
                vitals.Heal(Res.PotionHeal);
                return true;
            }
            if (kit.PotionsMana <= 0 || vitals.Mana >= vitals.MaxMana) return false;
            kit.PotionsMana -= 1;
            vitals.Mana = Math.Min(vitals.MaxMana, vitals.Mana + Res.PotionMana);
            return true;
        }

        /// Поставить постройку. spotOk — место годное (проверку места делает мир).
        public static Deal Build(Kit kit, Wallet wallet, BuildingKind kind, bool spotOk,
            float distanceToPoint, int elfHouses, int elfHouseLimit)
        {
            if (!Factions.MayBuild(kit.Side, kind, kit.IsLeader))
                return Deal.No(Res.BuildingNames[(int)kind] + " вашей стороне не строить");
            if (Res.IsElfHouse(kind) && distanceToPoint > ElfBuildReach)
                return Deal.No("дом ставят рядом с собой: не дальше " + (int)ElfBuildReach + " м");
            if (Res.IsElfHouse(kind) && elfHouses >= elfHouseLimit)
                return Deal.No("домов уже " + elfHouses + " из " + elfHouseLimit + ": больше эльфы не держат");
            var cost = Res.BuildingCost(kind);
            if (!wallet.CanAfford(cost))
                return Deal.No("не хватает ресурсов на " + Res.BuildingNames[(int)kind] + " — нужно "
                    + Res.FormatCost(cost) + Res.ShortfallHint(cost, wallet));
            if (!spotOk) return Deal.No("здесь строить нельзя: " + Res.BuildingNames[(int)kind] + " не встанет на этом месте");
            wallet.Spend(cost);
            return Deal.Done();
        }

        /// Укрепить постройку, у которой стоишь, на ступень.
        public static Deal Fortify(Kit kit, Wallet wallet, BuildingState building)
        {
            if (building == null) return Deal.No("укрепляют у своей достроенной постройки");
            if (!Factions.MayBuild(kit.Side, building.Kind, kit.IsLeader))
                return Deal.No("укреплять постройки вашей стороне нельзя");
            var cost = building.UpgradeCost();
            if (cost.Length == 0) return Deal.No("крепче этой постройки уже не сделать");
            if (!wallet.Spend(cost)) return Deal.No("не хватает на укрепление: нужно " + Res.FormatCost(cost));
            building.ApplyUpgrade();
            return Deal.Done();
        }

        public static Deal HireLabourer(Kit kit, Wallet wallet, int crew)
        {
            if (!Factions.CanBuild(kit.Side) && !kit.IsLeader) return Deal.No("батраки есть только у злодея");
            if (crew >= Res.LabourerLimit) return Deal.No("больше батраков не прокормить: потолок " + Res.LabourerLimit);
            if (!wallet.Spend(Res.LabourerCost))
                return Deal.No("не хватает на батрака — нужно " + Res.FormatCost(Res.LabourerCost)
                    + Res.ShortfallHint(Res.LabourerCost, wallet));
            return Deal.Done();
        }

        public static Deal HireHorse(Wallet wallet, bool atStable, bool hasStable)
        {
            if (!atStable)
                return Deal.No(hasStable ? "подойди к конюшне — лошадей берут там"
                    : "лошадей брать негде: сначала построй конюшню");
            if (wallet.Horses >= Res.HorseLimit) return Deal.No("конюшня полна: больше " + Res.HorseLimit + " лошадей не держат");
            if (!wallet.Spend(Res.HorseCost))
                return Deal.No("не хватает на лошадь — нужно " + Res.FormatCost(Res.HorseCost)
                    + Res.ShortfallHint(Res.HorseCost, wallet));
            wallet.Horses += 1;
            return Deal.Done();
        }

        /// Сколько людей сторона держит под ружьём: база плюс дома, но не выше потолка.
        public static int SquadCapacity(int housesReady)
        {
            return Math.Min(Res.SquadLimit, Res.SquadBase + Res.HouseSlots * housesReady);
        }

        public static Deal TrainUnit(Wallet wallet, bool archer, bool atBarracks, bool hasBarracks, int squad, int room)
        {
            var kind = archer ? BuildingKind.ArcherBarracks : BuildingKind.SwordBarracks;
            if (!atBarracks)
                return Deal.No(hasBarracks ? "подойди к постройке «" + Res.BuildingNames[(int)kind] + "» — нанимают там"
                    : "нанимать негде: сначала построй " + Res.BuildingNames[(int)kind]);
            if (squad >= room)
                return Deal.No("отряд полон: " + squad + " из " + room + " — построй дом дружины, он даёт ещё " + Res.HouseSlots);
            var cost = archer ? Res.ArcherCost : Res.UnitCost;
            if (!wallet.Spend(cost))
                return Deal.No("не хватает ресурсов на " + (archer ? "лучника" : "мечника") + " — нужно "
                    + Res.FormatCost(cost) + Res.ShortfallHint(cost, wallet));
            return Deal.Done();
        }

        /// Отправить обоз: нужен склад, свободные лошади, точки в пределах карты.
        public static Deal SendCaravan(Wallet wallet, bool hasStorage, int caravansOut, V3[] points)
        {
            if (!hasStorage) return Deal.No("каравану некуда возвращаться: сначала дострой склад");
            if (caravansOut >= MaxCaravans) return Deal.No("больше караванов в пути держать нельзя, дождись возврата");
            foreach (var point in points)
                if (Math.Abs(point.X) > RouteBound || Math.Abs(point.Z) > RouteBound)
                    return Deal.No("точка маршрута вне карты, караван не отправлен");
            if (wallet.HorsesFree <= 0) return Deal.No("некого запрягать: свободных лошадей нет, купи в конюшне");
            return Deal.Done();
        }
    }
}
