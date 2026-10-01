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

        public bool Placing { get; private set; }
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
            }
            else if (_character.Faction == Faction.Elves && GameInput.Pressed("build_elf_house"))
            {
                if (Placing) Stop();
                else Begin(BuildingKind.ElfHouse);
            }
            else if (Placing && !Res.IsElfHouse(Kind)) Stop();
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

        void OnDestroy() { Stop(); }

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
