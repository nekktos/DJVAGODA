// Экран боя (временный, до шага «Интерфейс» с картинками): прицел, полосы
// здоровья, выносливости и маны, оружие стороны, стрелы, откат удара, раны и
// отсчёт до возрождения. Показывает персонажа, за которым смотрит камера.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Hud : MonoBehaviour
    {
        CameraRig _rig;
        GUIStyle _label, _small;

        void Awake() { _rig = GetComponent<CameraRig>(); }

        /// Исход партии: объявления сверху, у дворца — чей он и ход захвата.
        void Goals(PlayerCharacter me)
        {
            var goals = MatchGoals.Instance;
            if (goals == null) return;
            var center = new GUIStyle(_label) { alignment = TextAnchor.MiddleCenter };
            float y = 120f;
            foreach (var entry in goals.Feed)
            {
                if (Time.time - entry.Value > MatchGoals.AnnounceSeconds && !entry.Key.StartsWith("ПОБЕДА")) continue;
                bool win = entry.Key.StartsWith("ПОБЕДА");
                GUI.Label(new Rect(Screen.width * 0.5f - 400, y, 800, win ? 40 : 28), entry.Key,
                    win ? new GUIStyle(center) { fontSize = 30 } : center);
                y += win ? 40 : 28;
            }
            var state = goals.State;
            bool near = me.Feet.FlatDistance(MatchState.Palace) <= MatchState.CaptureRadius * 2f;
            if (!near && state.CaptureProgress <= 0f) return;
            string text = "Дворец: " + Factions.NameOf(state.PalaceOwner);
            if (state.Contested) text += " — оспаривают";
            else if (state.Claimant >= 0) text += " — берёт " + Factions.Names[state.Claimant];
            GUI.Label(new Rect(Screen.width * 0.5f - 200, 40, 400, 24), text, center);
            if (state.CaptureProgress > 0f)
                Bar(new Rect(Screen.width * 0.5f - 120, 66, 240, 8), state.CaptureProgress, new Color(0.9f, 0.7f, 0.2f));
        }

        /// Ряд заклинаний над полосами здоровья и строки состояния над ним.
        static float SpellRow { get { return Screen.height - 170; } }
        static float Lines { get { return SpellRow - 4; } }

        void OnGUI()
        {
            var me = _rig != null ? _rig.Target : null;
            if (me == null) return;
            if (_label == null) _label = new GUIStyle(GUI.skin.label) { fontSize = 18 };
            if (_small == null) _small = new GUIStyle(GUI.skin.label) { fontSize = 14 };
            var combat = me.GetComponent<PlayerCombat>();
            var net = me.GetComponent<NetPlayer>();
            Goals(me);

            if (!me.Alive)
            {
                float left = net != null && net.IsSpawned ? net.RespawnIn.Value : -1f;
                string text = left < 0f ? "Вожак пал — злодей выбыл из партии." : "Вы пали. Встанете через " + Mathf.CeilToInt(left) + " с";
                GUI.Label(new Rect(Screen.width * 0.5f - 220, Screen.height * 0.4f, 440, 40), text,
                    new GUIStyle(_label) { fontSize = 26, alignment = TextAnchor.MiddleCenter });
                return;
            }

            Resources(me.Faction);
            BuildPanel(me);

            // Слепота: заклятие злодея и выбитые глаза — экран темнеет.
            float blind = Mathf.Max(me.Spells.Blind > 0f ? 0.85f : 0f, me.Body.Blindness() * 0.6f);
            if (blind > 0f)
            {
                GUI.color = new Color(0f, 0f, 0f, blind);
                GUI.DrawTexture(new Rect(0, 0, Screen.width, Screen.height), Texture2D.whiteTexture);
                GUI.color = Color.white;
            }

            // Прицел; откат — полоской под ним.
            float cx = Screen.width * 0.5f, cy = Screen.height * 0.5f;
            GUI.Label(new Rect(cx - 6, cy - 14, 20, 30), "+", _label);
            if (combat != null && combat.HitAge < 0.35f)
            {
                // Попал: крест вокруг прицела; в голову — жёлтый, добил — красный и крупнее.
                GUI.color = combat.HitKill ? new Color(1f, 0.2f, 0.2f) : (combat.HitHead ? new Color(1f, 0.85f, 0.2f) : Color.white);
                int size = combat.HitKill ? 30 : 22;
                GUI.Label(new Rect(cx - size * 0.35f, cy - size * 0.75f, 40, 40), "×",
                    new GUIStyle(_label) { fontSize = size });
                GUI.color = Color.white;
            }
            if (combat != null && combat.Cooldown > 0f && combat.CooldownFull > 0f)
                Bar(new Rect(cx - 20, cy + 16, 40, 4), combat.Cooldown / combat.CooldownFull, new Color(1f, 1f, 1f, 0.8f));

            float x = 16, y = Screen.height - 110;
            // Строки состояния — над рядом заклинаний, а не поверх него.
            Bar(new Rect(x, y, 240, 16), me.Vitals.Health / me.Vitals.MaxHealth, new Color(0.8f, 0.15f, 0.15f));
            GUI.Label(new Rect(x + 248, y - 4, 200, 24), Mathf.CeilToInt(me.Vitals.Health) + " / " + Mathf.CeilToInt(me.Vitals.MaxHealth), _label);
            Bar(new Rect(x, y + 22, 240, 10), me.Vitals.Stamina / me.Vitals.MaxStamina, new Color(0.85f, 0.75f, 0.2f));
            Bar(new Rect(x, y + 38, 240, 10), me.Vitals.Mana / me.Vitals.MaxMana, new Color(0.25f, 0.45f, 0.95f));
            Supplies(me, x, y + 54);

            var notes = "";
            if (me.Body.Bleeding) notes += "кровотечение — держите B, чтобы перевязаться (бинтов " + me.Body.Bandages + ")   ";
            if (combat != null && combat.Stagger > 0f) notes += "сбит с ног   ";
            if (me.Spells.Paralysis > 0f) notes += "паралич   ";
            if (me.Spells.Wither > 0f) notes += "увядание   ";
            if (me.Spells.Rally > 0f) notes += "клич леса   ";
            if (notes.Length > 0) GUI.Label(new Rect(x, Lines - 24, 900, 24), notes, _label);
            // Приказ стража или задание эльфа — строкой над полосами.
            if (me.Faction == Faction.Guard && me.Service.Order.HasValue)
                GUI.Label(new Rect(x, Lines - 72, 900, 24), "приказ: " + Orders.NameOf(me.Service.Order.Value) + " — "
                    + Orders.ProgressText(me.Service.Order.Value, me.Service.Progress), _label);
            if (me.Faction == Faction.Elves && me.Tasks.Task.HasValue)
                GUI.Label(new Rect(x, Lines - 72, 900, 24), "задание: " + ElfTasks.NameOf(me.Tasks.Task.Value) + " — "
                    + ElfTasks.ProgressText(me.Tasks.Task.Value, me.Tasks.Progress), _label);
            var t = me.Trophies;
            string wounds = me.Body.Summary();
            if (wounds != "цел" || t[0] + t[1] + t[2] > 0)
                GUI.Label(new Rect(x, Lines - 48, 900, 24), "тело: " + wounds
                    + (t[0] + t[1] + t[2] > 0 ? "   трофеи: рук " + t[0] + ", ног " + t[1] + ", глаз " + t[2] : ""), _label);

            // Каст — полоса над прицелом.
            if (me.Spells.Casting && me.Spells.CastKind.HasValue)
            {
                float full = Abilities.CastTime(me.Spells.CastKind.Value);
                Bar(new Rect(cx - 80, cy - 60, 160, 8), full > 0f ? 1f - me.Spells.CastLeft / full : 1f, new Color(0.6f, 0.3f, 0.9f));
                GUI.Label(new Rect(cx - 80, cy - 86, 300, 24), Abilities.NameOf(me.Spells.CastKind.Value) + "…", _label);
            }

            // Заклинания стороны: 4/5/6, мана и откат.
            var known = Factions.AbilitiesOf(me.Faction);
            for (int i = 0; i < known.Length; i++)
            {
                var kind = known[i];
                float cd = me.Spells.Cooldowns[(int)kind];
                string title = KeyOf("ability_" + (i + 1)) + "  " + Abilities.NameOf(kind) + (cd > 0f ? "  " + Mathf.CeilToInt(cd) : "");
                bool can = cd <= 0f && me.Vitals.Mana >= Abilities.ManaCost[(int)kind];
                GUI.color = can ? Color.white : new Color(1f, 1f, 1f, 0.5f);
                var slot = new Rect(16 + i * 214, SpellRow, 208, 38);
                GUI.Box(slot, GUIContent.none);
                Icons.Draw(new Rect(slot.x + 4, slot.y + 3, 32, 32), "ab_" + (int)kind, !can);
                GUI.Label(new Rect(slot.x + 40, slot.y + 8, 168, 24), title, new GUIStyle(_small) { fontSize = 14 });
                // Откат — тень, сползающая с иконки.
                if (cd > 0f)
                {
                    float frac = Mathf.Clamp01(cd / Mathf.Max(0.01f, Abilities.Cooldown[(int)kind]));
                    GUI.color = new Color(0f, 0f, 0f, 0.55f);
                    GUI.DrawTexture(new Rect(slot.x + 4, slot.y + 3 + 32 * (1f - frac), 32, 32 * frac), Texture2D.whiteTexture);
                }
                GUI.color = Color.white;
            }

            if (combat == null) return;
            var set = Factions.WeaponsOf(me.Faction);
            float wx = Screen.width - 16 - set.Length * 146;
            for (int i = 0; i < set.Length; i++)
            {
                bool chosen = set[i] == combat.Weapon;
                bool can = combat.Allowed(set[i]);
                string title = KeyOf("weapon_" + (i + 1)) + " " + Weapons.Names[(int)set[i]];
                if (Weapons.UsesArrows(set[i])) title += " " + me.Kit.Arrows;
                var slot = new Rect(wx + i * 146, Screen.height - 64, 140, 48);
                GUI.color = chosen ? Color.white : (can ? new Color(1f, 1f, 1f, 0.55f) : new Color(1f, 0.4f, 0.4f, 0.55f));
                GUI.Box(slot, GUIContent.none);
                if (chosen) GUI.Box(slot, GUIContent.none);
                Icons.Draw(new Rect(slot.x + 3, slot.y + 4, 40, 40), "wpn_" + (int)set[i], !can);
                GUI.Label(new Rect(slot.x + 44, slot.y + 2, 94, 44), title, new GUIStyle(_small) { fontSize = 13, wordWrap = true, alignment = TextAnchor.MiddleLeft });
                GUI.color = Color.white;
            }
            if (!string.IsNullOrEmpty(combat.Refusal))
                GUI.Label(new Rect(cx - 300, cy + 40, 600, 30), combat.Refusal,
                    new GUIStyle(_label) { alignment = TextAnchor.MiddleCenter });
        }

        /// Клавиша действия в текущей раскладке (с переназначениями) — для подсказок.
        public static string KeyOf(string action)
        {
            var path = GameInput.Binding(action);
            if (path == null) return "?";
            // Буквы — заглавными (W, E), названия (Shift, ЛКМ) — как есть.
            string name = GameMenu.Human(path);
            return name.Length == 1 ? name.ToUpperInvariant() : name;
        }

        /// Вид сверху: что можно строить, клавиши и цены; при постановке — подсказка.
        void BuildPanel(PlayerCharacter me)
        {
            var builder = me.GetComponent<Builder>();
            if (builder != null && builder.Placing)
                GUI.Label(new Rect(Screen.width * 0.5f - 300, Screen.height - 200, 600, 26),
                    "Ставим: " + Res.BuildingNames[(int)builder.Kind] + " — " + Res.FormatCost(Res.BuildingCost(builder.Kind))
                    + ".  ЛКМ — поставить, ПКМ — отмена", new GUIStyle(_label) { alignment = TextAnchor.MiddleCenter });
            if (!GameMode.Strategy)
            {
                if (me.Faction == Faction.Elves && (builder == null || !builder.Placing))
                    GUI.Label(new Rect(16, 140, 500, 24), KeyOf("build_elf_house") + " — поставить дом эльфов", _label);
                return;
            }
            float y = 140;
            GUI.Label(new Rect(16, y, 500, 24), "Вид сверху.  " + KeyOf("toggle_camera") + " — в бой", _label);
            y += 26;
            foreach (var item in Builder.Menu)
            {
                if (!Factions.MayBuild(me.Faction, item.Value, me.Kit.IsLeader)) continue;
                var cost = Res.BuildingCost(item.Value);
                bool can = Treasury.Of(me.Faction).CanAfford(cost);
                GUI.color = can ? Color.white : new Color(1f, 1f, 1f, 0.5f);
                GUI.Label(new Rect(16, y, 700, 24), KeyOf(item.Key) + "  " + Res.BuildingNames[(int)item.Value] + " — " + Res.FormatCost(cost), _label);
                GUI.color = Color.white;
                y += 24;
            }
            var wallet = Treasury.Of(me.Faction);
            if (builder != null && builder.Routing)
                GUI.Label(new Rect(Screen.width * 0.5f - 300, Screen.height - 200, 600, 26),
                    "Маршрут обоза: точек " + builder.RoutePoints + " из " + Builder.MaxRoutePoints
                    + ".  ЛКМ — точка, Enter — отправить, ПКМ — отмена", new GUIStyle(_label) { alignment = TextAnchor.MiddleCenter });
            y = SquadPanel(me, y + 8);
            y += 8;
            GUI.Label(new Rect(16, y, 700, 24), KeyOf("route") + "  маршрут обоза (лошадей свободно " + wallet.HorsesFree + " из " + wallet.Horses + ")", _label);
            y += 24;
            if (!Factions.CanBuild(me.Faction) && !me.Kit.IsLeader) return;
            // Хозяйство: найм и роли батраков (счёт — по видимым батракам стороны).
            var counts = new int[LabourerStats.RoleNames.Length];
            int crew = Agents.CountCrew(me.Faction, counts);
            y += 8;
            GUI.Label(new Rect(16, y, 700, 24), KeyOf("hire_labourer") + "  нанять батрака — " + Res.FormatCost(Res.LabourerCost)
                + "   (батраков " + crew + " из " + Res.LabourerLimit + ")", _label);
            y += 24;
            foreach (var role in Builder.Roles)
            {
                GUI.Label(new Rect(16, y, 700, 24), KeyOf(role.Key) + "  в " + LabourerStats.RoleNames[(int)role.Value] + "ы — сейчас " + counts[(int)role.Value], _label);
                y += 22;
            }
        }

        /// Отряд сверху: состав, строй, приказы (как command_bar Godot-версии).
        float SquadPanel(PlayerCharacter me, float y)
        {
            var net = me.GetComponent<NetPlayer>();
            int count = net != null && net.IsSpawned && !net.IsServer ? net.Squad.Value & 255 : Squads.Of(me).Count;
            if (count == 0) return y;
            GUI.Label(new Rect(16, y, 900, 24), "Отряд: " + count + ", строй — " + Formations.Names[(int)me.SquadFormation]
                + (me.SquadHold ? ", стоит на точке" : ", идёт за вами"), _label);
            y += 24;
            GUI.Label(new Rect(16, y, 900, 24), "ПКМ — идти туда   " + KeyOf("squad_follow") + " — ко мне   "
                + KeyOf("squad_escort") + " — с обозом", _label);
            y += 24;
            var line = "";
            for (int i = 0; i < Formations.Names.Length; i++) line += KeyOf("formation_" + (i + 1)) + " — " + Formations.Names[i] + "   ";
            GUI.Label(new Rect(16, y, 900, 24), line, _label);
            return y + 24;
        }

        /// Ресурсы стороны: иконка и число — при себе (под риском) и на складе.
        void Resources(Faction side)
        {
            var wallet = Treasury.Of(side);
            const float cell = 86f, icon = 22f;
            float w = 150f + cell * Res.Count;
            float x0 = Screen.width * 0.5f - w * 0.5f;
            GUI.Box(new Rect(x0, 80, w, 56), GUIContent.none);
            GUI.Label(new Rect(x0 + 8, 83, 150, 24), "при себе / " + wallet.Carried.Capacity, _small);
            bool store = wallet.Stored.Capacity > 0;
            GUI.Label(new Rect(x0 + 8, 107, 150, 24), store ? "склад / " + wallet.Stored.Capacity
                : side == Faction.Elves ? "склада нет" : "склада нет", _small);
            for (int i = 0; i < Res.Count; i++)
            {
                float x = x0 + 150f + i * cell;
                Icons.Draw(new Rect(x, 82, icon, icon), "res_" + i);
                GUI.Label(new Rect(x + icon + 4, 82, cell - icon, 24), wallet.Carried.Amounts[i].ToString(), _label);
                if (!store) continue;
                Icons.Draw(new Rect(x, 108, icon, icon), "res_" + i, true);
                GUI.Label(new Rect(x + icon + 4, 108, cell - icon, 24), wallet.Stored.Amounts[i].ToString(), _label);
            }
        }

        /// Запасы при себе — иконками у полос: зелья, бинты, стрелы.
        void Supplies(PlayerCharacter me, float x, float y)
        {
            var items = new[]
            {
                new KeyValuePair<string, int>("potion_heal", me.Kit.PotionsHeal), new KeyValuePair<string, int>("potion_mana", me.Kit.PotionsMana),
                new KeyValuePair<string, int>("bandage", me.Body.Bandages), new KeyValuePair<string, int>("arrows", me.Kit.Arrows),
            };
            for (int i = 0; i < items.Length; i++)
            {
                Icons.Draw(new Rect(x + i * 64, y, 26, 26), items[i].Key, items[i].Value <= 0);
                GUI.Label(new Rect(x + i * 64 + 28, y + 2, 40, 24), items[i].Value.ToString(), _label);
            }
        }

        static void Bar(Rect rect, float fill, Color color)
        {
            GUI.color = new Color(0f, 0f, 0f, 0.5f);
            GUI.DrawTexture(rect, Texture2D.whiteTexture);
            GUI.color = color;
            GUI.DrawTexture(new Rect(rect.x, rect.y, rect.width * Mathf.Clamp01(fill), rect.height), Texture2D.whiteTexture);
            GUI.color = Color.white;
        }
    }
}
