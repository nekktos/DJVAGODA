// Батрак в мире (перенос units/labourer.gd): мозг ядра решает, куда идти и что
// делать; здесь — шаг, удар по дереву или камню, ноша на склад. Ополченца
// ведёт отряд как бойца (UnitAgent на том же объекте включается вместо).
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(CharacterController))]
    public class LabourerAgent : Actor
    {
        public LabourerBrain Brain;
        public float Health = UnitStats.Health(UnitKind.Swordsman);
        public V3 Home;
        public NavWorld Nav;
        public World World;
        public Wallet Treasury;
        public bool Hungry;
        /// Пропущенные кормёжки (Hunger ядра); с HungerFatal — умирает.
        public int MissedMeals;

        readonly PathFollower _follower = new PathFollower();
        CharacterController _controller;
        float _fall;

        public override bool Alive { get { return Health > 0f; } }

        void Awake()
        {
            _controller = GetComponent<CharacterController>();
            _controller.height = 1.8f;
            _controller.radius = 0.4f;
            _controller.center = new Vector3(0f, 0.9f, 0f);
            _controller.slopeLimit = 45f;
            // Перемещения короче minMoveDistance CharacterController молча
            // выбрасывает. При тысячах кадров в секунду (фоновый прогон, мощная
            // машина) шаг за кадр меньше миллиметра — персонаж проходил 6% пути.
            _controller.minMoveDistance = 0f;
            HitZone.Humanoid(transform, this);
        }

        void Update()
        {
            if (Brain == null || !Alive) return;
            Side = (int)Brain.Side;
            float delta = Time.deltaTime;
            var view = new LabourerView { At = At, Home = Home, Hungry = Hungry };
            foreach (var other in Actor.All)
            {
                if (other == null || other == this || !other.Alive) continue;
                if (!(other is BuildingActor) && other.At.FlatDistance(At) <= LabourerStats.FleeRadius + 2f)
                    view.Others.Add(new SidedPoint(other.At, other.Side));
                var building = other as BuildingActor;
                if (building != null && building.Side == Side) view.Sites.Add(SiteOf(building));
            }
            AddHarvestables(view);
            if (Brain.Role == LabourerRole.Miner) view.SideMine = Mines.SiteFor(Home);
            var order = Brain.Tick(delta, view);
            Walk(delta, order.Goal);
            switch (order.Action)
            {
                case LabourAction.Harvest: Harvest(order.Site); break;
                case LabourAction.Dig: if (order.Site != null) Mines.Dig(order.Site.Id, Id); break;
                case LabourAction.Build:
                {
                    var building = order.Site != null ? Actor.ById(order.Site.Id) as BuildingActor : null;
                    if (building != null) building.NoteBuilder(Id);
                    break;
                }
                case LabourAction.Take:
                {
                    var farm = order.Site != null ? Actor.ById(order.Site.Id) as BuildingActor : null;
                    if (farm != null && farm.State != null) Brain.Took(farm.State.TakeGrown(Brain.Room));
                    break;
                }
                case LabourAction.Deliver: if (Treasury != null) Brain.Unload(Treasury); break;
            }
        }

        static WorkSite SiteOf(BuildingActor building)
        {
            var kind = building.State.Kind;
            var size = Res.BuildingSize(kind);
            var siteKind = !building.State.Done ? SiteKind.Construction
                : kind == BuildingKind.Farm ? SiteKind.Farm
                : kind == BuildingKind.Storage ? SiteKind.Storage : SiteKind.Construction;
            return new WorkSite { Id = building.Id, Kind = siteKind, Side = (Faction)building.Side, At = building.At, Body = Mathf.Max(size.X, size.Z) * 0.5f };
        }

        /// Деревья и камни рядом — добыча для лесоруба и шахтёра.
        void AddHarvestables(LabourerView view)
        {
            foreach (var harvest in Harvestable.All)
            {
                var at = harvest.transform.position.ToCore();
                if (at.FlatDistance(At) > 200f) continue;
                view.Sites.Add(new WorkSite
                {
                    Id = harvest.Id,
                    Kind = SiteKind.Harvestable,
                    At = at,
                    Resource = harvest.Resource,
                    Body = harvest.TreeIndex >= 0 ? 1.1f : 2f,
                });
            }
        }

        void Harvest(WorkSite site)
        {
            if (site == null) return;
            foreach (var harvest in Harvestable.All)
            {
                if (harvest.Id != site.Id) continue;
                Brain.Harvested(harvest.Resource);
                if (harvest.TakeHit()) Brain.SiteGone();
                return;
            }
        }

        void Walk(float delta, V3 goal)
        {
            var here = At;
            PathFinder finder = Nav != null && Nav.Ready ? Nav.Finder : null;
            var step = _follower.NextStep(here, goal, finder, Nav != null ? (System.Func<V3, V3>)Nav.ClosestPoint : null);
            bool moving = here.FlatDistance(goal) > UnitStats.SlotTolerance;
            var desired = new V3(0f, 0f, 0f);
            if (moving)
            {
                var to = (step - here).Flat();
                if (to.Length() < 0.01f) to = (goal - here).Flat();
                desired = to.Normalized() * UnitStats.Speed(UnitKind.Swordsman);
                transform.rotation = CoreSpace.YawToRotation(Mathf.Atan2(to.X, to.Z));
            }
            _fall = _controller.isGrounded ? -2f : _fall - CharacterMotor.Gravity * delta;
            _controller.Move(new V3(desired.X, _fall, desired.Z).ToUnity() * delta);
            _follower.NoteProgress(delta, moving, At, goal);
        }

        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive) return;
            Health = Mathf.Max(0f, Health - amount);
            if (Alive) return;
            // Ноша падает на землю кучей — подобрать может любой.
            Brain.DropOnDeath();
            Agents.Remove(gameObject);
        }
    }
}
