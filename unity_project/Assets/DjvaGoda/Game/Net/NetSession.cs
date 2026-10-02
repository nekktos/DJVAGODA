// Сессия: хост или подключение по IP (перенос network_manager.gd и спавна
// игроков из world.gd).
//
// Модель прав — как в Godot-версии, и она НЕ нарушается: клиент считает своё
// движение сам, всё остальное считает хост. Места на сторонах раздаёт хост
// при одобрении подключения (Lobby ядра): просил занятую — встаёт на первую
// свободную и слышит об этом.
using System.Collections.Generic;
using System.Text;
using DjvaGoda.Core;
using Unity.Netcode;
using Unity.Netcode.Transports.UTP;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class NetSession : MonoBehaviour
    {
        public static NetSession Instance { get; private set; }

        /// Префаб персонажа с NetworkObject, NetPlayer и PlayerCharacter (делается в редакторе).
        public GameObject PlayerPrefab;
        public Faction Wanted = Faction.Guard;
        public string Profile = "";
        public string Status { get; private set; }

        readonly Dictionary<ulong, int> _faction = new Dictionary<ulong, int>();
        readonly Dictionary<ulong, int> _slot = new Dictionary<ulong, int>();
        readonly Dictionary<ulong, string> _profile = new Dictionary<ulong, string>();
        readonly List<ulong> _toSpawn = new List<ulong>();

        void Awake() { Instance = this; }

        bool _prepared;

        // Зовётся из Host и Join, а не из Start: меню с ключом -join стартует
        // в своём Start, и порядок Start двух компонентов не задан.
        void Prepare()
        {
            if (_prepared) return;
            _prepared = true;
            // Подписка одна на сессию: Host/Join зовутся снова после выхода.
            Net.OnClientDisconnectCallback += Left;
            Net.OnClientConnectedCallback += Joined;
            // Одобрение входит в сверяемый NetworkConfig: включено только у хоста —
            // клиент шлёт неполный запрос и хост его сбрасывает («NetworkConfig mismatch»).
            Net.NetworkConfig.ConnectionApproval = true;
        }

        void OnDestroy()
        {
            if (NetworkManager.Singleton != null)
            {
                NetworkManager.Singleton.OnClientDisconnectCallback -= Left;
                NetworkManager.Singleton.OnClientConnectedCallback -= Joined;
            }
        }

        static NetworkManager Net { get { return NetworkManager.Singleton; } }

        byte[] Request() { return Encoding.UTF8.GetBytes((int)Wanted + "|" + Profile); }

        public bool Host(ushort port)
        {
            Prepare();
            Net.GetComponent<UnityTransport>().SetConnectionData("0.0.0.0", port);
            Net.ConnectionApprovalCallback = Approve;
            // Сам хост тоже проходит одобрение: его запрос — его сторона.
            Net.NetworkConfig.ConnectionData = Request();
            if (!Net.StartHost())
            {
                Status = "Не удалось открыть порт " + port + ". Порт занят другим процессом?";
                return false;
            }
            Status = "Хост запущен на порту " + port + ". Ждём игроков…";
            return true;
        }

        public bool Join(string address, ushort port)
        {
            address = address.Trim();
            if (address.Length == 0)
            {
                Status = "Пустой адрес хоста.";
                return false;
            }
            Prepare();
            Net.GetComponent<UnityTransport>().SetConnectionData(address, port);
            Net.NetworkConfig.ConnectionData = Request();
            if (!Net.StartClient())
            {
                Status = "Не удалось начать подключение к " + address + ":" + port + ".";
                return false;
            }
            Status = "Подключаемся к " + address + ":" + port + "…";
            return true;
        }

        public void Leave()
        {
            if (Net != null) Net.Shutdown();
            _faction.Clear();
            _slot.Clear();
            _profile.Clear();
            _toSpawn.Clear();
        }

        /// Одобрение на хосте: место и сторона по правилам ядра; мест нет — отказ.
        void Approve(NetworkManager.ConnectionApprovalRequest request, NetworkManager.ConnectionApprovalResponse response)
        {
            int wanted = (int)Faction.Guard;
            var text = Encoding.UTF8.GetString(request.Payload ?? new byte[0]);
            var parts = text.Split('|');
            int parsed;
            if (parts.Length > 0 && int.TryParse(parts[0], out parsed)) wanted = parsed;

            var humans = new int[Factions.Count];
            foreach (var side in _faction.Values) humans[side]++;
            int faction = Lobby.AssignFaction(wanted, humans);
            int slot = Lobby.NextFreeSlot(new List<int>(_slot.Values));
            if (faction < 0 || slot < 0)
            {
                response.Approved = false;
                response.Reason = "Сессия заполнена.";
                return;
            }
            _faction[request.ClientNetworkId] = faction;
            // Профиль — ключ сохранения: пустой у старого клиента — по номеру подключения.
            _profile[request.ClientNetworkId] = parts.Length > 1 && parts[1].Trim().Length > 0
                ? parts[1].Trim() : "игрок-" + request.ClientNetworkId;
            _slot[request.ClientNetworkId] = slot;
            if (faction != wanted) Status = Lobby.Redirected(wanted, faction);
            response.Approved = true;
            // Персонажа спавним сами — со стороной и местом, когда клиент подключится.
            response.CreatePlayerObject = false;
            response.Pending = false;
            _toSpawn.Add(request.ClientNetworkId);
        }

        void Update()
        {
            if (Net == null || !Net.IsServer || _toSpawn.Count == 0 || PlayerPrefab == null) return;
            foreach (var client in _toSpawn.ToArray())
            {
                if (!Net.ConnectedClients.ContainsKey(client)) continue;
                _toSpawn.Remove(client);
                int faction = _faction[client];
                int slot = _slot[client];
                // Метр над точкой — как одиночный загрузчик: капсула не встаёт в землю.
                var at = Respawn.SpawnPoint((Faction)faction, slot, false, new V3(0f, 0f, 0f), new List<V3>()) + new V3(0f, 1f, 0f);
                var go = Instantiate(PlayerPrefab, at.ToUnity(), Quaternion.identity);
                var player = go.GetComponent<NetPlayer>();
                player.AssignedSide = faction;
                player.AssignedSlot = slot;
                player.AssignedSpawn = at.ToUnity();
                go.GetComponent<PlayerCharacter>().Profile = _profile[client];
                go.GetComponent<NetworkObject>().SpawnAsPlayerObject(client);
            }
        }

        /// Герой под ИИ за свободную сторону (у хоста): тот же персонаж, что у
        /// игрока, во владении хоста; ведёт его HeroDriver.
        public PlayerCharacter SpawnAi(Faction side)
        {
            if (Net == null || !Net.IsServer || PlayerPrefab == null) return null;
            // Место — дальний ряд: живые игроки стороны встают в первые.
            var at = Respawn.SpawnPoint(side, Respawn.SlotRow - 1, false, new V3(0f, 0f, 0f), new List<V3>()) + new V3(0f, 1f, 0f);
            var go = Instantiate(PlayerPrefab, at.ToUnity(), Quaternion.identity);
            var player = go.GetComponent<NetPlayer>();
            player.AssignedSide = (int)side;
            player.AssignedSlot = Respawn.SlotRow - 1;
            player.AssignedSpawn = at.ToUnity();
            player.AssignedAi = true;
            go.GetComponent<NetworkObject>().Spawn();
            return go.GetComponent<PlayerCharacter>();
        }

        /// Люди за сторону (у хоста): одобренные подключения этой стороны.
        public int HumansOf(Faction side)
        {
            int count = 0;
            foreach (var pair in _faction)
                if (pair.Value == (int)side && Net.ConnectedClients.ContainsKey(pair.Key)) count++;
            return count;
        }

        /// Клиент вошёл в партию: строка состояния больше не «подключаемся».
        void Joined(ulong client)
        {
            if (Net.IsServer || client != Net.LocalClientId) return;
            Status = "Подключено к партии.";
        }

        void Left(ulong client)
        {
            if (!Net.IsServer)
            {
                // Клиента отключили (отказ хоста, хост ушёл, не дозвонились).
                string reason = Net.DisconnectReason;
                Status = string.IsNullOrEmpty(reason) ? "Связь с хостом потеряна." : reason;
                return;
            }
            _faction.Remove(client);
            _slot.Remove(client);
            Status = "Игрок " + client + " отключился.";
        }
    }
}
