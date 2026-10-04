// Меню в партии (перенос pause-меню, keymap-экрана, справки и окна прокачки
// Godot-версии; без картинок до шага ассетов):
//   Esc — меню: продолжить, клавиши, справка, выйти в главное меню;
//   клавиши — все действия раскладки по режимам, клик — нажать новую;
//     занятая в том же режиме меняется местами (KeyActions.Rebind ядра);
//   F1 — справка: что на какой клавише сейчас;
//   P — прокачка: опыт на уровни здоровья, выносливости, бега, маны (хост);
//   F10 — выйти в главное меню.
// Партия по сети не останавливается: меню — окно поверх, а не пауза мира.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;
using UnityEngine.InputSystem;

namespace DjvaGoda.Game
{
    public class GameMenu : MonoBehaviour
    {
        enum Page { None, Menu, Keys, Help, Upgrade }

        CameraRig _rig;
        Page _page;
        string _waiting;
        string _note = "";
        Vector2 _scroll;
        GUIStyle _button;

        public static bool Open { get; private set; }

        void Awake() { _rig = GetComponent<CameraRig>(); }

        void Update()
        {
            if (_waiting != null)
            {
                Capture();
                return;
            }
            var me = _rig != null ? _rig.Target : null;
            if (me == null)
            {
                Show(Page.None);
                return;
            }
            if (GameInput.Pressed("pause")) Show(_page == Page.None ? Page.Menu : Page.None);
            if (GameInput.Pressed("help")) Show(_page == Page.Help ? Page.None : Page.Help);
            if (GameInput.Pressed("upgrade") && !GameMode.Strategy) Show(_page == Page.Upgrade ? Page.None : Page.Upgrade);
            if (GameInput.Pressed("leave")) Leave();
        }

        void Show(Page page)
        {
            _page = page;
            Open = page != Page.None;
            if (!Open) return;
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }

        static void Leave()
        {
            if (NetSession.Instance != null) NetSession.Instance.Leave();
        }

        /// Ждём новую клавишу: первая нажатая клавиша или кнопка мыши; Esc — отмена.
        void Capture()
        {
            var keyboard = Keyboard.current;
            if (keyboard != null && keyboard.escapeKey.wasPressedThisFrame)
            {
                _waiting = null;
                _note = "отменено";
                return;
            }
            string path = null;
            if (keyboard != null)
                foreach (var key in keyboard.allKeys)
                    if (key != null && key.wasPressedThisFrame)
                    {
                        path = "<Keyboard>/" + key.name;
                        break;
                    }
            var mouse = Mouse.current;
            if (path == null && mouse != null)
            {
                if (mouse.middleButton.wasPressedThisFrame) path = "<Mouse>/middleButton";
                else if (mouse.rightButton.wasPressedThisFrame) path = "<Mouse>/rightButton";
                else if (mouse.forwardButton.wasPressedThisFrame) path = "<Mouse>/forwardButton";
                else if (mouse.backButton.wasPressedThisFrame) path = "<Mouse>/backButton";
            }
            if (path == null) return;
            var map = GameInput.Current();
            var before = new Dictionary<string, string[]>(map);
            KeyActions.Rebind(map, _waiting, path);
            var moved = new List<string>();
            foreach (var pair in map)
            {
                string[] old;
                if (before.TryGetValue(pair.Key, out old) && string.Join("|", old) == string.Join("|", pair.Value)) continue;
                GameInput.Rebind(pair.Key, pair.Value);
                if (pair.Key != _waiting) moved.Add(LabelOf(pair.Key));
            }
            _note = LabelOf(_waiting) + " — " + Human(path) + (moved.Count > 0 ? "; поменялись местами: " + string.Join(", ", moved.ToArray()) : "");
            _waiting = null;
        }

        static string LabelOf(string name)
        {
            var action = KeyActions.Find(name);
            return action.HasValue ? action.Value.Label : name;
        }

        public static string Human(string path)
        {
            string name = UnityEngine.InputSystem.InputControlPath.ToHumanReadableString(path,
                UnityEngine.InputSystem.InputControlPath.HumanReadableStringOptions.OmitDevice);
            string russian;
            return Russian.TryGetValue(name.ToLowerInvariant(), out russian) ? russian : name;
        }

        /// Кнопки мыши и служебные клавиши — по-русски, как в инструкции тестерам.
        static readonly Dictionary<string, string> Russian = new Dictionary<string, string>
        {
            { "left button", "ЛКМ" }, { "right button", "ПКМ" }, { "middle button", "СКМ" },
            { "forward", "мышь вперёд" }, { "back", "мышь назад" }, { "scroll", "колесо" },
            { "space", "Пробел" }, { "enter", "Enter" }, { "escape", "Esc" }, { "tab", "Tab" },
            { "left shift", "Shift" }, { "right shift", "правый Shift" },
            { "left ctrl", "Ctrl" }, { "right ctrl", "правый Ctrl" }, { "left control", "Ctrl" },
            { "left alt", "Alt" }, { "right alt", "правый Alt" },
            { "backspace", "Backspace" }, { "up arrow", "↑" }, { "down arrow", "↓" },
            { "left arrow", "←" }, { "right arrow", "→" },
        };

        static string Keys(Dictionary<string, string[]> map, string name)
        {
            string[] paths;
            if (!map.TryGetValue(name, out paths) || paths.Length == 0) return "—";
            var parts = new List<string>();
            foreach (var path in paths) parts.Add(Human(path));
            return string.Join(" / ", parts.ToArray());
        }

