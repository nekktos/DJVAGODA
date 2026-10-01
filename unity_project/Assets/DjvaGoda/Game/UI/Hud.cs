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

        void OnGUI()
        {
            var me = _rig != null ? _rig.Target : null;
            if (me == null) return;
            if (_label == null) _label = new GUIStyle(GUI.skin.label) { fontSize = 18 };
            var combat = me.GetComponent<PlayerCombat>();
            var net = me.GetComponent<NetPlayer>();

            if (!me.Alive)
            {
                float left = net != null && net.IsSpawned ? net.RespawnIn.Value : -1f;
                string text = left < 0f ? "Вожак пал — злодей выбыл из партии." : "Вы пали. Встанете через " + Mathf.CeilToInt(left) + " с";
                GUI.Label(new Rect(Screen.width * 0.5f - 220, Screen.height * 0.4f, 440, 40), text,
                    new GUIStyle(_label) { fontSize = 26, alignment = TextAnchor.MiddleCenter });
                return;
            }

            // Прицел; откат — полоской под ним.
            float cx = Screen.width * 0.5f, cy = Screen.height * 0.5f;
            GUI.Label(new Rect(cx - 6, cy - 14, 20, 30), "+", _label);
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
            if (notes.Length > 0) GUI.Label(new Rect(x, y - 30, 900, 24), notes, _label);

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
