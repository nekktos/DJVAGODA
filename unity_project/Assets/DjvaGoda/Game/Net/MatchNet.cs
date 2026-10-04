// Сетевое состояние партии, которое не принадлежит никому из игроков: казна
// сторон и исчерпанные источники добычи (поваленные деревья, выбитые камни).
// Объект стоит в сцене (in-scene NetworkObject) — он есть у всех с загрузки.
//
// Считает хост; клиентам — переменными. Исчерпанные — NetworkList: опоздавшему
// он приходит целиком, и тот убирает их у себя («опоздавшему досылают список
// поваленных» — правило Godot-версии).
//
// Без сети (проверки, одиночный загрузчик) хозяин — сама машина.
using System;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    /// Кошелёк стороны для клиентов.
    public struct WalletSync : INetworkSerializable, IEquatable<WalletSync>
    {
        public int C0, C1, C2, C3, C4, C5, S0, S1, S2, S3, S4, S5, CapC, CapS, Horses, HorsesOut;

        public void NetworkSerialize<T>(BufferSerializer<T> s) where T : IReaderWriter
        {
            s.SerializeValue(ref C0); s.SerializeValue(ref C1); s.SerializeValue(ref C2);
            s.SerializeValue(ref C3); s.SerializeValue(ref C4); s.SerializeValue(ref C5);
            s.SerializeValue(ref S0); s.SerializeValue(ref S1); s.SerializeValue(ref S2);
            s.SerializeValue(ref S3); s.SerializeValue(ref S4); s.SerializeValue(ref S5);
            s.SerializeValue(ref CapC); s.SerializeValue(ref CapS);
            s.SerializeValue(ref Horses); s.SerializeValue(ref HorsesOut);
        }

        public bool Equals(WalletSync o)
        {
            return C0 == o.C0 && C1 == o.C1 && C2 == o.C2 && C3 == o.C3 && C4 == o.C4 && C5 == o.C5
                && S0 == o.S0 && S1 == o.S1 && S2 == o.S2 && S3 == o.S3 && S4 == o.S4 && S5 == o.S5
                && CapC == o.CapC && CapS == o.CapS && Horses == o.Horses && HorsesOut == o.HorsesOut;
        }

        public static WalletSync Of(Wallet w)
        {
            var c = w.Carried.Amounts;
            var s = w.Stored.Amounts;
            return new WalletSync
            {
                C0 = c[0], C1 = c[1], C2 = c[2], C3 = c[3], C4 = c[4], C5 = c[5],
                S0 = s[0], S1 = s[1], S2 = s[2], S3 = s[3], S4 = s[4], S5 = s[5],
                CapC = w.Carried.Capacity, CapS = w.Stored.Capacity, Horses = w.Horses, HorsesOut = w.HorsesOut,
            };
        }

        public void Apply(Wallet w)
        {
            w.Carried.Amounts = new[] { C0, C1, C2, C3, C4, C5 };
            w.Stored.Amounts = new[] { S0, S1, S2, S3, S4, S5 };
            w.Carried.Capacity = CapC;
            w.Stored.Capacity = CapS;
            w.Horses = Horses;
            w.HorsesOut = HorsesOut;
        }
    }

    public class MatchNet : NetworkBehaviour
    {
        public static MatchNet Instance { get; private set; }

        public readonly NetworkVariable<WalletSync> VillainWallet = new NetworkVariable<WalletSync>();
        public readonly NetworkVariable<WalletSync> ElvesWallet = new NetworkVariable<WalletSync>();
        public readonly NetworkVariable<WalletSync> GuardWallet = new NetworkVariable<WalletSync>();
        /// Номера исчерпанных источников (Harvestable.Key).
        NetworkList<int> _gone;

        float _depositT;
        float _hungerT;

        void Awake()
        {
            Instance = this;
            _gone = new NetworkList<int>();
            // Новая сцена — новая партия: стартовый запас у всех; дальше
            // клиентам его перезапишет хост.
            Treasury.Reset();
            Mines.Reset();
        }

        NetworkVariable<WalletSync> WalletVar(int side)
        {
            return side == (int)Faction.Villain ? VillainWallet : side == (int)Faction.Elves ? ElvesWallet : GuardWallet;
        }

        /// Хозяин партии: хост в сети или машина без сети.
        public static bool Hosting
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net == null || !net.IsListening || net.IsServer;
            }
        }

        public override void OnNetworkSpawn()
        {
            _gone.OnListChanged += Changed;
            if (IsServer) return;
            foreach (var key in _gone) Remove(key);
            if (_gone.Count > 0) Debug.Log("[мир] исчерпанных источников при входе: " + _gone.Count + " — убраны у себя");
        }

        public override void OnNetworkDespawn() { _gone.OnListChanged -= Changed; }

        void Changed(NetworkListEvent<int> change)
        {
            // Хост убрал источник сам (Deplete); список — для клиентов.
            if (!IsServer && change.Type == NetworkListEvent<int>.EventType.Add) Remove(change.Value);
        }

        void Update()
        {
            if (IsSpawned && !IsServer)
            {
                for (int side = 0; side < Factions.Count; side++) WalletVar(side).Value.Apply(Treasury.Of(side));
                return;
            }
            if (!Hosting) return;
            if (IsSpawned)
                for (int side = 0; side < Factions.Count; side++) WalletVar(side).Value = WalletSync.Of(Treasury.Of(side));
            Mines.Tick(Time.deltaTime);
            _hungerT += Time.deltaTime;
            if (_hungerT >= Res.FeedInterval)
            {
                _hungerT = 0f;
                Feed();
            }
            _depositT += Time.deltaTime;
            if (_depositT >= Res.DepositInterval)
            {
                _depositT = 0f;
                Deposit();
            }
        }

        /// Ноша — в склад: живой персонаж у своего достроенного склада.
        static void Deposit()
        {
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player == null || !player.Alive) continue;
                var wallet = Treasury.Of(player.Faction);
                if (wallet.CarriedTotal() <= 0) continue;
                foreach (var other in Actor.All)
                {
                    var building = other as BuildingActor;
                    if (building == null || building.State.Kind != BuildingKind.Storage || !building.State.Done) continue;
                    if (building.Side != (int)player.Faction) continue;
                    if (building.At.FlatDistance(player.Feet) > Res.DepositRange) continue;
                    // Свою ношу игрок несёт сам — и опыт за неё его, а не вожака.
                    Experience.ForResources(player, wallet.Deposit());
                    break;
                }
            }
        }

        /// Кормёжка артелей (у хоста): каждая сторона кормит своих батраков из
        /// казны; не хватило на всех — не ест никто, голодные работают медленнее,
        /// с третьего пропуска умирают. Стороне — одна строка о беде.
        public static void Feed()
        {
            for (int side = 0; side < Factions.Count; side++)
            {
                var crew = Builder.Crew((Faction)side);
                if (crew.Count == 0) continue;
                var hunger = new int[crew.Count];
                for (int i = 0; i < crew.Count; i++) hunger[i] = crew[i].MissedMeals;
                var result = Hunger.Feed((Faction)side, Treasury.Of(side), hunger);
                for (int i = 0; i < crew.Count; i++)
                {
                    crew[i].MissedMeals = hunger[i];
                    crew[i].Hungry = hunger[i] > 0;
                    if (hunger[i] < Res.HungerFatal) continue;
                    var t = crew[i].transform;
                    Corpses.Spawn(t.position, t.eulerAngles.y, (int)AgentRole.Labourer, side, 0);
                    Agents.Remove(crew[i].gameObject);
                }
                if (string.IsNullOrEmpty(result.Message)) continue;
                Debug.Log("[голод] " + result.Message);
                foreach (var actor in Actor.All)
                {
                    var player = actor as PlayerCharacter;
                    if (player == null || (int)player.Faction != side) continue;
                    var combat = player.GetComponent<PlayerCombat>();
                    if (combat != null) combat.Tell(result.Message);
                }
            }
        }

        static readonly Color[] ChipColors =
        {
            new Color(0.45f, 0.30f, 0.16f), new Color(0.55f, 0.55f, 0.58f), new Color(0.85f, 0.70f, 0.20f),
            new Color(0.60f, 0.62f, 0.68f), new Color(0.75f, 0.60f, 0.30f), new Color(0.15f, 0.15f, 0.16f),
        };

        /// Удар по источнику (зовёт хост): стук и щепки — у всех.
        public static void Chips(Vector3 at, int resource)
        {
            var me = Instance;
            if (me != null && me.IsSpawned) me.ChipsRpc(at, resource);
            else ShowChips(at, resource);
        }

        [Rpc(SendTo.Everyone)]
        void ChipsRpc(Vector3 at, int resource) { ShowChips(at, resource); }

        static void ShowChips(Vector3 at, int resource)
        {
            bool wood = resource == (int)ResourceKind.Wood;
            Sfx.Play(wood ? SoundKind.HitWood : SoundKind.HitStone, at, 0.7f);
            Effects.Chips(at, ChipColors[Mathf.Clamp(resource, 0, ChipColors.Length - 1)]);
        }

        /// Павший лёг (рассылает хост, себе тоже).
        [Rpc(SendTo.Everyone)]
        public void CorpseRpc(Vector3 at, float yaw, int look, int side, int severed)
        {
            Corpses.Place(at, yaw, look, side, severed);
        }

        /// Источник исчерпан (зовёт хост): убрать у себя и сообщить всем.
        public static void Deplete(int key)
        {
            var me = Instance;
            if (me != null && me.IsSpawned && me.IsServer && !me._gone.Contains(key)) me._gone.Add(key);
            Remove(key);
        }

        static void Remove(int key)
        {
            if (key < Harvestable.PlanBase)
            {
                var world = UnityEngine.Object.FindAnyObjectByType<World>();
                if (world != null) world.Fell(key);
                return;
            }
            var source = Harvestable.Find(key);
            if (source != null) Destroy(source.gameObject);
        }
    }
}
