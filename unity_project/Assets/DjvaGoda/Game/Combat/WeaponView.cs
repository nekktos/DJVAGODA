// Оружие в руке (перенос combat/weapon_visual.gd) — пока заглушка из
// примитивов: меч — клинок, топор и молот — рукоять с бойком, лук и арбалет —
// дуга-палка, огненный шар — светящийся шар в ладони. Видно и чужим: выбор
// оружия везёт NetPlayer.WeaponHeld.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(PlayerCombat))]
    public class WeaponView : MonoBehaviour
    {
        static readonly Vector3 Hand = new Vector3(0.42f, 1.05f, 0.25f);

        PlayerCombat _combat;
        PlayerCharacter _character;
        Transform _view;
        WeaponKind? _shown;

        void Awake()
        {
            _combat = GetComponent<PlayerCombat>();
            _character = GetComponent<PlayerCharacter>();
        }

        void LateUpdate()
        {
            bool visible = _character.Alive && _character.Body.CanAttackMelee();
            if (_view != null) _view.gameObject.SetActive(visible);
            if (_shown == _combat.Weapon) return;
            _shown = _combat.Weapon;
            if (_view != null) Destroy(_view.gameObject);
            _view = Build(_combat.Weapon);
            _view.SetParent(transform, false);
            _view.localPosition = Hand;
        }

        static Transform Build(WeaponKind kind)
        {
            var root = new GameObject("Оружие: " + Weapons.Names[(int)kind]).transform;
            switch (kind)
            {
                case WeaponKind.Sword:
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0.45f, 0f), new Vector3(0.06f, 0.9f, 0.02f), "stone");
                    Part(root, PrimitiveType.Cube, Vector3.zero, new Vector3(0.22f, 0.04f, 0.05f), "dark_stone");
                    break;
                case WeaponKind.Axe:
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0.35f, 0f), new Vector3(0.04f, 0.7f, 0.04f), "wood");
                    Part(root, PrimitiveType.Cube, new Vector3(0.08f, 0.62f, 0f), new Vector3(0.18f, 0.16f, 0.03f), "stone");
                    break;
                case WeaponKind.Hammer:
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0.4f, 0f), new Vector3(0.05f, 0.8f, 0.05f), "wood");
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0.78f, 0f), new Vector3(0.3f, 0.16f, 0.16f), "dark_stone");
                    break;
                case WeaponKind.Bow:
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0.1f, 0f), new Vector3(0.03f, 1.1f, 0.04f), "wood");
                    break;
                case WeaponKind.Crossbow:
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0f, 0.2f), new Vector3(0.06f, 0.06f, 0.6f), "wood");
                    Part(root, PrimitiveType.Cube, new Vector3(0f, 0f, 0.45f), new Vector3(0.6f, 0.03f, 0.04f), "dark_stone");
                    break;
                default:
                    Part(root, PrimitiveType.Sphere, new Vector3(0f, 0.12f, 0.05f), Vector3.one * 0.2f, "accent");
                    break;
            }
            return root;
        }

        static void Part(Transform root, PrimitiveType shape, Vector3 at, Vector3 size, string material)
        {
            var go = GameObject.CreatePrimitive(shape);
            Destroy(go.GetComponent<Collider>());
            go.transform.SetParent(root, false);
            go.transform.localPosition = at;
            go.transform.localScale = size;
            go.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of(material);
        }
    }
}
