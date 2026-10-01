// Обоз в мире (перенос economy/caravan.gd): рейс считает CaravanTrip ядра
// (маршрут, погрузка, объезд, упряжка), здесь — телега на рельефе и удары.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class CaravanActor : Actor
    {
        public const float ClimbRate = 3f;

        public CaravanTrip Trip;
        public World World;
        public Wallet Treasury;
        public System.Func<V3, int[]> Load;

        public override bool Alive { get { return Trip != null && Trip.Health > 0f && Trip.State != CaravanState.Finished; } }

        public static CaravanActor Spawn(Faction side, int owner, List<V3> route, int horses, World world, Wallet treasury,
            System.Func<V3, int[]> load)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "Обоз";
            go.transform.localScale = new Vector3(2.6f, 2f, 4.4f);
            go.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of("wood");
            var actor = go.AddComponent<CaravanActor>();
            actor.Trip = new CaravanTrip(side, owner, route, horses);
            actor.Side = (int)side;
            actor.World = world;
            actor.Treasury = treasury;
            actor.Load = load;
            go.transform.position = actor.Trip.Position.ToUnity();
            return actor;
        }

        void Update()
        {
            if (Trip == null) return;
            bool enemyNear = false;
            foreach (var other in Actor.All)
                if (other != this && other.Alive && !(other is BuildingActor) && Factions.Hostile(Side, other.Side)
                    && other.At.FlatDistance(At) <= CaravanRules.HaltRange)
                {
                    enemyNear = true;
                    break;
                }
            var buildings = new List<KeyValuePair<BuildingKind, V3>>();
            foreach (var other in Actor.All)
            {
                var building = other as BuildingActor;
                if (building != null && building.Alive) buildings.Add(new KeyValuePair<BuildingKind, V3>(building.State.Kind, building.At));
            }
            var e = Trip.Tick(Time.deltaTime, enemyNear, buildings, Load, Treasury);
            // Высота — по рельефу, плавно (3 м/с): точки маршрута лежат на земле.
            float ground = World != null ? World.Relief.Height(Trip.Position.X, Trip.Position.Z) : Trip.Position.Y;
            float y = Mathf.MoveTowards(transform.position.y, ground + 1f, ClimbRate * Time.deltaTime);
            var at = Trip.Position.ToUnity();
            transform.SetPositionAndRotation(new Vector3(at.x, y, at.z), CoreSpace.YawToRotation(Trip.Yaw));
            if (e == TripEvent.Finished) Destroy(gameObject);
        }

        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive) return;
            // Удар по упряжке — лошадям; по повозке — повозке.
            if (zone == "harness") Trip.HurtHarness(amount);
            else Trip.Health = Mathf.Max(0f, Trip.Health - amount);
            if (Trip.Health <= 0f) Destroy(gameObject);
        }
    }
}