        void OnGUI()
        {
            if (_page == Page.None) return;
            // Меньшая глубина — поверх: HUD и окна мест не лезут на меню.
            GUI.depth = -100;
            GUI.color = new Color(0f, 0f, 0f, 0.75f);
            GUI.DrawTexture(new Rect(0, 0, Screen.width, Screen.height), Texture2D.whiteTexture);
            GUI.color = Color.white;
            if (_button == null) _button = new GUIStyle(GUI.skin.button) { fontSize = 16 };
            var area = new Rect(Screen.width * 0.5f - 300, Screen.height * 0.12f, 600, Screen.height * 0.76f);
            GUILayout.BeginArea(area, GUI.skin.box);
            switch (_page)
            {
                case Page.Menu: MenuPage(); break;
                case Page.Keys: KeysPage(); break;
                case Page.Help: HelpPage(); break;
                case Page.Upgrade: UpgradePage(); break;
            }
            GUILayout.EndArea();
        }

        void MenuPage()
        {
            GUILayout.Label("Меню (партия идёт дальше)");
            if (GUILayout.Button("Продолжить", _button, GUILayout.Height(40))) Show(Page.None);
            if (GUILayout.Button("Клавиши", _button, GUILayout.Height(40))) Show(Page.Keys);
            if (GUILayout.Button("Справка по клавишам", _button, GUILayout.Height(40))) Show(Page.Help);
            if (GUILayout.Button("Прокачка", _button, GUILayout.Height(40))) Show(Page.Upgrade);
            GUILayout.Space(12);
            if (GUILayout.Button("Выйти в главное меню", _button, GUILayout.Height(40))) Leave();
        }

        void KeysPage()
        {
            GUILayout.Label(_waiting != null ? "Нажмите новую клавишу для «" + LabelOf(_waiting) + "» (Esc — отмена)"
                : "Клик по строке — назначить клавишу. Совпадение в том же режиме меняется местами.");
            if (_note.Length > 0) GUILayout.Label(_note);
            var map = GameInput.Current();
            _scroll = GUILayout.BeginScrollView(_scroll);
            for (int group = 0; group < KeyActions.GroupNames.Length; group++)
            {
                GUILayout.Label("— " + KeyActions.GroupNames[group] + " —");
                foreach (var action in KeyActions.All)
                {
                    if ((int)action.Group != group) continue;
                    // Esc держит само меню: переназначить его — запереть себя без выхода.
                    GUI.enabled = action.Name != "pause" && _waiting == null;
                    if (GUILayout.Button(action.Label + ": " + Keys(map, action.Name), _button, GUILayout.Height(28)))
                    {
                        _waiting = action.Name;
                        _note = "";
                    }
                    GUI.enabled = true;
                }
            }
            GUILayout.EndScrollView();
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Сбросить всё", _button, GUILayout.Height(34)))
            {
                GameInput.ResetAll();
                _note = "раскладка по умолчанию";
            }
            if (GUILayout.Button("Назад", _button, GUILayout.Height(34))) Show(Page.Menu);
            GUILayout.EndHorizontal();
        }

        void HelpPage()
        {
            var map = GameInput.Current();
            _scroll = GUILayout.BeginScrollView(_scroll);
            for (int group = 0; group < KeyActions.GroupNames.Length; group++)
            {
                GUILayout.Label("— " + KeyActions.GroupNames[group] + " —");
                foreach (var action in KeyActions.All)
                    if ((int)action.Group == group) GUILayout.Label(Keys(map, action.Name) + " — " + action.Label);
            }
            GUILayout.EndScrollView();
            if (GUILayout.Button("Закрыть (F1)", _button, GUILayout.Height(34))) Show(Page.None);
        }

        void UpgradePage()
        {
            var me = _rig.Target;
            var vitals = me.Vitals;
            GUILayout.Label("Прокачка — опыт: " + vitals.Experience);
            GUILayout.Label("Опыт дают донесённая добыча, убийства врагов и доехавшие обозы.");
            bool magic = Factions.AbilitiesOf(me.Faction).Length > 0;
            for (int stat = 0; stat < Progression.Names.Length; stat++)
            {
                if (stat == (int)Stat.Mana && !magic) continue;
                int level = vitals.Levels[stat];
                int cost = Progression.CostOf(level);
                string title = Progression.Names[stat] + ": уровень " + level + " из " + Progression.MaxLevel
                    + (cost < 0 ? " — выше некуда" : " — следующий за " + cost);
                GUI.enabled = cost >= 0 && vitals.Experience >= cost;
                if (GUILayout.Button(title, _button, GUILayout.Height(34)))
                {
                    var shop = me.GetComponent<Shop>();
                    if (shop != null) shop.Request(DealKind.Upgrade, stat);
                }
                GUI.enabled = true;
            }
            // Заклинания своей стороны, у которых прокачка что-то меняет.
            foreach (var spell in Factions.AbilitiesOf(me.Faction))
            {
                if (!Abilities.Upgradable(spell)) continue;
                int level = vitals.SpellLevels[(int)spell];
                int cost = level >= Abilities.MaxSpellLevel ? -1 : Progression.CostOf(level);
                string title = Abilities.NameOf(spell) + ": уровень " + level + " из " + Abilities.MaxSpellLevel + ", "
                    + Abilities.UpgradeText(spell, level) + (cost < 0 ? " — выше некуда" : " → " + Abilities.UpgradeText(spell, level + 1) + " за " + cost);
                GUI.enabled = cost >= 0 && vitals.Experience >= cost;
                if (GUILayout.Button(title, _button, GUILayout.Height(34)))
                {
                    var shop = me.GetComponent<Shop>();
                    if (shop != null) shop.Request(DealKind.Upgrade, 10 + (int)spell);
                }
                GUI.enabled = true;
            }
            if (GUILayout.Button("Закрыть (P)", _button, GUILayout.Height(34))) Show(Page.None);
        }
    }
}
