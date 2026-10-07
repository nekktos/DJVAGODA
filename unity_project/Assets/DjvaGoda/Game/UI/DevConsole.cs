// Консоль плейтеста: «~» (клавиша под Esc) открывает строку ввода, Enter
// шлёт команду хосту (Cheats). Есть только в отладочной сборке и в редакторе.
// Пока открыта — игровые клавиши молчат (GameInput.Muted), курсор свободен.
using System.Collections.Generic;
using Unity.Netcode;
using UnityEngine;
using UnityEngine.InputSystem;

namespace DjvaGoda.Game
{
    public class DevConsole : MonoBehaviour
    {
        const int HistorySize = 12;
        static readonly List<string> History = new List<string>();

        public static bool Open { get; private set; }
        string _line = "";
        bool _focus;
        CursorLockMode _wasLock;

        public static void Reply(string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            foreach (var part in text.Split('\n')) History.Add(part);
            while (History.Count > HistorySize) History.RemoveAt(0);
        }

        void Update()
        {
            var keyboard = Keyboard.current;
            if (keyboard == null || !Cheats.Allowed) return;
            if (keyboard.backquoteKey.wasPressedThisFrame) Toggle(!Open);
        }

        void Toggle(bool open)
        {
            Open = open;
            GameInput.Muted = open;
            if (open)
            {
                _wasLock = Cursor.lockState;
                Cursor.lockState = CursorLockMode.None;
                Cursor.visible = true;
                _focus = true;
                _line = "";
            }
            else
            {
                Cursor.lockState = _wasLock;
                Cursor.visible = _wasLock != CursorLockMode.Locked;
            }
        }

        void OnDisable()
        {
            if (Open) Toggle(false);
        }

        static PlayerCharacter Me()
        {
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player != null && player.LocalControl && player.GetComponent<HeroDriver>() == null) return player;
            }
            return null;
        }

        void Send(string line)
        {
            Reply("> " + line);
            var me = Me();
            var net = me != null ? me.GetComponent<NetPlayer>() : null;
            bool remote = net != null && net.IsSpawned && !NetworkManager.Singleton.IsServer;
            // Выносливость считает владелец персонажа (движение — у клиента), так
            // что «stamina» у клиента — у себя, а не у хоста.
            if (remote && line.Trim().ToLowerInvariant() == "stamina") Reply(Cheats.Run(me, line));
            else if (remote) net.CheatRpc(line);
            else Reply(Cheats.Run(me, line));
        }

        void OnGUI()
        {
            if (!Open) return;
            var e = Event.current;
            // «~», которым открыли, в строку не пишем; Esc и «~» — закрыть.
            if (e.type == EventType.KeyDown && (e.keyCode == KeyCode.BackQuote || e.character == '`' || e.character == '~' || e.character == 'ё'))
            {
                e.Use();
                return;
            }
            if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape)
            {
                e.Use();
                Toggle(false);
                return;
            }
            if (e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter))
            {
                e.Use();
                if (_line.Trim().Length > 0) Send(_line.Trim());
                _line = "";
            }
            float width = Mathf.Min(900f, Screen.width - 32f);
            GUI.Box(new Rect(16, 16, width, 30 + HistorySize * 20 + 34), "Консоль плейтеста (help — список, ~ — закрыть)");
            var style = new GUIStyle(GUI.skin.label) { fontSize = 15 };
            for (int i = 0; i < History.Count; i++) GUI.Label(new Rect(24, 40 + i * 20, width - 16, 20), History[i], style);
            GUI.SetNextControlName("консоль");
            _line = GUI.TextField(new Rect(24, 40 + HistorySize * 20 + 4, width - 16, 26), _line, new GUIStyle(GUI.skin.textField) { fontSize = 16 });
            if (_focus)
            {
                GUI.FocusControl("консоль");
                _focus = false;
            }
        }
    }
}
