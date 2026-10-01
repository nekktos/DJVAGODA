// Герой стороны под ИИ (перенос ai/hero.gd): персонаж, который играет за
// сторону, пока на ней нет живого игрока.
//
// Мозг решает ЧТО делать; КАК идти (путь по навигации, обход построек) и
// чисто ли летит заклинание (луч физики) — Unity-слой. Порядок забот — как в
// Godot-версии: зелье при ранении; враг рядом; враг у своего хозяйства или
// обоза; без врагов — микро-шахта (злодей без склада), дом и лес (эльфы),
// кузня и лавка; иначе — при обозе или при якоре отряда. Почему так — там же.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum HeroTask { Fight, Defend, Dig, BuildElfHouse, ChopTree, ForgeGear, BuyArmor, BuyPotion, Follow }

    /// Жила, камень или дерево, которое герой может бить молотом.
    public struct Vein
    {
        public readonly V3 At;
        /// Радиус тела: к большой глыбе нельзя подойти на 2.4 м от центра.
        public readonly float Radius;

        public Vein(V3 at, float radius)
        {
            At = at;
            Radius = radius > 0f ? radius : 2f;
        }
    }

    public class HeroView
    {
        public Faction Side;
        public V3 At;
        public float Health = Vitals.BaseHealth;
        public float MaxHealth = Vitals.BaseHealth;
        public int PotionsHeal;
        public int[] Stock = Res.Empty();
        public WeaponKind Weapon = WeaponKind.Sword;
        /// Живые персонажи и бойцы других сторон поблизости.
        public List<SidedPoint> Others = new List<SidedPoint>();
        /// Своё хозяйство: постройки и батраки.
        public List<V3> Posts = new List<V3>();
        /// Свой обоз в пути — герой его охраняет.
        public V3? OwnCart;
        public V3? WarbandAnchor;
        /// Злодей: есть ли склад; пока нет — копать микро-шахту.
        public bool HasStorage = true;
        public List<Vein> MicroVeins = new List<Vein>();
        /// Эльфы: дома и их потолок, лес у спавна, можно ли ставить дом в точке.
        public int ElfHouses;
        public int ElfHouseLimit;
        public List<Vein> Trees = new List<Vein>();
        public Func<V3, bool> ElfSpotBuildable;
        /// Кузня стороны, если построена, и стоит ли герой у неё.
        public V3? Forge;
        public bool AtForge;
        public int[] NextGearCost = new int[0];
        public int[] NextArmorCost = new int[0];
        public V3 Trader;
        public bool AtTrader;
    }

    public class HeroDecision
    {
        public HeroTask Task;
        /// Куда идти; Walk — идти ли вообще (иначе стоять и действовать).
        public V3 Goal;
        public bool Walk;
        public V3? Target;
        public bool Attack;
        /// Если стреляет заклинанием — Unity обязан проверить чистый бросок лучом.
        public bool NeedsClearThrow;
        public WeaponKind? Weapon;
        public AbilityKind? Spell;
        public bool UsePotion;
        /// Действие у постройки или лавки: ковать, купить, поставить дом.
        public bool Interact;
        public V3? BuildAt;
    }

    public static class HeroBrain
    {
        public static HeroDecision Decide(HeroView view)
        {
            var decision = new HeroDecision { Goal = view.At };
            decision.UsePotion = view.PotionsHeal > 0 && view.Health < view.MaxHealth * AiStats.PotionAt;
            var enemies = EnemiesNear(view.Side, view.Others, view.At);
            V3? target = Closest(view.At, enemies);
            bool defending = false;
            if (!target.HasValue)
            {
                target = HomeThreat(view);
                defending = target.HasValue;
            }

            if (!target.HasValue)
            {
                if (MicroVein(view, decision)) return decision;
                if (view.Side == Faction.Elves && ElfBuild(view, decision)) return decision;
                if (GearErrand(view, decision)) return decision;
            }

            var anchor = view.OwnCart ?? view.WarbandAnchor;
            V3 goal;
            if (target.HasValue) goal = target.Value;
            else goal = anchor ?? Factions.Spawn[(int)view.Side];

            // Поводок: за целью, уводящей от обоза или отряда, не гнаться. Рядом —
            // драться (иначе убегает от врага, который его бьёт); свой дом — защищать.
            if (target.HasValue && anchor.HasValue)
            {
                bool close = view.At.FlatDistance(target.Value) <= AiStats.CloseFight;
                if (!close && !defending && anchor.Value.FlatDistance(goal) > AiStats.HeroLeash)
                    goal = anchor.Value;
            }
            decision.Task = target.HasValue ? (defending ? HeroTask.Defend : HeroTask.Fight) : HeroTask.Follow;
            decision.Goal = goal;
            decision.Walk = view.At.FlatDistance(goal) > (target.HasValue ? AiStats.MeleeReach : AiStats.AtAnchor);
            if (!target.HasValue) return decision;

            decision.Target = target;
            float gap = view.At.FlatDistance(target.Value);
            var weapon = ChooseWeapon(view.Side, gap) ?? view.Weapon;
            decision.Weapon = weapon;
            bool melee = Weapons.IsMelee(weapon);
            float reach = melee ? AiStats.MeleeReach : AiStats.Sight;
            // Огненный шар вплотную взорвался бы на самом герое. Только шар: в
            // Godot-версии запрет стоял на любом дальнобойном, и эльф с луком не
            // стрелял бы в упор — там это не всплывало, эльф-ИИ держит меч.
            if (weapon == WeaponKind.Spell && gap <= AiStats.SafeSpellGap) reach = 0f;
            decision.Attack = gap <= reach && !OwnCartInSwing(view);
            decision.NeedsClearThrow = decision.Attack && !melee;
            decision.Spell = ChooseSpell(view, enemies, target.Value);
            return decision;
        }

        /// Вплотную — молот, издали — огненный шар; если стороне можно.
        public static WeaponKind? ChooseWeapon(Faction side, float gap)
        {
            var wanted = gap <= AiStats.SafeSpellGap ? WeaponKind.Hammer : WeaponKind.Spell;
            return Factions.AllowsWeapon(side, wanted) ? wanted : (WeaponKind?)null;
        }

        /// Паралич — когда плохо (половина здоровья и цель в досягаемости);
        /// увядание — по кучке из трёх врагов.
        public static AbilityKind? ChooseSpell(HeroView view, List<V3> enemies, V3 target)
        {
            float share = view.Health / Math.Max(1f, Vitals.BaseHealth);
            float gap = view.At.FlatDistance(target);
            if (share <= AiStats.PanicFraction && gap <= Abilities.RangeOf(AbilityKind.Paralysis)
                && Factions.AllowsAbility(view.Side, AbilityKind.Paralysis))
                return AbilityKind.Paralysis;
            if (ClusterSize(enemies, target) >= AiStats.ClusterSize && gap <= Abilities.RangeOf(AbilityKind.Wither)
                && Factions.AllowsAbility(view.Side, AbilityKind.Wither))
                return AbilityKind.Wither;
            return null;
        }

        static int ClusterSize(List<V3> enemies, V3 point)
        {
            int count = 0;
            foreach (var enemy in enemies)
                if (point.FlatDistance(enemy) <= AiStats.ClusterRadius) count++;
            return count;
        }

        public static List<V3> EnemiesNear(Faction side, List<SidedPoint> others, V3 point)
        {
            var found = new List<V3>();
            foreach (var other in others)
                if (Factions.Hostile((int)side, other.Side) && point.FlatDistance(other.At) <= AiStats.Sight)
                    found.Add(other.At);
            return found;
        }

        static V3? Closest(V3 point, List<V3> points)
        {
            V3? best = null;
            float closest = float.MaxValue;
            foreach (var at in points)
            {
                float gap = point.FlatDistance(at);
                if (gap < closest)
                {
                    closest = gap;
                    best = at;
                }
            }
            return best;
        }

        /// Враг у своей постройки, батрака или обоза — ближайший к герою.
        public static V3? HomeThreat(HeroView view)
        {
            var posts = new List<V3>(view.Posts);
            if (view.OwnCart.HasValue) posts.Add(view.OwnCart.Value);
            V3? best = null;
            float bestGap = float.MaxValue;
            foreach (var post in posts)
                foreach (var enemy in EnemiesNear(view.Side, view.Others, post))
                {
                    float gap = view.At.FlatDistance(enemy);
                    if (gap < bestGap)
                    {
                        bestGap = gap;
                        best = enemy;
                    }
                }
            return best;
        }

        /// Не махать молотом у своего обоза: удар по площади задел бы лошадей.
        static bool OwnCartInSwing(HeroView view)
        {
            return view.OwnCart.HasValue && view.At.FlatDistance(view.OwnCart.Value) <= AiStats.MeleeReach + 3f;
        }

        /// Злодей без склада копает микро-шахту за фортом: камень и золото на склад.
        static bool MicroVein(HeroView view, HeroDecision decision)
        {
            if (view.Side != Faction.Villain || view.HasStorage) return false;
            Vein? best = null;
            float bestGap = float.MaxValue;
            foreach (var vein in view.MicroVeins)
            {
                if (vein.At.FlatDistance(MapLayout.MicroMine) > AiStats.MicroRadius) continue;
                float gap = view.At.FlatDistance(vein.At);
                if (gap < bestGap)
                {
                    bestGap = gap;
                    best = vein;
                }
            }
            if (!best.HasValue) return false;
            Dig(view, best.Value, decision, HeroTask.Dig);
            return true;
        }

        static void Dig(HeroView view, Vein vein, HeroDecision decision, HeroTask task)
        {
            bool close = view.At.FlatDistance(vein.At) <= AiStats.MineReach + vein.Radius;
            decision.Task = task;
            decision.Goal = vein.At;
            decision.Target = vein.At;
            decision.Walk = !close;
            decision.Attack = close;
            if (close) decision.Weapon = WeaponKind.Hammer;
        }

        /// Эльфы: дом, если по карману и не упёрлись в потолок; иначе — рубить лес у спавна.
        static bool ElfBuild(HeroView view, HeroDecision decision)
        {
            if (view.ElfHouses >= view.ElfHouseLimit) return false;
            var cost = Res.BuildingCost(BuildingKind.ElfHouse);
            if (Res.CanAfford(view.Stock, cost))
            {
                var spot = ElfSpot(view);
                if (!spot.HasValue) return false;
                decision.Task = HeroTask.BuildElfHouse;
                decision.Goal = spot.Value;
                if (view.At.FlatDistance(spot.Value) > Deals.ElfBuildReach - 6f)
                {
                    decision.Walk = true;
                    return true;
                }
                decision.Interact = true;
                decision.BuildAt = spot;
                return true;
            }
            Vein? tree = null;
            float bestGap = float.MaxValue;
            var centre = Factions.Spawn[(int)Faction.Elves];
            foreach (var candidate in view.Trees)
            {
                if (candidate.At.FlatDistance(centre) > AiStats.ElfWoods) continue;
                float gap = view.At.FlatDistance(candidate.At);
                if (gap < bestGap)
                {
                    bestGap = gap;
                    tree = candidate;
                }
            }
            if (!tree.HasValue) return false;
            Dig(view, tree.Value, decision, HeroTask.ChopTree);
            return true;
        }

        /// Место под дом — на кольцах вокруг спавна эльфов, ближнее кольцо первым.
        public static V3? ElfSpot(HeroView view)
        {
            var centre = Factions.Spawn[(int)Faction.Elves];
            foreach (float radius in AiStats.ElfRing)
            {
                V3? best = null;
                float bestGap = float.MaxValue;
                for (int i = 0; i < AiStats.ElfAngles; i++)
                {
                    double angle = 2.0 * Math.PI * i / AiStats.ElfAngles;
                    var at = new V3(centre.X + (float)Math.Cos(angle) * radius, 0f, centre.Z - (float)Math.Sin(angle) * radius);
                    if (view.ElfSpotBuildable != null && !view.ElfSpotBuildable(at)) continue;
                    float gap = view.At.FlatDistance(at);
                    if (gap < bestGap)
                    {
                        bestGap = gap;
                        best = at;
                    }
                }
                if (best.HasValue) return best;
            }
            return null;
        }

        /// Лишнее добро — в снаряжение: кузня (не эльфы), доспех в лавке, зелье эльфам.
        static bool GearErrand(HeroView view, HeroDecision decision)
        {
            if (view.Forge.HasValue && view.Side != Faction.Elves && Rich(view.Stock, view.NextGearCost))
                return Errand(decision, HeroTask.ForgeGear, view.Forge.Value, view.AtForge);
            if (Rich(view.Stock, view.NextArmorCost))
                return Errand(decision, HeroTask.BuyArmor, view.Trader, view.AtTrader);
            if (view.Side == Faction.Elves && view.PotionsHeal == 0 && Rich(view.Stock, Res.PotionHealCost))
                return Errand(decision, HeroTask.BuyPotion, view.Trader, view.AtTrader);
            return false;
        }

        static bool Errand(HeroDecision decision, HeroTask task, V3 place, bool there)
        {
            decision.Task = task;
            decision.Goal = place;
            decision.Walk = !there;
            decision.Interact = there;
            return true;
        }

        /// «Богат» — есть вдвое против цены: покупка не оставит сторону без стройки.
        public static bool Rich(int[] stock, int[] cost)
        {
            if (cost == null || cost.Length == 0) return false;
            for (int kind = 0; kind < Res.Count; kind++)
                if (Res.At(stock, kind) < Res.At(cost, kind) * AiStats.Surplus) return false;
            return true;
        }
    }

    /// Геометрия на плоскости земли.
    public static class Geometry
    {
        /// Пересекает ли отрезок a→b прямоугольник ±half с центром в нуле (Лян — Барски).
        public static bool SegmentHitsBox(float ax, float az, float bx, float bz, float halfX, float halfZ)
        {
            float dx = bx - ax;
            float dz = bz - az;
            float t0 = 0f, t1 = 1f;
            float[] p = { -dx, dx, -dz, dz };
            float[] q = { ax + halfX, halfX - ax, az + halfZ, halfZ - az };
            for (int k = 0; k < 4; k++)
            {
                if (Math.Abs(p[k]) < 0.0001f)
                {
                    if (q[k] < 0f) return false;
                    continue;
                }
                float t = q[k] / p[k];
                if (p[k] < 0f) t0 = Math.Max(t0, t);
                else t1 = Math.Min(t1, t);
            }
            return t0 <= t1;
        }

        /// Стоит ли глухая постройка между точками. Постройка, в которой лежит
        /// сама цель, не мешает: к ней и идут. Поле проходимо.
        public static bool BuildingBetween(V3 from, V3 to, IEnumerable<KeyValuePair<BuildingKind, V3>> buildings)
        {
            foreach (var building in buildings)
            {
                if (Res.Walkable(building.Key)) continue;
                var size = Res.BuildingSize(building.Key);
                float hx = size.X * 0.5f, hz = size.Z * 0.5f;
                var c = building.Value;
                if (Math.Abs(to.X - c.X) <= hx && Math.Abs(to.Z - c.Z) <= hz) continue;
                if (SegmentHitsBox(from.X - c.X, from.Z - c.Z, to.X - c.X, to.Z - c.Z, hx, hz)) return true;
            }
            return false;
        }
    }
}
