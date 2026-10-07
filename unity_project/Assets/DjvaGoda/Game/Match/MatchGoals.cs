// Исход партии (перенос objective.gd и world.gd::absorb_guard): захват
// дворца, павшие вожаки, выбывание сторон, победа. Правила — MatchState ядра;
// здесь — снимок мира для них и объявления всем.
//
// Считает хост: кто стоит в круге дворца (живые персонажи, страж под злодеем
// считается за злодея), кто из вожаков пал и от чьей руки, раз в 2 с — кто
// выбыл. Клиентам — переменными и объявлениями (AnnounceRpc). Союз стражи со
// злодеем выставляет каждый пир по переменной.
//
// Партия идёт до последней стороны (GDD 9a); выбывание окончательно.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class MatchGoals : NetworkBehaviour
    {
        public static MatchGoals Instance { get; private set; }

        /// Сколько держать объявление на экране.
        public const float AnnounceSeconds = 8f;
        public const int FeedSize = 4;

        /// Без сети (проверки) — включить вручную: иначе пустой загрузчик
        /// без ИИ объявлял бы эльфов выбывшими на второй секунде.
        public bool RunWithoutNetwork;

        public readonly MatchState State = new MatchState();
        public readonly NetworkVariable<int> Owner = new NetworkVariable<int>((int)Faction.Guard);
        public readonly NetworkVariable<float> Progress = new NetworkVariable<float>();
        public readonly NetworkVariable<int> Claimant = new NetworkVariable<int>(-1);
        public readonly NetworkVariable<bool> Contested = new NetworkVariable<bool>();
        /// Биты: 0–2 — пал вожак, 3–5 — выбыла, 6–8 — победила, 9 — стража у злодея.
        public readonly NetworkVariable<int> Flags = new NetworkVariable<int>();

        /// Объявления: текст и когда показано.
        public readonly List<KeyValuePair<string, float>> Feed = new List<KeyValuePair<string, float>>();

        /// Кто последним добил участника: номер участника → сторона убийцы.
        readonly Dictionary<int, int> _killers = new Dictionary<int, int>();
        /// Первая проверка — не в первый кадр: старт партии (MatchAi.Begin) ставит дома эльфов.
        float _check = MatchState.CheckInterval;

        void Awake()
        {
            Instance = this;
            // Новая сцена — новая партия: союзы прошлой не переезжают.
            State.ApplyAlliances();
            Actor.Killed += NoteKill;
            gameObject.AddComponent<Commander>();
            gameObject.AddComponent<Elder>();
            gameObject.AddComponent<SaveGame>();
            gameObject.AddComponent<Experience>();
            gameObject.AddComponent<Sfx>();
            if (Cheats.Allowed) gameObject.AddComponent<DevConsole>();
        }

        public override void OnDestroy()
        {
            Actor.Killed -= NoteKill;
            if (Instance == this) Instance = null;
            Factions.Overlord[(int)Faction.Guard] = -1;
            base.OnDestroy();
        }

        public static bool IsOut(Faction side) { return Instance != null && Instance.State.Out[(int)side]; }

        /// Кто именно нанёс смертельный удар: место злодея занимает убийца.
        readonly Dictionary<int, int> _killerActors = new Dictionary<int, int>();
        readonly HashSet<int> _fallen = new HashSet<int>();

        void NoteKill(Actor victim, Actor source)
        {
            if (victim == null || source == null) return;
            _killers[victim.Id] = source.Side;
            _killerActors[victim.Id] = source.Id;
        }

        void Update()
        {
            var net = NetworkManager.Singleton;
            bool listening = net != null && net.IsListening;
            if (listening && !net.IsServer)
            {
                if (IsSpawned) Read();
                State.ApplyAlliances();
                return;
            }
            if (!listening && !RunWithoutNetwork) return;
            foreach (var text in State.TickCapture(Time.deltaTime, Present())) Announce(text);
            if (State.GuardAbsorbed && !_absorbed) Absorb();
            Leaders();
            _check -= Time.deltaTime;
            if (_check <= 0f)
            {
                _check = MatchState.CheckInterval;
                foreach (var text in State.CheckVictories(Snapshots())) Announce(text);
            }
            if (IsSpawned) Write();
        }

        void Write()
        {
            Owner.Value = (int)State.PalaceOwner;
            Progress.Value = State.CaptureProgress;
            Claimant.Value = State.Claimant;
            Contested.Value = State.Contested;
            int flags = (State.GuardAbsorbed ? 1 << 9 : 0) | (State.VillainAbsorbed ? 1 << 10 : 0);
            for (int f = 0; f < Factions.Count; f++)
            {
                if (State.LeaderDown[f]) flags |= 1 << f;
                if (State.Out[f]) flags |= 1 << (3 + f);
                if (State.Victors[f]) flags |= 1 << (6 + f);
            }
            Flags.Value = flags;
        }

        void Read()
        {
            State.PalaceOwner = (Faction)Owner.Value;
            State.CaptureProgress = Progress.Value;
            State.Claimant = Claimant.Value;
            State.Contested = Contested.Value;
            int flags = Flags.Value;
            for (int f = 0; f < Factions.Count; f++)
            {
                State.LeaderDown[f] = (flags & (1 << f)) != 0;
                State.Out[f] = (flags & (1 << (3 + f))) != 0;
                State.Victors[f] = (flags & (1 << (6 + f))) != 0;
            }
            State.GuardAbsorbed = (flags & (1 << 9)) != 0;
            State.VillainAbsorbed = (flags & (1 << 10)) != 0;
        }

        /// Какие стороны стоят в круге дворца: живые персонажи, по сюзерену.
        static List<Faction> Present()
        {
            var found = new List<Faction>();
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player == null || !player.Alive) continue;
                if (player.Feet.FlatDistance(MatchState.Palace) > MatchState.CaptureRadius) continue;
                var side = (Faction)Factions.Root((int)player.Faction);
                if (!found.Contains(side)) found.Add(side);
            }
            return found;
        }

        /// Вожак пал — окончательно (он не встаёт: Respawn.Verdict).
        void Leaders()
        {
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player == null || player.Alive || !player.Kit.IsLeader) continue;
                if (State.LeaderDown[(int)player.Faction]) continue;
                int killer;
                if (!_killers.TryGetValue(player.Id, out killer)) killer = -1;
                if (_fallen.Contains(player.Id)) continue;
                if (player.Faction == Faction.Villain && VillainFell(player))
                {
                    // Исход решён раз и навсегда: тело прежнего злодея больше не считаем.
                    _fallen.Add(player.Id);
                    continue;
                }
                var text = State.ReportLeaderDown(player.Faction, killer);
                if (text != null) Announce(text);
                foreach (var more in State.CheckVictories(Snapshots())) Announce(more);
            }
        }

        SideSnapshot[] Snapshots()
        {
            var sides = new SideSnapshot[Factions.Count];
            var ai = Object.FindAnyObjectByType<MatchAi>();
            for (int f = 0; f < Factions.Count; f++)
            {
                sides[f].HasPlayers = MatchAi.Occupied((Faction)f);
                var hero = ai != null ? ai.HeroOf((Faction)f) : null;
                sides[f].AiHeroExists = hero != null;
                sides[f].AiHeroAlive = hero != null && hero.Alive;
            }
            foreach (var actor in Actor.All)
            {
                if (actor == null || !actor.Alive || actor.Side < 0 || actor.Side >= Factions.Count) continue;
                var building = actor as BuildingActor;
                if (building != null)
                {
                    var kind = building.State.Kind;
                    if (kind == BuildingKind.SwordBarracks || kind == BuildingKind.ArcherBarracks) sides[actor.Side].HasBarracks = true;
                    if (Res.IsElfHouse(kind)) sides[actor.Side].ElfHouses++;
                    continue;
                }
                var unit = actor as UnitAgent;
                if (actor.Side == (int)Faction.Elves && (actor is PlayerCharacter || (unit != null && !unit.Champion))) sides[actor.Side].LivingElves++;
            }
            return sides;
        }

        /// Злодей пал от руки игрока (ответ автора от 07.10): рядовой стражник
        /// или эльф занимает его место, командир стражи забирает его владения
        /// страже. true — исход обработан здесь.
        bool VillainFell(PlayerCharacter villain)
        {
            int killerId;
            var killer = _killerActors.TryGetValue(villain.Id, out killerId) ? Actor.ById(killerId) as PlayerCharacter : null;
            if (killer == null || !killer.Alive) return false;
            bool human = killer.GetComponent<HeroDriver>() == null;
            switch (MatchState.VillainFallBy(killer.Faction, human, killer.Kit.IsLeader))
            {
                case MatchState.VillainFall.Usurped:
                    Usurp(killer);
                    return true;
                case MatchState.VillainFall.Absorbed:
                    var said = State.AbsorbVillain();
                    if (said != null) Announce(said);
                    HandOverVillain();
                    foreach (var more in State.CheckVictories(Snapshots())) Announce(more);
                    return true;
                default:
                    return false;
            }
        }

        /// Убийца встаёт на место злодея: его сторона, вожак, хозяйство и казна
        /// злодея — его. Свой отряд идёт за ним. Прежний вожак мёртв навсегда.
        void Usurp(PlayerCharacter killer)
        {
            var was = killer.Faction;
            foreach (var unit in Squads.Of(killer))
            {
                unit.Brain.Side = (int)Faction.Villain;
                unit.Side = (int)Faction.Villain;
            }
            killer.ChangeFaction(Faction.Villain);
            killer.Kit.IsLeader = true;
            var net = killer.GetComponent<NetPlayer>();
            if (net != null && net.IsSpawned)
            {
                net.Side.Value = (int)Faction.Villain;
                if (NetSession.Instance != null) NetSession.Instance.Reassign(net.OwnerClientId, Faction.Villain);
            }
            // Злодей снова ведом — не «пал».
            State.LeaderDown[(int)Faction.Villain] = false;
            Announce(Factions.NameOf(was) + ": " + killer.name + " сразил злодея и занял его место");
        }

        /// Владения злодея — страже: постройки, казна, лошади, батраки и бойцы.
        void HandOverVillain()
        {
            foreach (var actor in Actor.All)
            {
                if (actor == null || actor.Side != (int)Faction.Villain) continue;
                var building = actor as BuildingActor;
                if (building != null)
                {
                    building.State.Side = Faction.Guard;
                    building.Side = (int)Faction.Guard;
                    continue;
                }
                var worker = actor as LabourerAgent;
                if (worker != null && worker.Brain != null)
                {
                    worker.Brain.Side = Faction.Guard;
                    worker.Side = (int)Faction.Guard;
                    continue;
                }
                var unit = actor as UnitAgent;
                if (unit != null && unit.Brain != null && !unit.Champion)
                {
                    unit.Brain.Side = (int)Faction.Guard;
                    unit.Side = (int)Faction.Guard;
                }
            }
            MoveTreasury(Faction.Villain, Faction.Guard);
        }

        /// Казна стороны — другой: склад, ноша, свободные лошади.
        static void MoveTreasury(Faction fromSide, Faction intoSide)
        {
            var from = Treasury.Of(fromSide);
            var into = Treasury.Of(intoSide);
            into.RaiseCapacity(from.Stored.Capacity);
            for (int i = 0; i < Res.Count; i++)
            {
                int amount = from.GetAmount(i);
                if (amount <= 0) continue;
                int left = amount - into.AddStored(i, amount);
                if (left > 0)
                {
                    into.Carried.Capacity = Mathf.Max(into.Carried.Capacity, into.Carried.GetAmount(i) + left);
                    into.Add(i, left);
                }
            }
            into.Horses += from.HorsesFree;
            from.Carried.Amounts = Res.Empty();
            from.Stored.Amounts = Res.Empty();
            from.Horses = from.HorsesOut;
        }

        bool _absorbed;

        /// Дворец взят злодеем: постройки стражи и её казна — его. Бойцы
        /// стражи остаются в своих цветах, но служат ему (союз в Factions).
        void Absorb()
        {
            _absorbed = true;
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building == null || building.Side != (int)Faction.Guard) continue;
                building.State.Side = Faction.Villain;
                building.Side = (int)Faction.Villain;
            }
            MoveTreasury(Faction.Guard, Faction.Villain);
        }

        /// Объявить всем (хост).
        public void Announce(string text)
        {
            Debug.Log("[цель] " + text);
            Show(text);
            if (IsSpawned) AnnounceRpc(text);
        }

        [Rpc(SendTo.NotServer)]
        void AnnounceRpc(string text)
        {
            Debug.Log("[цель] у себя: " + text);
            Show(text);
        }

        void Show(string text)
        {
            Feed.Add(new KeyValuePair<string, float>(text, Time.time));
            Sfx.PlayFlat(SoundKind.Notice, 0.6f);
            while (Feed.Count > FeedSize) Feed.RemoveAt(0);
        }
    }
}
