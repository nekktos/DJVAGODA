// Распорядитель стражи на посту и служба стражей (перенос commander.gd).
// Правила службы — ServiceRecord и CommanderPost ядра; здесь — тело на посту,
// засчитывание делом по событиям мира и доклад (Shop, E у распорядителя).
//
// Тело — боец-«чемпион» стражи у помоста: его убивают, через три минуты он
// снова на посту. Пока лежит — докладывать и принимать командование некому.
// Считает хост; книжку стража владельцу везёт NetPlayer.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Commander : MonoBehaviour
    {
        public static Commander Instance { get; private set; }

        public readonly CommanderPost Post = new CommanderPost();
        UnitAgent _body;
        bool _started;
        readonly Dictionary<int, bool> _wasAlive = new Dictionary<int, bool>();

        void Awake()
        {
            Instance = this;
            Actor.Killed += OnKilled;
            CaravanActor.Home += OnCaravanHome;
            CaravanActor.Lost += OnCaravanLost;
        }

        void OnDestroy()
        {
            Actor.Killed -= OnKilled;
            CaravanActor.Home -= OnCaravanHome;
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

        /// Где стоит распорядитель: живое тело, а не пустой помост.
        public V3? BodyAt { get { return _body != null && _body.Alive ? _body.At : (V3?)null; } }

        public bool InRange(V3 point)
        {
            var at = BodyAt;
            return at.HasValue && at.Value.FlatDistance(point) <= Orders.TalkRange;
        }

        void Update()
        {
            if (!Running) return;
            if (!_started)
            {
                _started = true;
                SpawnBody();
            }
            if (Post.OnDuty && (_body == null || !_body.Alive))
            {
                _body = null;
                Post.OnDied();
                Say("Распорядитель стражи пал. Приказы и повышение недоступны.");
            }
            if (Post.Tick(Time.deltaTime))
            {
                SpawnBody();
                Say("Распорядитель стражи вернулся на пост.");
            }
            foreach (var guard in Guards()) TickGuard(guard, Time.deltaTime);
        }

        void SpawnBody()
        {
            var go = Agents.Make(AgentRole.Champion, Faction.Guard, CommanderPost.Position + new V3(0f, 0.5f, 0f), "Распорядитель стражи");
            var unit = go.AddComponent<UnitAgent>();
            unit.Setup(UnitKind.Swordsman, (int)Faction.Guard, 0, CommanderPost.Position, CommanderPost.Leash);
            unit.Champion = true;
            unit.Nav = Object.FindAnyObjectByType<NavWorld>();
            Agents.Show(go);
            _body = unit;
        }

        static void Say(string text)
        {
            if (MatchGoals.Instance != null) MatchGoals.Instance.Announce(text);
        }

        static void Tell(PlayerCharacter guard, string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            var combat = guard.GetComponent<PlayerCombat>();
            if (combat != null) combat.Tell(text);
        }

        static List<PlayerCharacter> Guards()
        {
            var list = new List<PlayerCharacter>();
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player != null && player.Faction == Faction.Guard) list.Add(player);
            }
            return list;
        }

        void TickGuard(PlayerCharacter guard, float delta)
        {
            bool was;
            if (!_wasAlive.TryGetValue(guard.Id, out was)) was = true;
            _wasAlive[guard.Id] = guard.Alive;
            var record = guard.Service;
            if (was && !guard.Alive) Tell(guard, record.OnDeath());
            if (!guard.Alive || !record.Order.HasValue) return;
            var at = guard.Feet;
            var goals = MatchGoals.Instance;
            bool palaceOurs = goals == null || goals.State.PalaceOwner == Faction.Guard;
            record.TickHold(delta, at.FlatDistance(MatchState.Palace) <= MatchState.CaptureRadius, palaceOurs);
            Tell(guard, record.TickRaid(at.FlatDistance(Orders.RaidPoint) <= Orders.RaidRadius, InRange(at)));
            foreach (var mine in MapLayout.Mines)
            {
                if (mine.At.FlatDistance(at) > Orders.MineRadius) continue;
                record.TickMine(delta, true, HostilesNear(Faction.Guard, mine.At, Orders.MineRadius));
                break;
            }
            foreach (var actor in Actor.All)
            {
                var cart = actor as CaravanActor;
                if (cart == null || cart.Side != (int)Faction.Guard || cart.Trip == null || cart.Trip.State != CaravanState.ToHome) continue;
                if (cart.At.FlatDistance(at) > Orders.EscortRadius) continue;
                record.TickEscort(delta, true);
                break;
            }
        }

        /// Живые враги стороны (персонажи и бойцы) у точки.
        public static int HostilesNear(Faction side, V3 point, float radius)
        {
            int count = 0;
            foreach (var actor in Actor.All)
            {
                if (actor == null || !actor.Alive || actor is BuildingActor || actor is CaravanActor) continue;
                if (!Factions.Hostile((int)side, actor.Side)) continue;
                if (actor.At.FlatDistance(point) <= radius) count++;
            }
            return count;
        }

        /// Обоз стражи разбит или ограблен: все враги рядом — грабители, на них погоня.
        void Robbed(V3 at)
        {
            var hostiles = new List<KeyValuePair<int, V3>>();
            foreach (var actor in Actor.All)
                if (actor != null && actor.Alive && !(actor is BuildingActor) && Factions.Hostile((int)Faction.Guard, actor.Side))
                    hostiles.Add(new KeyValuePair<int, V3>(actor.Id, actor.At));
            Post.OnCaravanLost(at, hostiles);
        }

        /// Обоз остановлен игроком: увёл лошадей, перехватил, разграбил.
        void OnCaravanLost(CaravanActor cart, Faction owner, PlayerCharacter by)
        {
            if (owner == Faction.Guard) Robbed(cart.At);
            // Перехват и разграбление стражем засчитываются как «перехватить
            // караван»; уведённые лошади — нет: обоз ещё стоит.
            if (by != null && by.Faction == Faction.Guard && (!cart.Alive || cart.Side == (int)Faction.Guard))
                by.Service.OnCaravanDestroyed(owner);
        }

        void OnKilled(Actor victim, Actor source)
        {
            if (victim == null) return;
            var cart = victim as CaravanActor;
            if (cart != null && cart.Side == (int)Faction.Guard) Robbed(cart.At);
            var guard = source as PlayerCharacter;
            if (guard == null || guard.Faction != Faction.Guard) return;
            var record = guard.Service;
            var building = victim as BuildingActor;
            if (building != null)
            {
                record.OnBuildingDown((Faction)building.Side, building.State.Kind);
                return;
            }
            if (cart != null)
            {
                record.OnCaravanDestroyed((Faction)cart.Side);
                return;
            }
            if (victim.Side < 0 || victim.Side >= Factions.Count) return;
            var player = victim as PlayerCharacter;
            record.OnKill((Faction)victim.Side, player != null && player.Kit.IsLeader,
                victim.At.FlatDistance(MatchState.Palace) <= Orders.DefendRadius, Post.IsRobber(victim.Id));
        }

        void OnCaravanHome(CaravanActor cart)
        {
            if (cart.Side != (int)Faction.Guard) return;
            foreach (var guard in Guards()) Tell(guard, guard.Service.OnCaravanHome());
        }

        bool Possible(OrderKind kind)
        {
            switch (kind)
            {
                case OrderKind.Hunt:
                    return Post.AnyRobberAlive(id =>
                    {
                        var actor = Actor.ById(id);
                        return actor != null && actor.Alive;
                    });
                case OrderKind.Field:
                    foreach (var actor in Actor.All)
                    {
                        var building = actor as BuildingActor;
                        if (building != null && building.Alive && building.Side == (int)Faction.Villain && building.State.Kind == BuildingKind.Farm)
                            return true;
                    }
                    return false;
            }
            return true;
        }

        static bool GuardHasLeader()
        {
            foreach (var guard in Guards()) if (guard.Alive && guard.Kit.IsLeader) return true;
            return false;
        }

        /// Доклад (у хоста): первый приказ, сдача выполненного с наградой, следующий.
        public void Report(PlayerCharacter guard)
        {
            if (guard.Faction != Faction.Guard || !InRange(guard.Feet)) return;
            var goals = MatchGoals.Instance;
            bool villainAlive = goals == null || !goals.State.LeaderDown[(int)Faction.Villain];
            Tell(guard, guard.Service.Report(Treasury.Of(Faction.Guard), villainAlive, Possible));
        }

        /// Принять командование: стройка, наём, вид сверху — и смерть без возврата.
        public void Promote(PlayerCharacter guard)
        {
            if (guard.Faction != Faction.Guard || !InRange(guard.Feet)) return;
            string text = guard.Service.Promote(guard.Alive, Post.OnDuty, GuardHasLeader());
            if (!guard.Service.IsLeader)
            {
                Tell(guard, text);
                return;
            }
            guard.Kit.IsLeader = true;
            Say(text);
        }
    }
}
