// Оружие в руке (перенос combat/weapon_visual.gd): модель из WeaponShapes в
// хвате правой кисти фигуры. Видно и чужим: выбор оружия везёт
// NetPlayer.WeaponHeld.
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
            var figure = GetComponentInChildren<Figure>();
            if (figure != null && figure.HandR != null) Hold(_view, figure.HandR, _combat.Weapon);
            else
            {
                _view.SetParent(transform, false);
                _view.localPosition = Hand;
            }
        }

        /// Тело собрано заново (сменилась сторона) — оружие в руку заново.
        public void Refresh()
        {
            if (_view != null) Destroy(_view.gameObject);
            _view = null;
            _shown = null;
        }

        /// В хвате кисти: клинок смотрит вперёд, пока рука опущена, и вверх при замахе.
        public static void Hold(Transform weapon, Transform hand, WeaponKind kind)
        {
            weapon.SetParent(hand, false);
            weapon.localPosition = Vector3.zero;
            bool held = kind == WeaponKind.Bow || kind == WeaponKind.Spell;
            weapon.localRotation = held ? Quaternion.identity : Quaternion.Euler(55f, 0f, 0f);
        }

        /// Модель оружия — WeaponShapes.
        public static Transform Build(WeaponKind kind) { return WeaponShapes.Build(kind); }
    }
}
