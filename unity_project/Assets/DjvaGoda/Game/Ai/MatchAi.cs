// Стороны без людей и начало партии (перенос world.gd::_on_session_started,
// ai/garrison.gd, ai/hero.gd::_sync_heroes и подключения warband/steward).
//
// Старт (раз за партию): казарма и обжитое хозяйство стражи во дворце, три дома
// эльфов в кольце поселения — всё достроено и принадлежит СТОРОНЕ.
//
// Раз в 3 с — кто за какую сторону. Сторона, за которую никто не сел:
//   - гарнизон: до 4 мечников у базы; пополняется только дома (отряд в набеге
//     — павшие не восполняются, иначе отход не срабатывал бы никогда), эльфы —
//     только пока стоят их дома;
//   - отряд (WarbandDriver): гарнизон идёт в набег, на оборону и назад;
//   - злодей — распорядитель хозяйства (StewardDriver) из той же казны;
//   - злодей и эльфы — герой под ИИ (HeroDriver) теми же заявками, что игрок.
// Сел человек — гарнизон и герой уходят: живой не должен застать свою базу
// занятой кем-то другим. Только хост.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class MatchAi : MonoBehaviour
    {
        /// Казарма стражи и её хозяйство (Godot-версия, z — в осях Unity).
        public static readonly V3 GuardBarracks = new V3(332f, 6f, 238f);
        public static readonly KeyValuePair<BuildingKind, V3>[] GuardEstate =
        {
            new KeyValuePair<BuildingKind, V3>(BuildingKind.Storage, new V3(340f, 6f, 200f)),
            new KeyValuePair<BuildingKind, V3>(BuildingKind.Farm, new V3(220f, 6f, 210f)),
            new KeyValuePair<BuildingKind, V3>(BuildingKind.Farm, new V3(220f, 6f, 250f)),
            new KeyValuePair<BuildingKind, V3>(BuildingKind.House, new V3(380f, 6f, 240f)),
            new KeyValuePair<BuildingKind, V3>(BuildingKind.Stable, new V3(380f, 6f, 200f)),
        };

        /// Без сети (проверки) — включить вручную; по сети ИИ живёт только у хоста.
        public bool RunWithoutNetwork;

        bool _started;
        float _check;
        readonly List<UnitAgent>[] _garrisons = { new List<UnitAgent>(), new List<UnitAgent>(), new List<UnitAgent>() };
        readonly WarbandDriver[] _warbands = new WarbandDriver[Factions.Count];
        StewardDriver _steward;
        readonly PlayerCharacter[] _heroes = new PlayerCharacter[Factions.Count];

        public PlayerCharacter HeroOf(Faction side) { return _heroes[(int)side]; }
        public int GarrisonOf(Faction side) { return _garrisons[(int)side].Count; }
        public WarbandDriver WarbandOf(Faction side) { return _warbands[(int)side]; }

        bool Running
        {
            get
            {
                var net = NetworkManager.Singleton;
                if (net != null && net.IsListening) return net.IsServer;
                return RunWithoutNetwork;
            }
        }

        void Update()
        {
            if (!Running) return;
            if (!_started)
            {
                _started = true;
                Begin();
                _check = 0f;
            }
            _check -= Time.deltaTime;
            if (_check > 0f) return;
            _check = AiStats.GarrisonCheck;
            for (int side = 0; side < Factions.Count; side++) Sync((Faction)side);
        }

        NavWorld Nav { get { return Object.FindAnyObjectByType<NavWorld>(); } }

        /// Начало партии: то, что у сторон есть с первой минуты.
        void Begin()
        {
            var nav = Nav;
            BuildingActor.Spawn(BuildingKind.SwordBarracks, Faction.Guard, GuardBarracks, true, nav);
            foreach (var entry in GuardEstate) BuildingActor.Spawn(entry.Key, Faction.Guard, entry.Value, true, nav);
            foreach (var house in Respawn.ElfHousesStart) BuildingActor.Spawn(BuildingKind.ElfHouse, Faction.Elves, house, true, nav);
        }

        /// Люди за сторону: по сети — одобренные подключения, без сети — свой игрок.
        public static bool Occupied(Faction side)
        {
            var session = NetSession.Instance;
            var net = NetworkManager.Singleton;
            if (session != null && net != null && net.IsListening) return session.HumansOf(side) > 0;
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player != null && player.LocalControl && player.Faction == side) return true;
            }
            return false;
        }

        void Sync(Faction side)
        {
            int index = (int)side;
            _garrisons[index].RemoveAll(unit => unit == null || !unit.Alive);
            // Выбывшая сторона больше не пополняется: партия ушла дальше.
            if (MatchGoals.IsOut(side)) return;
            if (Occupied(side))
            {
                Disband(side);
                return;
            }
            Reinforce(side);
            if (_warbands[index] == null)
            {
                var band = new GameObject("Отряд ИИ: " + Factions.Names[index]).AddComponent<WarbandDriver>();
                band.transform.SetParent(transform, false);
                band.Side = side;
                band.Nav = Nav;
                _warbands[index] = band;
            }
            var driver = _warbands[index];
            foreach (var unit in _garrisons[index])
                if (!driver.Band.Contains(unit)) driver.Band.Add(unit);
            if (side == Faction.Villain && _steward == null)
            {
                _steward = new GameObject("Распорядитель ИИ: " + Factions.Names[index]).AddComponent<StewardDriver>();
                _steward.transform.SetParent(transform, false);
                _steward.Side = side;
                _steward.Treasury = Treasury.Of(side);
                _steward.Nav = Nav;
                _steward.World = Object.FindAnyObjectByType<World>();
                _steward.Warband = driver;
            }
            if ((side == Faction.Villain || side == Faction.Elves) && _heroes[index] == null) _heroes[index] = SpawnHero(side);
        }

        void Disband(Faction side)
        {
            int index = (int)side;
            foreach (var unit in _garrisons[index]) if (unit != null) Agents.Remove(unit.gameObject);
            _garrisons[index].Clear();
            if (_warbands[index] != null)
            {
                Destroy(_warbands[index].gameObject);
                _warbands[index] = null;
            }
            if (side == Faction.Villain && _steward != null)
            {
                Destroy(_steward.gameObject);
                _steward = null;
            }
            if (_heroes[index] != null)
            {
                var net = _heroes[index].GetComponent<NetworkObject>();
                if (net != null && net.IsSpawned) net.Despawn(true);
                else Destroy(_heroes[index].gameObject);
                _heroes[index] = null;
            }
        }

        /// Дополнить гарнизон до штата — только пока отряд дома.
        void Reinforce(Faction side)
        {
            int index = (int)side;
            var band = _warbands[index];
            if (band != null && band.Brain != null && band.Brain.State != WarbandState.Hold) return;
            if (side == Faction.Elves && !ElfHouseStands()) return;
            var home = Factions.Spawn[index];
            var nav = Nav;
            while (_garrisons[index].Count < AiStats.GarrisonSize)
            {
                int slot = _garrisons[index].Count;
                float angle = 2f * Mathf.PI * slot / AiStats.GarrisonSize;
                var spot = home + new V3(Mathf.Cos(angle) * 6f, 0.5f, -Mathf.Sin(angle) * 6f);
                var go = Agents.Make(AgentRole.Swordsman, side, spot, "Гарнизон: мечник");
                var unit = go.AddComponent<UnitAgent>();
                unit.Setup(UnitKind.Swordsman, index, slot, home, AiStats.GarrisonLeash);
                unit.Nav = nav;
                Agents.Show(go);
                _garrisons[index].Add(unit);
            }
        }

        static bool ElfHouseStands()
        {
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.State.Done && building.Side == (int)Faction.Elves
                    && Res.IsElfHouse(building.State.Kind)) return true;
            }
            return false;
        }

        /// Герой под ИИ: по сети — персонаж хоста (NetSession.SpawnAi), без сети — свой объект.
        PlayerCharacter SpawnHero(Faction side)
        {
            PlayerCharacter hero;
            var net = NetworkManager.Singleton;
            if (net != null && net.IsListening && NetSession.Instance != null) hero = NetSession.Instance.SpawnAi(side);
            else
            {
                var root = new GameObject("ИИ (" + Factions.Names[(int)side] + ")");
                var at = Respawn.SpawnPoint(side, Respawn.SlotRow - 1, false, new V3(0f, 0f, 0f), new List<V3>()) + new V3(0f, 1f, 0f);
                root.transform.position = at.ToUnity();
                Bootstrap.AddBody(root.transform, side);
                hero = root.AddComponent<PlayerCharacter>();
                hero.Faction = side;
                hero.LocalControl = false;
                hero.Kit.IsLeader = side == Faction.Villain;
                root.AddComponent<PlayerCombat>();
                root.AddComponent<PlayerSpells>();
                root.AddComponent<WeaponView>();
                root.AddComponent<Builder>();
                root.AddComponent<Shop>();
            }
            if (hero != null && hero.GetComponent<HeroDriver>() == null) hero.gameObject.AddComponent<HeroDriver>();
            return hero;
        }
    }
}
