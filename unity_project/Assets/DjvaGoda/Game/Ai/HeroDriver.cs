// Руки героя под ИИ (перенос ai/hero.gd::_drive). Решает HeroBrain ядра раз в
// полсекунды: драться, защищать хозяйство, копать микро-шахту, ставить дом
// эльфов, рубить лес, идти в кузню или лавку, держаться отряда или обоза.
// Здесь — то, что сделал бы человек: идти по сетке навигации, повернуться к
// цели, ударить, сколдовать, выпить зелье, купить, поставить дом. Всё — теми же
// заявками хосту, что у игрока (PlayerCombat, PlayerSpells, Shop, Builder):
// своей экономики и своих правил у ИИ нет.
//
// Только хост.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(PlayerCharacter))]
    public class HeroDriver : MonoBehaviour
    {
        public const float ThinkInterval = 0.5f;

        PlayerCharacter _hero;
        PlayerCombat _combat;
        PlayerSpells _spells;
        Shop _shop;
        Builder _builder;
        NavWorld _nav;
        readonly PathFollower _follower = new PathFollower();
        HeroDecision _decision;
        float _think;

        public HeroDecision Decision { get { return _decision; } }

        void Awake()
        {
            _hero = GetComponent<PlayerCharacter>();
            _combat = GetComponent<PlayerCombat>();
            _spells = GetComponent<PlayerSpells>();
            _shop = GetComponent<Shop>();
            _builder = GetComponent<Builder>();
        }

        void Update()
        {
            if (!_hero.Alive)
            {
                _hero.Scripted = new MotorInput();
                return;
            }
            if (_nav == null) _nav = Object.FindAnyObjectByType<NavWorld>();
            _think -= Time.deltaTime;
            if (_think <= 0f)
            {
                _think = ThinkInterval;
                _decision = HeroBrain.Decide(View());
                Act(_decision);
            }
            if (_decision != null) Steer(_decision);
        }

        /// Что видит герой: враги и свои, хозяйство, запас стороны, места дел.
        HeroView View()
        {
            var side = _hero.Faction;
            var wallet = Treasury.Of(side);
            var view = new HeroView
            {
                Side = side,
                At = _hero.Feet,
                Health = _hero.Vitals.Health,
                MaxHealth = _hero.Vitals.MaxHealth,
                PotionsHeal = _hero.Kit.PotionsHeal,
                Weapon = _combat != null ? _combat.Weapon : WeaponKind.Sword,
                Trader = MapLayout.Traders[(int)side],
                AtTrader = _shop != null && _shop.AtTrader,
                NextGearCost = _hero.Kit.NextGearCost(),
                NextArmorCost = _hero.Kit.NextArmorCost(),
                HasStorage = false,
                ElfHouseLimit = Respawn.ElfHouseLimit(1),
                ElfSpotBuildable = point =>
                {
                    float top;
                    return Builder.Fits(BuildingKind.ElfHouse, point, out top);
                },
            };
            for (int i = 0; i < Res.Count; i++) view.Stock[i] = wallet.GetAmount(i);
            foreach (var actor in Actor.All)
            {
                if (actor == null || actor == _hero || !actor.Alive) continue;
                var building = actor as BuildingActor;
                if (building != null)
                {
                    if (building.Side != (int)side) continue;
                    view.Posts.Add(building.At);
                    if (building.State.Done && building.State.Kind == BuildingKind.Storage) view.HasStorage = true;
                    if (Res.IsElfHouse(building.State.Kind)) view.ElfHouses++;
                    if (building.State.Done && building.State.Kind == BuildingKind.Forge) view.Forge = building.At;
                    continue;
                }
                var cart = actor as CaravanActor;
                if (cart != null)
                {
                    if (cart.Side == (int)side && (!view.OwnCart.HasValue || cart.At.FlatDistance(view.At) < view.OwnCart.Value.FlatDistance(view.At)))
                        view.OwnCart = cart.At;
                    continue;
                }
                if (actor.Side == (int)side)
                {
                    if (actor is LabourerAgent) view.Posts.Add(actor.At);
                    continue;
                }
                view.Others.Add(new SidedPoint(actor.At, actor.Side));
            }
            view.AtForge = view.Forge.HasValue && _shop != null && _shop.BuildingAtHand(BuildingKind.Forge) != null;
            foreach (var source in Harvestable.All)
            {
                var at = source.transform.position.ToCore();
                if (source.TreeIndex < 0 && at.FlatDistance(MapLayout.MicroMine) <= AiStats.MicroRadius)
                    view.MicroVeins.Add(new Vein(at, RockRadius(source)));
                else if (side == Faction.Elves && source.Resource == ResourceKind.Wood
                    && at.FlatDistance(Factions.Spawn[(int)Faction.Elves]) <= AiStats.ElfWoods)
                    view.Trees.Add(new Vein(at, Forest.TrunkRadius * source.transform.localScale.x));
            }
            return view;
        }

        /// Действия раз в полсекунды: зелье, оружие, удар, заклинание, дела у мест.
        void Act(HeroDecision decision)
        {
            if (decision.UsePotion && _shop != null) _shop.ServerDeal(DealKind.Potion, 1);
            if (decision.Weapon.HasValue && _combat != null && _combat.Allowed(decision.Weapon.Value)) _combat.Weapon = decision.Weapon.Value;
            if (decision.Spell.HasValue && _spells != null && _hero.Spells.Ready(decision.Spell.Value)) _spells.ServerCast(decision.Spell.Value);
            if (!decision.Interact) return;
            switch (decision.Task)
            {
                case HeroTask.ForgeGear: if (_shop != null) _shop.ServerDeal(DealKind.Forge, 0); break;
                case HeroTask.BuyArmor: if (_shop != null) _shop.ServerDeal(DealKind.Trade, (int)TradeItem.Armor); break;
                case HeroTask.BuyPotion: if (_shop != null) _shop.ServerDeal(DealKind.Trade, (int)TradeItem.PotionHeal); break;
                case HeroTask.BuildElfHouse:
                    if (_builder != null && decision.BuildAt.HasValue) _builder.ServerBuild(BuildingKind.ElfHouse, decision.BuildAt.Value);
                    break;
            }
        }

        /// Радиус валуна по его коллайдеру: с прежних «2 м» вожак вставал так
        /// далеко, что молот (3.2 м) до камня не доставал и казна стояла на нуле.
        static float RockRadius(Harvestable source)
        {
            var col = source.GetComponentInChildren<Collider>();
            if (col == null) return 1f;
            var ext = col.bounds.extents;
            return Mathf.Min(ext.x, ext.z) * 0.7f;
        }

        /// Каждый кадр: идти к цели по сетке, смотреть на цель, бить, когда можно.
        void Steer(HeroDecision decision)
        {
            var here = _hero.Feet;
            if (decision.Walk)
            {
                PathFinder finder = _nav != null && _nav.Ready ? _nav.Finder : null;
                var step = _follower.NextStep(here, decision.Goal, finder, _nav != null ? (System.Func<V3, V3>)_nav.ClosestPoint : null);
                var to = (step - here).Flat();
                if (to.Length() < 0.05f) to = (decision.Goal - here).Flat();
                if (to.Length() > 0.05f) _hero.Yaw = Mathf.Atan2(to.X, to.Z);
                _hero.Scripted = new MotorInput { MoveY = -1f, Run = here.FlatDistance(decision.Goal) > 30f };
                _follower.NoteProgress(Time.deltaTime, true, here, decision.Goal);
            }
            else _hero.Scripted = new MotorInput();

            if (!decision.Target.HasValue) return;
            var target = decision.Target.Value + new V3(0f, 1f, 0f);
            var aim = target - Aim.Origin(here);
            var flat = aim.Flat();
            if (!decision.Walk && flat.Length() > 0.05f) _hero.Yaw = Mathf.Atan2(flat.X, flat.Z);
            if (!decision.Attack || _combat == null) return;
            if (decision.NeedsClearThrow && Blocked(Aim.Origin(here), target)) return;
            _combat.ServerAttack(_combat.Weapon, Aim.Origin(here), aim.Normalized());
        }

        /// Огненный шар в стену — себе под ноги: бросать только по чистой линии.
        static bool Blocked(V3 from, V3 to)
        {
            return Physics.Linecast(from.ToUnity(), to.ToUnity(), HitZone.WorldMask, QueryTriggerInteraction.Ignore);
        }
    }
}
