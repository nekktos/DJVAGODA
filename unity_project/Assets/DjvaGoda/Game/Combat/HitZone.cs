// Зона попадания на персонаже или бойце (перенос combat/hit_zone.gd).
//
// Зоны — триггеры на отдельном слое «Hitbox»: поиск целей ударом и снарядом
// не цепляет ни землю, ни капсулу самого персонажа. Ключ зоны (head, torso,
// arm_l, arm_r, leg_l, leg_r) — тот же, что у правил ядра: по нему считаются
// множитель урона (UnitStats.ZoneMultiplier) и судьба конечности (BodyState).
//
// Пока тело — капсула-заглушка, зоны — коробки по пропорциям человека от ног;
// с моделями автора они переедут на кости (как rig.gd в Godot-версии).
using UnityEngine;

namespace DjvaGoda.Game
{
    public class HitZone : MonoBehaviour
    {
        public const string LayerName = "Hitbox";
        /// Слой, на котором стоят персонажи и бойцы: снаряды и лучи прицела по
        /// миру его не видят — по живым бьют только зоны.
        public const string CharacterLayerName = "Characters";

        public string Zone = "torso";
        public Actor Owner;

        public static int Layer { get { return Named(LayerName); } }
        public static int CharacterLayer { get { return Named(CharacterLayerName); } }

        /// Слои заведены в настройках проекта (TagManager); нет — ошибка, слой 0.
        static int Named(string name)
        {
            int layer = LayerMask.NameToLayer(name);
            if (layer >= 0) return layer;
            Debug.LogError("Нет слоя «" + name + "» в настройках проекта (Tags and Layers).");
            return 0;
        }
        public static int Mask { get { return 1 << Layer; } }

        /// Мир для снарядов: всё, кроме персонажей и зон (их ищут отдельно).
        public static int WorldMask { get { return ~((1 << Layer) | (1 << CharacterLayer) | (1 << 2)); } }

        /// Разметка человека от ног: голова, тело, руки, ноги.
        public static void Humanoid(Transform root, Actor owner)
        {
            root.gameObject.layer = CharacterLayer;
            var holder = new GameObject("Зоны попадания").transform;
            holder.SetParent(root, false);
            Add(holder, owner, "head", new Vector3(0f, 1.62f, 0f), new Vector3(0.32f, 0.34f, 0.32f));
            Add(holder, owner, "torso", new Vector3(0f, 1.12f, 0f), new Vector3(0.5f, 0.64f, 0.34f));
            Add(holder, owner, "arm_l", new Vector3(-0.36f, 1.12f, 0f), new Vector3(0.18f, 0.66f, 0.2f));
            Add(holder, owner, "arm_r", new Vector3(0.36f, 1.12f, 0f), new Vector3(0.18f, 0.66f, 0.2f));
            Add(holder, owner, "leg_l", new Vector3(-0.13f, 0.4f, 0f), new Vector3(0.2f, 0.8f, 0.22f));
            Add(holder, owner, "leg_r", new Vector3(0.13f, 0.4f, 0f), new Vector3(0.2f, 0.8f, 0.22f));
        }

        static void Add(Transform holder, Actor owner, string zone, Vector3 centre, Vector3 size)
        {
            var go = new GameObject(zone);
            go.layer = Layer;
            go.transform.SetParent(holder, false);
            go.transform.localPosition = centre;
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = size;
            var hit = go.AddComponent<HitZone>();
            hit.Zone = zone;
            hit.Owner = owner;
        }
    }
}
