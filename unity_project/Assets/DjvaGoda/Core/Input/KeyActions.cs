// Раскладка: все клавиши игры одним списком, переназначаемые (перенос keymap.gd;
// решение автора от 28.09: «чтоб каждый мог под себя назначить клавиши»).
//
// Умолчания записаны путями привязок Input System ("<Keyboard>/w"): ядро не
// знает Unity, но путь — просто строка. Клавиши ФИЗИЧЕСКИЕ: на русской
// раскладке «C» и «С» — разные символы на одной кнопке.
//
// Одна клавиша может стоять на двух действиях из РАЗНЫХ режимов: B в бою
// перевязывает, сверху нанимает батрака. Конфликт — совпадение внутри одного
// режима или с «общими» клавишами, которые работают везде.
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum KeyGroup { Combat, Strategy, General }

    public struct KeyAction
    {
        public readonly string Name;
        public readonly string Label;
        public readonly KeyGroup Group;
        public readonly string[] Defaults;

        public KeyAction(string name, string label, KeyGroup group, params string[] defaults)
        {
            Name = name;
            Label = label;
            Group = group;
            Defaults = defaults;
        }
    }

    public static class KeyActions
    {
        public static readonly string[] GroupNames = { "В бою", "Вид сверху", "Везде" };

        const string K = "<Keyboard>/";

        /// Порядок — порядок строк в меню настройки.
        public static readonly KeyAction[] All =
        {
            new KeyAction("move_forward", "вперёд", KeyGroup.Combat, K + "w"),
            new KeyAction("move_back", "назад", KeyGroup.Combat, K + "s"),
            new KeyAction("move_left", "влево", KeyGroup.Combat, K + "a"),
            new KeyAction("move_right", "вправо", KeyGroup.Combat, K + "d"),
            new KeyAction("jump", "прыжок", KeyGroup.Combat, K + "space"),
            new KeyAction("sprint", "бег", KeyGroup.Combat, K + "leftShift"),
            new KeyAction("dash", "рывок (эльфы)", KeyGroup.Combat, K + "r"),
            new KeyAction("attack", "удар / выстрел", KeyGroup.Combat, "<Mouse>/leftButton"),
            new KeyAction("interact", "взаимодействие", KeyGroup.Combat, K + "e", K + "f"),
            new KeyAction("bandage", "перевязка (держать)", KeyGroup.Combat, K + "b"),
            new KeyAction("toggle_view", "первое / третье лицо", KeyGroup.Combat, K + "v"),
            new KeyAction("weapon_1", "оружие 1", KeyGroup.Combat, K + "1"),
            new KeyAction("weapon_2", "оружие 2", KeyGroup.Combat, K + "2"),
            new KeyAction("weapon_3", "оружие 3", KeyGroup.Combat, K + "3"),
            new KeyAction("weapon_4", "оружие 4", KeyGroup.Combat, K + "7"),
            new KeyAction("ability_1", "заклинание 1", KeyGroup.Combat, K + "4"),
            new KeyAction("ability_2", "заклинание 2", KeyGroup.Combat, K + "5"),
            new KeyAction("ability_3", "заклинание 3", KeyGroup.Combat, K + "6"),
            new KeyAction("build_elf_house", "эльфы: построить дом", KeyGroup.Combat, K + "n"),
            new KeyAction("potion_heal", "выпить зелье лечения", KeyGroup.Combat, K + "z"),
            new KeyAction("potion_mana", "выпить зелье маны", KeyGroup.Combat, K + "x"),

            new KeyAction("cam_rotate_left", "поворот камеры влево", KeyGroup.Strategy, K + "q"),
            new KeyAction("cam_rotate_right", "поворот камеры вправо", KeyGroup.Strategy, K + "e"),
            new KeyAction("build_storage", "строить: склад", KeyGroup.Strategy, K + "1"),
            new KeyAction("build_sword", "строить: казарма мечников", KeyGroup.Strategy, K + "2"),
            new KeyAction("build_archer", "строить: казарма лучников", KeyGroup.Strategy, K + "3"),
            new KeyAction("build_stable", "строить: конюшня", KeyGroup.Strategy, K + "4"),
            new KeyAction("build_house", "строить: дом дружины", KeyGroup.Strategy, K + "5"),
            new KeyAction("build_farm", "строить: поле", KeyGroup.Strategy, K + "6"),
            new KeyAction("build_forge", "строить: кузня", KeyGroup.Strategy, K + "u"),
            new KeyAction("route", "маршрут обоза", KeyGroup.Strategy, K + "c"),
            new KeyAction("hire_labourer", "нанять батрака", KeyGroup.Strategy, K + "b"),
            new KeyAction("role_lumberjack", "батрака в лесорубы", KeyGroup.Strategy, K + "7"),
            new KeyAction("role_miner", "батрака в шахтёры", KeyGroup.Strategy, K + "8"),
            new KeyAction("role_militia", "батрака в ополченцы", KeyGroup.Strategy, K + "9"),
            new KeyAction("role_builder", "батрака в строители", KeyGroup.Strategy, K + "0"),
            new KeyAction("role_farmer", "батрака в фермеры", KeyGroup.Strategy, K + "f"),
            new KeyAction("squad_follow", "отряд ко мне", KeyGroup.Strategy, K + "g"),
            new KeyAction("squad_escort", "отряд с обозом", KeyGroup.Strategy, K + "h"),
            // Строи на F2–F5: на F1 справка, и строй «колонна» по F1 не включался никогда.
            new KeyAction("formation_1", "строй 1", KeyGroup.Strategy, K + "f2"),
            new KeyAction("formation_2", "строй 2", KeyGroup.Strategy, K + "f3"),
            new KeyAction("formation_3", "строй 3", KeyGroup.Strategy, K + "f4"),
            new KeyAction("formation_4", "строй 4", KeyGroup.Strategy, K + "f5"),

            new KeyAction("toggle_camera", "вид сверху / в бой", KeyGroup.General, K + "tab"),
            new KeyAction("upgrade", "прокачка", KeyGroup.General, K + "p"),
            new KeyAction("help", "справка по клавишам", KeyGroup.General, K + "f1"),
            new KeyAction("mute", "звук выкл / вкл", KeyGroup.General, K + "m"),
            new KeyAction("volume_down", "тише", KeyGroup.General, K + "minus"),
            new KeyAction("volume_up", "громче", KeyGroup.General, K + "equals"),
            new KeyAction("console", "консоль", KeyGroup.General, K + "backquote"),
            new KeyAction("leave", "выйти в главное меню", KeyGroup.General, K + "f10"),
            new KeyAction("pause", "пауза", KeyGroup.General, K + "escape"),
        };

        public static KeyAction? Find(string name)
        {
            foreach (var action in All)
                if (action.Name == name) return action;
            return null;
        }

        /// Мешают ли друг другу действия двух групп на одной клавише.
        public static bool GroupsClash(KeyGroup a, KeyGroup b)
        {
            return a == b || a == KeyGroup.General || b == KeyGroup.General;
        }

        /// Кто ещё сидит на этой клавише и мешает действию `name`. Пусто — никто.
        public static List<string> Conflicts(string name, string binding, IDictionary<string, string[]> current)
        {
            var found = new List<string>();
            var self = Find(name);
            if (!self.HasValue) return found;
            foreach (var other in All)
            {
                if (other.Name == name || !GroupsClash(self.Value.Group, other.Group)) continue;
                string[] keys;
                if (!current.TryGetValue(other.Name, out keys)) keys = other.Defaults;
                if (System.Array.IndexOf(keys, binding) >= 0) found.Add(other.Name);
            }
            return found;
        }

        /// Раскладка по умолчанию: действие -> клавиши.
        public static Dictionary<string, string[]> Defaults()
        {
            var map = new Dictionary<string, string[]>();
            foreach (var action in All) map[action.Name] = (string[])action.Defaults.Clone();
            return map;
        }

        /// Переназначить; при конфликте — поменять местами (как в Godot-версии):
        /// мешавшее действие получает прежнюю клавишу переназначаемого.
        public static void Rebind(IDictionary<string, string[]> current, string name, string binding)
        {
            string[] before;
            if (!current.TryGetValue(name, out before)) before = Find(name).Value.Defaults;
            string old = before.Length > 0 ? before[0] : null;
            foreach (var other in Conflicts(name, binding, current))
            {
                string[] keys;
                if (!current.TryGetValue(other, out keys)) keys = Find(other).Value.Defaults;
                var swapped = new List<string>(keys);
                swapped.Remove(binding);
                if (old != null) swapped.Insert(0, old);
                current[other] = swapped.ToArray();
            }
            current[name] = new[] { binding };
        }
    }
}
