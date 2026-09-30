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
        readonly List<ulong> _toSpawn = new List<ulong>();

        void Awake() { Instance = this; }

        static NetworkManager Net { get { return NetworkManager.Singleton; } }

        byte[] Request() { return Encoding.UTF8.GetBytes((int)Wanted + "|" + Profile); }

        public bool Host(ushort port)
        {
            Net.GetComponent<UnityTransport>().SetConnectionData("0.0.0.0", port);
            Net.NetworkConfig.ConnectionApproval = true;
            Net.ConnectionApprovalCallback = Approve;
            Net.OnClientDisconnectCallback += Left;
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
                var at = Respawn.SpawnPoint((Faction)faction, slot, false, new V3(0f, 0f, 0f), new List<V3>());
                var go = Instantiate(PlayerPrefab, at.ToUnity(), Quaternion.identity);
                var player = go.GetComponent<NetPlayer>();
                player.Side.Value = faction;
                player.Slot.Value = slot;
                go.GetComponent<NetworkObject>().SpawnAsPlayerObject(client);
            }
        }

        void Left(ulong client)
        {
            _faction.Remove(client);
            _slot.Remove(client);
            Status = "Игрок " + client + " отключился.";
        }
    }
}
