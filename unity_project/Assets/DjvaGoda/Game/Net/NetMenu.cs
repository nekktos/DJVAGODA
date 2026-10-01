// Меню сессии (перенос главного меню Godot-версии, пока без картинок):
// сторона, «Создать игру» или «Подключиться» по адресу, строка состояния.
//
// Для прогонов без мыши — ключи командной строки:
//   -host [порт]            создать игру
//   -join адрес [порт]      подключиться
//   -side 0|1|2             сторона (Злодей, Лесные эльфы, Охрана дворца)
//   -walk                   свой персонаж идёт вперёд без ввода (проверка
//                           движения по сети)
using System;
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

        void Awake() { _session = GetComponent<NetSession>(); }

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
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-host") _session.Host(PortAt(args, i + 1));
                else if (args[i] == "-join" && i + 1 < args.Length) _session.Join(args[i + 1], PortAt(args, i + 2));
            }
        }

        bool _walk;

        void Update()
        {
            if (!_walk) return;
            var net = NetworkManager.Singleton;
            if (net == null || net.LocalClient == null || net.LocalClient.PlayerObject == null) return;
            var me = net.LocalClient.PlayerObject.GetComponent<PlayerCharacter>();
            if (me != null && me.Scripted == null) me.Scripted = new MotorInput { MoveY = -1f };
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
