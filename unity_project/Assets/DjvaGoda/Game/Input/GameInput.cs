// Ввод из раскладки ядра (KeyActions): действие на каждое имя, с умолчаниями
// и переназначениями игрока. Переназначения хранятся по имени действия.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;
using UnityEngine.InputSystem;

namespace DjvaGoda.Game
{
    public static class GameInput
    {
        const string OverridePrefix = "key.";
        static readonly Dictionary<string, InputAction> Actions = new Dictionary<string, InputAction>();
        static bool _built;

        static void Build()
        {
            if (_built) return;
            _built = true;
            foreach (var key in KeyActions.All)
            {
                var action = new InputAction(key.Name, InputActionType.Button);
                string saved = PlayerPrefs.GetString(OverridePrefix + key.Name, "");
                if (saved.Length > 0)
                {
                    foreach (var path in saved.Split('|')) action.AddBinding(path);
                }
                else
                {
                    foreach (var path in key.Defaults) action.AddBinding(path);
                }
                action.Enable();
                Actions[key.Name] = action;
            }
        }

        static InputAction Of(string name)
        {
            Build();
            InputAction action;
            return Actions.TryGetValue(name, out action) ? action : null;
        }

        public static bool Held(string name)
        {
            var action = Of(name);
            return action != null && action.IsPressed();
        }

        public static bool Pressed(string name)
        {
            var action = Of(name);
            return action != null && action.WasPressedThisFrame();
        }

        /// Ход как get_vector Godot: X — вправо, Y — назад.
        public static Vector2 Move()
        {
            float x = (Held("move_right") ? 1f : 0f) - (Held("move_left") ? 1f : 0f);
            float y = (Held("move_back") ? 1f : 0f) - (Held("move_forward") ? 1f : 0f);
            var v = new Vector2(x, y);
            return v.sqrMagnitude > 1f ? v.normalized : v;
        }

        public static Vector2 Look()
        {
            return Mouse.current != null ? Mouse.current.delta.ReadValue() : Vector2.zero;
        }

        /// Текущая раскладка: действие -> клавиши (свои или по умолчанию).
        public static Dictionary<string, string[]> Current()
        {
            var map = KeyActions.Defaults();
            foreach (var key in KeyActions.All)
            {
                string saved = PlayerPrefs.GetString(OverridePrefix + key.Name, "");
                if (saved.Length > 0) map[key.Name] = saved.Split('|');
            }
            return map;
        }

        /// Вернуть раскладку по умолчанию.
        public static void ResetAll()
        {
            foreach (var key in KeyActions.All)
            {
                PlayerPrefs.DeleteKey(OverridePrefix + key.Name);
                var action = Of(key.Name);
                if (action == null) continue;
                action.Disable();
                for (int i = action.bindings.Count - 1; i >= 0; i--) action.ChangeBinding(i).Erase();
                foreach (var path in key.Defaults) action.AddBinding(path);
                action.Enable();
            }
            PlayerPrefs.Save();
        }

        /// Переназначить клавиши действия (пути Input System) и запомнить.
        public static void Rebind(string name, string[] paths)
        {
            PlayerPrefs.SetString(OverridePrefix + name, string.Join("|", paths));
            PlayerPrefs.Save();
            var action = Of(name);
            if (action == null) return;
            action.Disable();
            for (int i = action.bindings.Count - 1; i >= 0; i--) action.ChangeBinding(i).Erase();
            foreach (var path in paths) action.AddBinding(path);
            action.Enable();
        }
    }
}
