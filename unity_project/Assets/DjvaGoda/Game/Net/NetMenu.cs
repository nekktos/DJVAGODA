// Меню сессии (перенос главного меню Godot-версии, пока без картинок):
// сторона, «Создать игру» или «Подключиться» по адресу, строка состояния.
//
// Для прогонов без мыши — ключи командной строки:
//   -host [порт]            создать игру
//   -join адрес [порт]      подключиться
//   -side 0|1|2             сторона (Злодей, Лесные эльфы, Охрана дворца)
//   -walk                   свой персонаж идёт вперёд без ввода (проверка
//                           движения по сети)
//   -attack N               взять оружие из слота N (1..4) и держать удар
//                           (проверка боя по сети)
//   -cast N                 произносить заклинание из слота N (1..3), как
//                           только оно готово
//   -shot путь [секунды]    снимок экрана через N секунд после входа в
//                           партию (по умолчанию 8) — проверка вида у клиента
using System;
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(NetSession))]
    public class NetMenu : MonoBehaviour
    {
        public const ushort DefaultPort = 24545;

        NetSession _session;
        string _address = "127.0.0.1";
        string _port = DefaultPort.ToString();

        const string ProfileKey = "profile";

        void Awake()
        {
            _session = GetComponent<NetSession>();
            // Профиль — ключ сохранения у хоста: одно имя на этой машине, пока его не сменят.
            string profile = PlayerPrefs.GetString(ProfileKey, "");
            if (profile.Length == 0)
            {
                profile = "игрок-" + UnityEngine.Random.Range(1000, 9999);
                PlayerPrefs.SetString(ProfileKey, profile);
                PlayerPrefs.Save();
            }
            _session.Profile = profile;
        }

        void Start()
        {
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-side" && i + 1 < args.Length)
                {
                    int side;
                    if (int.TryParse(args[i + 1], out side) && side >= 0 && side < Factions.Count) _session.Wanted = (Faction)side;
                }
            }
            _walk = Array.IndexOf(args, "-walk") >= 0;
            int attack = Array.IndexOf(args, "-attack");
            if (attack >= 0 && attack + 1 < args.Length) int.TryParse(args[attack + 1], out _attackSlot);
            int cast = Array.IndexOf(args, "-cast");
            if (cast >= 0 && cast + 1 < args.Length) int.TryParse(args[cast + 1], out _castSlot);
            int shot = Array.IndexOf(args, "-shot");
            if (shot >= 0 && shot + 1 < args.Length)
            {
                _shotPath = args[shot + 1];
                float delay;
                if (shot + 2 < args.Length && float.TryParse(args[shot + 2], System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out delay)) _shotDelay = delay;
            }
            // -deals "вид:арг@сек,…" — заявки сделок по расписанию после входа
            // (проверки вдвоём: подбор, верстак, прокачка у клиента).
            int deals = Array.IndexOf(args, "-deals");
            if (deals >= 0 && deals + 1 < args.Length)
                foreach (var item in args[deals + 1].Split(','))
                {
                    var parts = item.Split('@', ':');
                    int kind, arg;
                    float at;
                    if (parts.Length == 3 && int.TryParse(parts[0], out kind) && int.TryParse(parts[1], out arg)
                        && float.TryParse(parts[2], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out at))
                        _deals.Add(new KeyValuePair<float, Vector2Int>(at, new Vector2Int(kind, arg)));
                }
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-host") _session.Host(PortAt(args, i + 1));
                else if (args[i] == "-join" && i + 1 < args.Length) _session.Join(args[i + 1], PortAt(args, i + 2));
            }
        }

        bool _walk;
        int _attackSlot;
        int _castSlot;

        readonly List<KeyValuePair<float, Vector2Int>> _deals = new List<KeyValuePair<float, Vector2Int>>();
        float _inSession;

        string _shotPath;
        float _shotDelay = 8f;

        void Update()
        {
            if (_shotPath != null && InSession && NetworkManager.Singleton.LocalClient != null
                && NetworkManager.Singleton.LocalClient.PlayerObject != null)
            {
                _shotDelay -= Time.deltaTime;
                if (_shotDelay <= 0f)
                {
                    ScreenCapture.CaptureScreenshot(_shotPath);
                    Debug.Log("[снимок] " + _shotPath);
                    _shotPath = null;
                }
            }
            if (_deals.Count > 0 && InSession && NetworkManager.Singleton.LocalClient != null
                && NetworkManager.Singleton.LocalClient.PlayerObject != null)
            {
                _inSession += Time.deltaTime;
                for (int i = _deals.Count - 1; i >= 0; i--)
                {
                    if (_inSession < _deals[i].Key) continue;
                    var shop = NetworkManager.Singleton.LocalClient.PlayerObject.GetComponent<Shop>();
                    var deal = _deals[i].Value;
                    if (shop != null) shop.Request((DealKind)deal.x, deal.y);
                    Debug.Log("[сделка] заявка " + (DealKind)deal.x + " " + deal.y);
                    _deals.RemoveAt(i);
                }
            }
            if (!_walk && _attackSlot <= 0 && _castSlot <= 0) return;
            var net = NetworkManager.Singleton;
            if (net == null || net.LocalClient == null || net.LocalClient.PlayerObject == null) return;
            var me = net.LocalClient.PlayerObject.GetComponent<PlayerCharacter>();
            if (me == null) return;
            if (_walk && me.Scripted == null) me.Scripted = new MotorInput { MoveY = -1f };
            var combat = me.GetComponent<PlayerCombat>();
            var set = Factions.WeaponsOf(me.Faction);
            if (combat != null && _attackSlot > 0 && _attackSlot <= set.Length)
            {
                combat.Weapon = set[_attackSlot - 1];
                combat.ScriptedAttack = true;
            }
            var spells = me.GetComponent<PlayerSpells>();
            var known = Factions.AbilitiesOf(me.Faction);
            if (spells != null && _castSlot > 0 && _castSlot <= known.Length && me.Spells.Ready(known[_castSlot - 1]))
                spells.ScriptedCast = (int)known[_castSlot - 1];
        }

        static ushort PortAt(string[] args, int i)
        {
            ushort port;
            return i < args.Length && ushort.TryParse(args[i], out port) ? port : DefaultPort;
        }

        bool InSession
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net != null && (net.IsServer || net.IsClient);
            }
        }

        void OnGUI()
        {
            GUI.skin.label.fontSize = 18;
            GUI.skin.button.fontSize = 18;
            GUI.skin.textField.fontSize = 18;
            if (InSession)
            {
                var net = NetworkManager.Singleton;
                string role = net.IsHost ? "Хост" : net.IsConnectedClient ? "Клиент" : "Подключение…";
                GUI.Label(new Rect(12, 8, 900, 30), role + ". " + _session.Status);
                if (Cursor.lockState != CursorLockMode.Locked && GUI.Button(new Rect(12, 40, 160, 34), "Выйти"))
                    _session.Leave();
                return;
            }

            GUILayout.BeginArea(new Rect(Screen.width * 0.5f - 220, Screen.height * 0.5f - 170, 440, 340), GUI.skin.box);
            GUILayout.Label("ДжваГода");
            GUILayout.BeginHorizontal();
            GUILayout.Label("Имя", GUILayout.Width(80));
            string named = GUILayout.TextField(_session.Profile, 24);
            if (named != _session.Profile)
            {
                _session.Profile = named;
                PlayerPrefs.SetString(ProfileKey, named);
            }
            GUILayout.EndHorizontal();
            GUILayout.Label("Сторона:");
            _session.Wanted = (Faction)GUILayout.Toolbar((int)_session.Wanted, Factions.Names);
            GUILayout.Space(8);
            GUILayout.BeginHorizontal();
            GUILayout.Label("Адрес", GUILayout.Width(80));
            _address = GUILayout.TextField(_address);
            GUILayout.Label("Порт", GUILayout.Width(60));
            _port = GUILayout.TextField(_port, GUILayout.Width(80));
            GUILayout.EndHorizontal();
            ushort port;
            if (!ushort.TryParse(_port, out port)) port = DefaultPort;
            GUILayout.Space(8);
            if (GUILayout.Button("Создать игру", GUILayout.Height(40))) _session.Host(port);
            if (GUILayout.Button("Подключиться", GUILayout.Height(40))) _session.Join(_address, port);
            if (!string.IsNullOrEmpty(_session.Status)) GUILayout.Label(_session.Status);
            GUILayout.EndArea();
        }
    }
}
