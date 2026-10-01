// Экран боя (временный, до шага «Интерфейс» с картинками): прицел, полосы
// здоровья, выносливости и маны, оружие стороны, стрелы, откат удара, раны и
// отсчёт до возрождения. Показывает персонажа, за которым смотрит камера.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Hud : MonoBehaviour
    {
        CameraRig _rig;
        GUIStyle _label;

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

        void OnGUI()
        {
            var me = _rig != null ? _rig.Target : null;
            if (me == null) return;
            if (_label == null) _label = new GUIStyle(GUI.skin.label) { fontSize = 18 };
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
            Bar(new Rect(x, y, 240, 16), me.Vitals.Health / me.Vitals.MaxHealth, new Color(0.8f, 0.15f, 0.15f));
            GUI.Label(new Rect(x + 248, y - 4, 200, 24), Mathf.CeilToInt(me.Vitals.Health) + " / " + Mathf.CeilToInt(me.Vitals.MaxHealth), _label);
            Bar(new Rect(x, y + 22, 240, 10), me.Vitals.Stamina / me.Vitals.MaxStamina, new Color(0.85f, 0.75f, 0.2f));
            Bar(new Rect(x, y + 38, 240, 10), me.Vitals.Mana / me.Vitals.MaxMana, new Color(0.25f, 0.45f, 0.95f));

            var notes = "";
            if (me.Body.Bleeding) notes += "кровотечение — держите B, чтобы перевязаться (бинтов " + me.Body.Bandages + ")   ";
            if (combat != null && combat.Stagger > 0f) notes += "сбит с ног   ";
            if (me.Spells.Paralysis > 0f) notes += "паралич   ";
            if (me.Spells.Wither > 0f) notes += "увядание   ";
            if (me.Spells.Rally > 0f) notes += "клич леса   ";
            if (notes.Length > 0) GUI.Label(new Rect(x, y - 30, 900, 24), notes, _label);
            var t = me.Trophies;
            string wounds = me.Body.Summary();
            if (wounds != "цел" || t[0] + t[1] + t[2] > 0)
                GUI.Label(new Rect(x, y - 54, 900, 24), "тело: " + wounds
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
                string title = (4 + i) + " " + Abilities.NameOf(kind) + (cd > 0f ? " " + Mathf.CeilToInt(cd) : "");
                bool can = cd <= 0f && me.Vitals.Mana >= Abilities.ManaCost[(int)kind];
                GUI.color = can ? Color.white : new Color(1f, 1f, 1f, 0.5f);
                GUI.Box(new Rect(16 + i * 214, Screen.height - 160, 208, 30), title, new GUIStyle(GUI.skin.box) { fontSize = 14 });
                GUI.color = Color.white;
            }

            if (combat == null) return;
            var set = Factions.WeaponsOf(me.Faction);
            float wx = Screen.width - 16 - set.Length * 120;
            string[] keys = { "1", "2", "3", "7" };
            for (int i = 0; i < set.Length; i++)
            {
                bool chosen = set[i] == combat.Weapon;
                bool can = combat.Allowed(set[i]);
                string title = (i < keys.Length ? keys[i] + " " : "") + Weapons.Names[(int)set[i]];
                if (Weapons.UsesArrows(set[i])) title += " (" + me.Kit.Arrows + ")";
                var style = new GUIStyle(GUI.skin.box) { fontSize = 15 };
                GUI.color = chosen ? Color.white : (can ? new Color(1f, 1f, 1f, 0.55f) : new Color(1f, 0.4f, 0.4f, 0.55f));
                GUI.Box(new Rect(wx + i * 120, Screen.height - 50, 114, 34), title, style);
                GUI.color = Color.white;
            }
            if (!string.IsNullOrEmpty(combat.Refusal))
                GUI.Label(new Rect(cx - 300, cy + 40, 600, 30), combat.Refusal,
                    new GUIStyle(_label) { alignment = TextAnchor.MiddleCenter });
        }

        /// Клавиша действия по умолчанию — для подсказок («1», «U»).
        static string KeyOf(string action)
        {
            foreach (var key in KeyActions.All)
                if (key.Name == action && key.Defaults.Length > 0)
                {
                    var path = key.Defaults[0];
                    return path.Substring(path.LastIndexOf('/') + 1).ToUpperInvariant();
                }
            return "?";
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

        /// Ресурсы стороны: при себе (под риском) и на складе.
        void Resources(Faction side)
        {
            var wallet = Treasury.Of(side);
            string carried = "", stored = "";
            for (int i = 0; i < Res.Count; i++)
            {
                carried += Res.Short[i] + " " + wallet.Carried.Amounts[i] + "   ";
                stored += Res.Short[i] + " " + wallet.Stored.Amounts[i] + "   ";
            }
            float w = 620;
            GUI.Box(new Rect(Screen.width * 0.5f - w * 0.5f, 80, w, 52), GUIContent.none);
            GUI.Label(new Rect(Screen.width * 0.5f - w * 0.5f + 8, 82, w, 24),
                "при себе (до " + wallet.Carried.Capacity + "): " + carried, _label);
            GUI.Label(new Rect(Screen.width * 0.5f - w * 0.5f + 8, 104, w, 24),
                wallet.Stored.Capacity > 0 ? "склад (до " + wallet.Stored.Capacity + "): " + stored : "склада нет — постройте", _label);
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
