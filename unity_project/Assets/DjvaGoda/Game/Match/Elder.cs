// Старейшина эльфов и задания (перенос elder.gd). Правила — ElfTaskRecord
// ядра; здесь — тело в поселении, засчитывание делом и доклад (Shop, E у
// старейшины). Тело встаёт через три минуты после гибели и в счёт живых
// эльфов не идёт (иначе эльфы не выбыли бы никогда). Считает хост.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Elder : MonoBehaviour
    {
        public static Elder Instance { get; private set; }

        UnitAgent _body;
        bool _started;
        float _respawnLeft;

        void Awake()
        {
            Instance = this;
            Actor.Killed += OnKilled;
            CaravanActor.Lost += OnCaravanLost;
        }

        void OnDestroy()
        {
            Actor.Killed -= OnKilled;
            CaravanActor.Lost -= OnCaravanLost;
            if (Instance == this) Instance = null;
        }

        static bool Running
        {
            get
            {
                var goals = MatchGoals.Instance;
                var net = Unity.Netcode.NetworkManager.Singleton;
                if (net != null && net.IsListening) return net.IsServer;
                return goals != null && goals.RunWithoutNetwork;
            }
        }

        public V3? BodyAt { get { return _body != null && _body.Alive ? _body.At : (V3?)null; } }

        public bool InRange(V3 point)
        {
            var at = BodyAt;
            return at.HasValue && at.Value.FlatDistance(point) <= ElfTasks.TalkRange;
        }

        void Update()
        {
            if (!Running) return;
            if (!_started)
            {
                _started = true;
                SpawnBody();
            }
            if (_body != null && !_body.Alive)
            {
                _body = null;
                _respawnLeft = ElfTaskRecord.ElderRespawn;
                Say("Старейшина эльфов пал. Задания недоступны.");
            }
            if (_body == null && _respawnLeft > 0f)
            {
                _respawnLeft -= Time.deltaTime;
                if (_respawnLeft <= 0f)
                {
                    SpawnBody();
                    Say("Старейшина эльфов вернулся в поселение.");
                }
            }
            foreach (var actor in Actor.All)
            {
                var elf = actor as PlayerCharacter;
                if (elf != null && elf.Faction == Faction.Elves && elf.Alive && elf.Tasks.Task.HasValue) Tick(elf, Time.deltaTime);
            }
        }

        void SpawnBody()
        {
            var go = Agents.Make(AgentRole.Swordsman, Faction.Elves, ElfTaskRecord.ElderPosition + new V3(0f, 0.5f, 0f), "Старейшина эльфов");
            var unit = go.AddComponent<UnitAgent>();
            unit.Setup(UnitKind.Swordsman, (int)Faction.Elves, 0, ElfTaskRecord.ElderPosition, CommanderPost.Leash);
            unit.Champion = true;
            unit.Nav = Object.FindAnyObjectByType<NavWorld>();
            Agents.Show(go);
            _body = unit;
        }

        static void Say(string text)
        {
            if (MatchGoals.Instance != null) MatchGoals.Instance.Announce(text);
        }

        static void Tell(PlayerCharacter elf, string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            var combat = elf.GetComponent<PlayerCombat>();
            if (combat != null) combat.Tell(text);
        }

        static void Tick(PlayerCharacter elf, float delta)
        {
            var record = elf.Tasks;
            var at = elf.Feet;
            V3? place = null;
            if (record.Task == ElfTaskKind.Mine)
            {
                foreach (var mine in MapLayout.Mines) if (mine.At.FlatDistance(at) <= ElfTasks.HoldRadius) place = mine.At;
            }
            else if (record.Task == ElfTaskKind.Reclaim)
            {
                foreach (var hamlet in MapLayout.Hamlets) if (hamlet.FlatDistance(at) <= ElfTasks.HoldRadius) place = hamlet;
            }
            if (place.HasValue) record.TickHold(delta, true, Commander.HostilesNear(Faction.Elves, place.Value, ElfTasks.HoldRadius));
            record.TickHorse(elf.Mounted && at.FlatDistance(Factions.Spawn[(int)Faction.Elves]) <= ElfTasks.VillageRadius);
        }

        /// Засада: эльф увёл лошадей, разграбил или перехватил чужой обоз.
        static void OnCaravanLost(CaravanActor cart, Faction owner, PlayerCharacter by)
        {
            if (by != null && by.Faction == Faction.Elves) by.Tasks.OnCaravanHit(owner);
        }

        static void OnKilled(Actor victim, Actor source)
        {
            var elf = source as PlayerCharacter;
            if (elf == null || elf.Faction != Faction.Elves || victim == null) return;
            var cart = victim as CaravanActor;
            if (cart != null)
            {
                elf.Tasks.OnCaravanHit((Faction)cart.Side);
                return;
            }
            if (victim is BuildingActor || victim.Side < 0 || victim.Side >= Factions.Count) return;
            var player = victim as PlayerCharacter;
            elf.Tasks.OnKill((Faction)victim.Side, victim is LabourerAgent, player != null && player.Kit.IsLeader);
        }

        /// Доклад (у хоста): первое задание, сдача выполненного с наградой, следующее.
        public void Report(PlayerCharacter elf)
        {
            if (elf.Faction != Faction.Elves || !InRange(elf.Feet)) return;
            bool labourers = false;
            bool heads = false;
            foreach (var actor in Actor.All)
            {
                if (actor == null || !actor.Alive) continue;
                if (actor is LabourerAgent && Factions.Hostile((int)Faction.Elves, actor.Side)) labourers = true;
                var player = actor as PlayerCharacter;
                if (player != null && player.Kit.IsLeader && Factions.Hostile((int)Faction.Elves, player.Side)) heads = true;
            }
            Tell(elf, elf.Tasks.Report(Treasury.Of(Faction.Elves), labourers, heads));
        }
    }
}
