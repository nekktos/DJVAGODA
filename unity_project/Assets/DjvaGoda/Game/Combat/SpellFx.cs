// Вспышка заклинания (перенос effects.gd: druid): только картинка, на игру не
// влияет. Светящаяся сфера цвета заклинания (DjvaGoda/Glow) растёт и гаснет
// за полсекунды.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class SpellFx : MonoBehaviour
    {
        const float Life = 0.5f;
        float _age;
        float _size;

        public static void Show(AbilityKind kind, Vector3 at)
        {
            var go = new GameObject("Вспышка: " + Abilities.NameOf(kind));
            go.transform.position = at + Vector3.up;
            bool villain = kind == AbilityKind.Paralysis || kind == AbilityKind.Wither || kind == AbilityKind.Blind;
            string glow = villain ? "curse" : kind == AbilityKind.Heal ? "heal" : kind == AbilityKind.Rally ? "rally" : "nature";
            BodyShapes.Part(go.transform, "Сфера", BodyShapes.Ellipsoid(16, 10), "dark_metal", Vector3.zero, Vector3.one)
                .GetComponent<MeshRenderer>().sharedMaterial = Palette.Glow(glow);
            var fx = go.AddComponent<SpellFx>();
            fx._size = kind == AbilityKind.Heal || kind == AbilityKind.Rally ? Abilities.RangeOf(kind) * 0.5f : 2.5f;
        }

        void Update()
        {
            _age += Time.deltaTime;
            float t = _age / Life;
            transform.localScale = Vector3.one * Mathf.Lerp(0.5f, _size, t);
            if (t >= 1f) Destroy(gameObject);
        }
    }
}
