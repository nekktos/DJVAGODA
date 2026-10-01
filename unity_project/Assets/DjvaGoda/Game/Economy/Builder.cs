// Стройка игрока (перенос economy/build_controller.gd и world.gd: стройка,
// ask_build/request_build).
//
// Сверху (Tab) клавиши 1–6 и U выбирают постройку, эльф из боя берёт план дома
// клавишей N. «Призрак» под курсором (сверху) или под прицелом (из боя) — зелёный,
// если место годится, красный — если нет; ЛКМ — заявка, ПКМ — отмена. Призрак
// — только подсказка владельцу: решает хост и проверяет всё заново по своей
// копии мира (земля пятью лучами, зазор до построек, цена, лимит домов эльфов —
// Placement и Deals.Build ядра). Дом садится полом на самую высокую точку под
// собой.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(PlayerCharacter))]
    public class Builder : MonoBehaviour
    {
        static readonly KeyValuePair<string, BuildingKind>[] Keys =
        {
            new KeyValuePair<string, BuildingKind>("build_storage", BuildingKind.Storage),
            new KeyValuePair<string, BuildingKind>("build_sword", BuildingKind.SwordBarracks),
            new KeyValuePair<string, BuildingKind>("build_archer", BuildingKind.ArcherBarracks),
            new KeyValuePair<string, BuildingKind>("build_stable", BuildingKind.Stable),
            new KeyValuePair<string, BuildingKind>("build_house", BuildingKind.House),
            new KeyValuePair<string, BuildingKind>("build_farm", BuildingKind.Farm),
            new KeyValuePair<string, BuildingKind>("build_forge", BuildingKind.Forge),
        };

        static readonly KeyValuePair<string, LabourerRole>[] RoleKeys =
        {
            new KeyValuePair<string, LabourerRole>("role_lumberjack", LabourerRole.Lumberjack),
            new KeyValuePair<string, LabourerRole>("role_miner", LabourerRole.Miner),
            new KeyValuePair<string, LabourerRole>("role_militia", LabourerRole.Militia),
            new KeyValuePair<string, LabourerRole>("role_builder", LabourerRole.Builder),
            new KeyValuePair<string, LabourerRole>("role_farmer", LabourerRole.Farmer),
        };

        public static IEnumerable<KeyValuePair<string, LabourerRole>> Roles { get { return RoleKeys; } }

        public bool Placing { get; private set; }
        /// Прокладка маршрута обоза (C): точки кликами, Enter — отправить.
        public bool Routing { get; private set; }
        public const int MaxRoutePoints = 12;
        public const int HarnessSize = 2;
        readonly List<V3> _route = new List<V3>();
        readonly List<GameObject> _marks = new List<GameObject>();
        public int RoutePoints { get { return _route.Count; } }
        public BuildingKind Kind { get; private set; }

        PlayerCharacter _character;
        PlayerCombat _combat;
        NetPlayer _net;
        Transform _ghost;
        bool _valid;
        V3 _point;

        void Awake()
        {
            _character = GetComponent<PlayerCharacter>();
            _combat = GetComponent<PlayerCombat>();
            _net = GetComponent<NetPlayer>();
        }

        bool Hosting { get { return _net == null || !_net.IsSpawned || _net.IsServer; } }

        public static IEnumerable<KeyValuePair<string, BuildingKind>> Menu { get { return Keys; } }

        void Update()
        {
            if (!_character.LocalControl || !_character.Alive)
            {
                Stop();
                return;
            }
            if (GameMode.Strategy)
            {
                foreach (var key in Keys)
                    if (GameInput.Pressed(key.Key) && Factions.MayBuild(_character.Faction, key.Value, _character.Kit.IsLeader))
                        Begin(key.Value);
                if (GameInput.Pressed("hire_labourer")) Labour(-1);
                if (GameInput.Pressed("route"))
                {
                    if (Routing) StopRoute();
                    else
                    {
                        Stop();
                        Routing = true;
                    }
                }
                foreach (var key in RoleKeys)
                    if (GameInput.Pressed(key.Key)) Labour((int)key.Value);
            }
            else if (_character.Faction == Faction.Elves && GameInput.Pressed("build_elf_house"))
            {
                if (Placing) Stop();
                else Begin(BuildingKind.ElfHouse);
            }
            else if (Placing && !Res.IsElfHouse(Kind)) Stop();
            if (!GameMode.Strategy) StopRoute();
            if (Routing) Route();
            if (!Placing) return;

            var mouse = UnityEngine.InputSystem.Mouse.current;
            var keyboard = UnityEngine.InputSystem.Keyboard.current;
            if ((mouse != null && mouse.rightButton.wasPressedThisFrame) || (keyboard != null && keyboard.escapeKey.wasPressedThisFrame))
            {
                Stop();
                return;
            }
            Aim();
            if (mouse != null && mouse.leftButton.wasPressedThisFrame && (GameMode.Strategy || Cursor.lockState == CursorLockMode.Locked))
            {
                var kind = Kind;
                var point = _point;
                Stop();
                if (Hosting) ServerBuild(kind, point);
                else _net.BuildRpc((int)kind, point.ToUnity());
            }
        }

        /// Маршрут обоза: ЛКМ — точка, Enter — отправить, ПКМ/Esc — отменить.
        void Route()
        {
            var mouse = UnityEngine.InputSystem.Mouse.current;
            var keyboard = UnityEngine.InputSystem.Keyboard.current;
            if ((mouse != null && mouse.rightButton.wasPressedThisFrame) || (keyboard != null && keyboard.escapeKey.wasPressedThisFrame))
            {
                StopRoute();
                return;
            }
            if (keyboard != null && (keyboard.enterKey.wasPressedThisFrame || keyboard.numpadEnterKey.wasPressedThisFrame))
            {
                var points = _route.ToArray();
                StopRoute();
                if (Hosting) ServerSendCaravan(points);
                else
                {
                    var sent = new Vector3[points.Length];
                    for (int i = 0; i < points.Length; i++) sent[i] = points[i].ToUnity();
                    _net.CaravanRpc(sent);
                }
                return;
            }
            if (mouse == null || !mouse.leftButton.wasPressedThisFrame || _route.Count >= MaxRoutePoints) return;
            var rig = Object.FindAnyObjectByType<CameraRig>();
            if (rig == null || rig.Camera == null) return;
            RaycastHit hit;
            if (!Physics.Raycast(rig.Camera.ScreenPointToRay(mouse.position.ReadValue()), out hit, 1200f, HitZone.WorldMask, QueryTriggerInteraction.Ignore))
                return;
            _route.Add(hit.point.ToCore());
            var mark = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            mark.name = "Точка маршрута " + _route.Count;
            Destroy(mark.GetComponent<Collider>());
            mark.transform.position = hit.point + Vector3.up * 2f;
            mark.transform.localScale = new Vector3(1.2f, 2f, 1.2f);
            mark.GetComponent<MeshRenderer>().sharedMaterial = Palette.Side(_character.Faction);
            _marks.Add(mark);
        }

        void StopRoute()
        {
            Routing = false;
            _route.Clear();
            foreach (var mark in _marks) if (mark != null) Destroy(mark);
            _marks.Clear();
        }

        /// Свой достроенный склад (у хоста).
        public static bool HasStorage(Faction side) { return StorageOf(side) != null; }

        public static BuildingActor StorageOf(Faction side)
        {
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.State.Done && building.State.Kind == BuildingKind.Storage
                    && building.Side == (int)side) return building;
            }
            return null;
        }

        int OwnerId { get { return _net != null && _net.IsSpawned ? (int)_net.OwnerClientId : 0; } }

        /// Отправка обоза у хоста (перенос request_send_caravan): обоз выходит
        /// от склада, едет по точкам игрока и в конце — к шахте у последней точки
        /// (без точек — к ближайшей к складу). Запрягают сколько есть свободных.
        public void ServerSendCaravan(V3[] points)
        {
            if (!_character.Alive) return;
            var side = _character.Faction;
            var wallet = Treasury.Of(side);
            var storage = StorageOf(side);
            int carts = 0;
            foreach (var actor in Actor.All)
            {
                var cart = actor as CaravanActor;
                if (cart != null && cart.Alive && cart.Trip.Owner == OwnerId) carts++;
            }
            var deal = Deals.SendCaravan(wallet, storage != null, carts, points);
            if (!deal.Ok)
            {
                if (_combat != null && !string.IsNullOrEmpty(deal.Refusal)) _combat.Tell(deal.Refusal);
                return;
            }
            var route = new List<V3> { storage.At };
            route.AddRange(points);
            route.Add(Mines.Dock(Mines.Nearest(route[route.Count - 1])));
            int team = Mathf.Min(HarnessSize, wallet.HorsesFree);
            wallet.HorsesOut += team;
            if (team < HarnessSize && _combat != null) _combat.Tell("свободных лошадей " + team + " — запрягли столько");
            CaravanActor.Spawn(side, OwnerId, route, team, Object.FindAnyObjectByType<World>(), wallet, Mines.Load);
        }

        /// Хозяйство: −1 — нанять батрака, иначе — перевести одного на дело.
        void Labour(int role)
        {
            if (Hosting) ServerLabour(role);
            else _net.LabourRpc(role);
        }

        /// Батраки стороны (у хоста).
        public static List<LabourerAgent> Crew(Faction side)
        {
            var crew = new List<LabourerAgent>();
            foreach (var actor in Actor.All)
            {
                var worker = actor as LabourerAgent;
                if (worker != null && worker.Alive && worker.Brain != null && worker.Brain.Side == side) crew.Add(worker);
            }
            return crew;
        }

        /// Найм и перевод батраков — у хоста (перенос request_hire_labourer и
        /// request_set_labourer_role). Новый батрак — лесоруб у точки стороны;
        /// перевод берёт одного с самого многолюдного дела: без выбора мышью
        /// это единственный порядок, который не требует помнить, кого уже переводил.
        /// Батрак стороны у её точки (у хоста): наём и восстановление из сохранения.
        public static LabourerAgent SpawnLabourer(Faction side, LabourerRole role, int index)
        {
            var home = Factions.Spawn[(int)side];
            var spot = StewardRules.HireSpot(home, index);
            var go = Agents.Make(AgentRole.Labourer, side, spot + new V3(0f, 0.5f, 0f), "Батрак");
            var worker = go.AddComponent<LabourerAgent>();
            worker.Brain = new LabourerBrain(side, role);
            worker.Home = home;
            worker.Nav = Object.FindAnyObjectByType<NavWorld>();
            worker.World = Object.FindAnyObjectByType<World>();
            worker.Treasury = Treasury.Of(side);
            Agents.Show(go);
            return worker;
        }

        public void ServerLabour(int role)
        {
            if (!_character.Alive) return;
            var side = _character.Faction;
            var crew = Crew(side);
            if (role < 0)
            {
                var deal = Deals.HireLabourer(_character.Kit, Treasury.Of(side), crew.Count);
                if (!deal.Ok)
                {
                    if (_combat != null && !string.IsNullOrEmpty(deal.Refusal)) _combat.Tell(deal.Refusal);
                    return;
                }
                SpawnLabourer(side, LabourerRole.Lumberjack, crew.Count);
                return;
            }
            if (crew.Count == 0)
            {
                if (_combat != null) _combat.Tell("батраков нет — сначала найми");
                return;
            }
            var wanted = (LabourerRole)Mathf.Clamp(role, 0, LabourerStats.RoleNames.Length - 1);
            var counts = new int[LabourerStats.RoleNames.Length];
            foreach (var worker in crew) counts[(int)worker.Brain.Role]++;
            int busiest = -1, most = 0;
            for (int r = 0; r < counts.Length; r++)
                if (r != (int)wanted && counts[r] > most)
                {
                    most = counts[r];
                    busiest = r;
                }
            if (busiest < 0)
            {
                if (_combat != null) _combat.Tell("все батраки уже " + LabourerStats.RoleNames[(int)wanted]);
                return;
            }
            foreach (var worker in crew)
                if ((int)worker.Brain.Role == busiest)
                {
                    worker.Brain.SetRole(wanted);
                    return;
                }
        }

        void Begin(BuildingKind kind)
        {
            Kind = kind;
            Placing = true;
            if (_ghost != null) Destroy(_ghost.gameObject);
            var box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            box.name = "Призрак: " + Res.BuildingNames[(int)kind];
            Destroy(box.GetComponent<Collider>());
            var size = Res.BuildingSize(kind).ToUnity();
            box.transform.localScale = new Vector3(size.x, Mathf.Min(size.y, 1.2f), size.z);
            _ghost = box.transform;
        }

        void Stop()
        {
            Placing = false;
            if (_ghost != null) Destroy(_ghost.gameObject);
            _ghost = null;
        }

        void OnDestroy()
        {
            Stop();
            StopRoute();
        }

        /// Куда смотрит игрок: сверху — под курсор, из боя — под прицел.
        void Aim()
        {
            var rig = Object.FindAnyObjectByType<CameraRig>();
            if (rig == null || rig.Camera == null) return;
            Ray ray;
            var mouse = UnityEngine.InputSystem.Mouse.current;
            if (GameMode.Strategy && mouse != null) ray = rig.Camera.ScreenPointToRay(mouse.position.ReadValue());
            else ray = new Ray(rig.transform.position, rig.transform.forward);
            RaycastHit hit;
            if (!Physics.Raycast(ray, out hit, Placement.PickDistance, HitZone.WorldMask, QueryTriggerInteraction.Ignore)) return;
            _point = hit.point.ToCore();
            float top;
            _valid = Fits(Kind, _point, out top) && (!Res.IsElfHouse(Kind) || _point.FlatDistance(_character.Feet) <= Deals.ElfBuildReach);
            var size = Res.BuildingSize(Kind).ToUnity();
            _ghost.position = new Vector3(_point.X, top + Mathf.Min(size.y, 1.2f) * 0.5f, _point.Z);
            _ghost.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of(_valid ? "ghost_ok" : "ghost_bad");
        }

        /// Годится ли место: земля пятью лучами (перепад не больше ступени) и
        /// зазор до стоящих построек. top — самая высокая точка под пятном.
        public static bool Fits(BuildingKind kind, V3 point, out float top)
        {
            var probes = Placement.Probes(point, kind);
            var heights = new float?[probes.Length];
            top = point.Y;
            float best = float.MinValue;
            for (int i = 0; i < probes.Length; i++)
            {
                RaycastHit hit;
                var from = probes[i].ToUnity() + Vector3.up * 80f;
                if (Physics.Raycast(from, Vector3.down, out hit, 200f, HitZone.WorldMask, QueryTriggerInteraction.Ignore))
                {
                    heights[i] = hit.point.y;
                    best = Mathf.Max(best, hit.point.y);
                }
            }
            if (best > float.MinValue) top = best;
            return Placement.GroundFits(heights) && Placement.Clear(point, kind, Standing());
        }

        static List<KeyValuePair<BuildingKind, V3>> Standing()
        {
            var list = new List<KeyValuePair<BuildingKind, V3>>();
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive) list.Add(new KeyValuePair<BuildingKind, V3>(building.State.Kind, building.At));
            }
            return list;
        }

        /// Заявка у хоста: всё заново по своей копии мира.
        public void ServerBuild(BuildingKind kind, V3 point)
        {
            if (!_character.Alive) return;
            float top;
            bool spotOk = Fits(kind, point, out top);
            int elfHouses = 0, elves = 0;
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && Res.IsElfHouse(building.State.Kind) && building.Side == (int)Faction.Elves) elfHouses++;
                var player = actor as PlayerCharacter;
                if (player != null && player.Faction == Faction.Elves) elves++;
            }
            var deal = Deals.Build(_character.Kit, Treasury.Of(_character.Faction), kind, spotOk,
                point.FlatDistance(_character.Feet), elfHouses, Respawn.ElfHouseLimit(elves));
            if (!deal.Ok)
            {
                if (_combat != null && !string.IsNullOrEmpty(deal.Refusal)) _combat.Tell(deal.Refusal);
                return;
            }
            var nav = Object.FindAnyObjectByType<NavWorld>();
            BuildingActor.Spawn(kind, _character.Faction, new V3(point.X, top, point.Z), false, nav);
        }
    }
}
