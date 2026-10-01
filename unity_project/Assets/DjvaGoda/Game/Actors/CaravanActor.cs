// Обоз в мире (перенос economy/caravan.gd): рейс считает CaravanTrip ядра
// (маршрут, погрузка, объезд, упряжка), здесь — телега на рельефе и удары.
//
// Считает хост. По сети обоз — префаб Resources/Caravan (NetworkObject,
// NetworkTransform хоста, CaravanNet — сторона); без сети — простой объект.
// Лошади уходят с обозом (HorsesOut) и, доехав, возвращаются в конюшню;
// убитые в упряжке и ушедшие с разбитой телегой — потеря стороны.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
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
        int _team;
        bool _settled;

        public override bool Alive { get { return Trip != null && Trip.Health > 0f && Trip.State != CaravanState.Finished; } }

        /// У клиента рейса нет — упряжку, стоянку и груз везёт CaravanNet.
        [System.NonSerialized] public int ShownHorses;
        [System.NonSerialized] public bool ShownHalted;
        [System.NonSerialized] public int ShownCargo;
        [System.NonSerialized] public int ShownOwner;
        [System.NonSerialized] public int ShownState;
        [System.NonSerialized] public float ShownLeft;
        public int OwnerNow { get { return Trip != null ? Trip.Owner : ShownOwner; } }
        public int StateNow { get { return Trip != null ? (int)Trip.State : ShownState; } }
        /// Сколько метров рейса осталось.
        public float LeftNow
        {
            get
            {
                if (Trip == null) return ShownLeft;
                var ahead = Trip.PathAhead();
                float total = 0f;
                var from = Trip.Position;
                foreach (var point in ahead)
                {
                    total += from.FlatDistance(point);
                    from = point;
                }
                return total;
            }
        }
        public int HorsesNow { get { return Trip != null ? Trip.Horses : ShownHorses; } }
        public bool HaltedNow { get { return Trip != null ? Trip.Halted : ShownHalted; } }
        public int CargoNow { get { return Trip != null ? Trip.CargoTotal : ShownCargo; } }
        /// Стоит в мире (у клиента — заспавнен, у хоста — жив).
        public bool Present { get { return Trip != null ? Alive : GetComponent<NetworkObject>() != null && GetComponent<NetworkObject>().IsSpawned; } }

        /// Что сторона может сделать с этим обозом, подойдя вплотную (правило ядра).
        public CaravanAction ActionFor(Faction actor)
        {
            if (!Present) return CaravanAction.None;
            return CaravanRules.ActionFor(actor, (Faction)Side, HorsesNow, HaltedNow, CargoNow, Builder.HasStorage(actor));
        }

        /// Увести лошадей (у хоста): из конюшни прежнего хозяина они ушли
        /// насовсем и встают рядом живыми — до дома их ещё надо довести.
        public int CaptureHorses()
        {
            int taken = Trip.CaptureHorses();
            if (taken <= 0) return 0;
            _team = Mathf.Max(0, _team - taken);
            if (Treasury != null)
            {
                Treasury.Horses = Mathf.Max(0, Treasury.Horses - taken);
                Treasury.HorsesOut = Mathf.Max(0, Treasury.HorsesOut - taken);
            }
            for (int i = 0; i < taken; i++) HorseActor.Spawn(At + new V3(2f + 2f * i, 0f, 2f));
            Debug.Log("[обоз] уведено лошадей: " + taken);
            return taken;
        }

        /// Разграбить (у хоста): груз кучей на землю, повозка — лом.
        public void Plunder()
        {
            if (!Alive) return;
            Trip.Health = 0f;
            Spill();
            Leave(0);
        }

        /// Перехват (у хоста): обоз едет на склад перехватчика, лошади
        /// упряжки переходят к нему вместе с обозом.
        public bool Intercept(Faction side, int owner, List<V3> walked)
        {
            if (walked == null || walked.Count < 2) return false;
            var from = Treasury;
            var into = Game.Treasury.Of(side);
            if (from != null)
            {
                from.Horses = Mathf.Max(0, from.Horses - _team);
                from.HorsesOut = Mathf.Max(0, from.HorsesOut - _team);
            }
            into.Horses += _team;
            into.HorsesOut += _team;
            Treasury = into;
            Side = (int)side;
            Trip.Redirect(side, owner, walked);
            return true;
        }

        /// Груз разбитой или разграбленной телеги — кучей на землю.
        void Spill()
        {
            if (Trip.CargoTotal <= 0) return;
            Pickup.Drop(At + new V3(0f, 0.6f, 0f), new LootPile { Contents = Res.Fit(Trip.Cargo) });
            Trip.Cargo = Res.Empty();
        }

        static GameObject _prefab;

        static bool Networked
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net != null && net.IsListening && net.IsServer;
            }
        }

        public static CaravanActor Spawn(Faction side, int owner, List<V3> route, int horses, World world, Wallet treasury,
            System.Func<V3, int[]> load)
        {
            GameObject go;
            if (Networked)
            {
                if (_prefab == null) _prefab = Resources.Load<GameObject>("Caravan");
                go = Instantiate(_prefab);
            }
            else go = new GameObject();
            go.name = "Обоз (" + Factions.Names[(int)side] + ")";
            var actor = go.GetComponent<CaravanActor>();
            if (actor == null) actor = go.AddComponent<CaravanActor>();
            actor.Trip = new CaravanTrip(side, owner, route, horses);
            actor._team = actor.Trip.Horses;
            actor.Side = (int)side;
            actor.World = world;
            actor.Treasury = treasury;
            actor.Load = load;
            go.transform.position = actor.Trip.Position.ToUnity();
            if (Networked)
            {
                go.GetComponent<CaravanNet>().AssignedSide = side;
                go.GetComponent<NetworkObject>().Spawn();
            }
            else Build(go.transform, side, actor);
            return actor;
        }

        /// Вид и зоны попадания: телега и упряжка спереди.
        public static void Build(Transform root, Faction side, Actor owner)
        {
            var cart = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cart.name = "Телега";
            Destroy(cart.GetComponent<Collider>());
            cart.transform.SetParent(root, false);
            cart.transform.localPosition = new Vector3(0f, 0.2f, 0f);
            cart.transform.localScale = new Vector3(2.6f, 2f, 4.4f);
            cart.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of("wood");
            var flag = GameObject.CreatePrimitive(PrimitiveType.Cube);
            flag.name = "Флаг";
            Destroy(flag.GetComponent<Collider>());
            flag.transform.SetParent(root, false);
            flag.transform.localPosition = new Vector3(0f, 1.6f, -1.6f);
            flag.transform.localScale = new Vector3(0.1f, 1.2f, 0.8f);
            flag.GetComponent<MeshRenderer>().sharedMaterial = Palette.Side(side);
            if (owner == null) return;
            Zone(root, owner, "torso", new Vector3(0f, 0.2f, 0f), new Vector3(2.6f, 2f, 4.4f));
            Zone(root, owner, "harness", new Vector3(0f, 0f, 3.4f), new Vector3(1.6f, 1.6f, 2.2f));
        }

        static void Zone(Transform root, Actor owner, string zone, Vector3 at, Vector3 size)
        {
            var go = new GameObject(zone);
            go.layer = HitZone.Layer;
            go.transform.SetParent(root, false);
            go.transform.localPosition = at;
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = size;
            var hit = go.AddComponent<HitZone>();
            hit.Zone = zone;
            hit.Owner = owner;
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
            if (e == TripEvent.Finished)
            {
                if (Home != null) Home(this);
                Leave(Trip.Horses);
            }
        }

        /// Обоз доехал до склада и рейс кончен (у хоста) — для приказа «сопроводить».
        public static event System.Action<CaravanActor> Home;

        /// Обоз остановлен игроком — увёл лошадей, перехватил, разграбил (у
        /// хоста): для засады эльфов, погони и перехвата стражи. Разбитый ударом
        /// идёт через Actor.Killed.
        public static event System.Action<CaravanActor, Faction, PlayerCharacter> Lost;

        public static void NoteLost(CaravanActor cart, Faction owner, PlayerCharacter by)
        {
            if (Lost != null) Lost(cart, owner, by);
        }

        /// Рейс кончен или телега разбита: живые лошади — в конюшню, прочие — потеря.
        void Leave(int horsesBack)
        {
            if (_settled) return;
            _settled = true;
            if (Treasury != null)
            {
                Treasury.HorsesOut = Mathf.Max(0, Treasury.HorsesOut - _team);
                Treasury.Horses = Mathf.Max(0, Treasury.Horses - (_team - horsesBack));
            }
            var net = GetComponent<NetworkObject>();
            if (net != null && net.IsSpawned) net.Despawn(true);
            else Destroy(gameObject);
        }

        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive) return;
            // Удар по упряжке — лошадям; по повозке — повозке.
            if (zone == "harness") Trip.HurtHarness(amount);
            else Trip.Health = Mathf.Max(0f, Trip.Health - amount);
            if (Trip.Health > 0f) return;
            Spill();
            Leave(0);
        }
    }
}
